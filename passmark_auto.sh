#!/bin/bash
# --- Passmark PerformanceTest Ultimate Diagnostic Script (v3 - Automated Non-Interactive) ---
#
# Purpose:
#   Fully automated, non-interactive downloader/installer/runner for
#   PassMark PerformanceTest Linux build. The script attempts to resolve
#   library compatibility issues (ncurses), downloads the correct
#   PassMark package for the host architecture, runs the test in
#   non-interactive mode, and formats a concise report from results*.yml.
#
# Usage:
#   Make executable and run on a Linux machine with network access:
#     chmod +x passmark_auto.sh
#     sudo ./passmark_auto.sh
#
# Notes / Requirements:
#   - Requires root privileges to install packages (apt/yum/dnf) when
#     resolving dependencies. The script detects apt/yum/dnf.
#   - Needs `wget`, `unzip`, `dpkg` (or equivalents) to be available or
#     installable via the system package manager.
#   - On modern distros the script will attempt to install `libncurses5`
#     or `ncurses-compat-libs`. If unavailable, it will extract required
#     compatibility libraries from .deb files and place them next to the
#     PassMark executable.
#   - The script is intended for non-interactive benchmarking (-r 3 is
#     used by default). Adjust the `eval` invocation later in the file
#     if you need different flags.
#
set -e

# 0. Define necessary variables
TEMP_DIR="passmark_auto_test_$$"
PT_LINUX_ARCH=""
EXECUTABLE_NAME="" # The name of the final executable
LD_PATH_PREFIX=""
LIB_PATH_DIR=""    # Sub-path where libncurses.so.5 resides

# --- 1. Auto-detect package manager and install base dependencies ---
echo "--- Installing base dependencies (wget, unzip, dpkg) ---"
if command -v apt >/dev/null; then
    PKG_MGR="apt"
    apt-get update -y >/dev/null
    apt-get install -y wget unzip dpkg >/dev/null 2>&1
elif command -v yum >/dev/null; then
    PKG_MGR="yum"
    yum install -y wget unzip dpkg >/dev/null 2>&1
elif command -v dnf >/dev/null; then
    PKG_MGR="dnf"
    dnf install -y wget unzip dpkg >/dev/null 2>&1
else
    echo "FATAL ERROR: Could not find a supported package manager (apt/yum/dnf)."
    exit 1
fi

# 2. Create and enter temporary directory
mkdir "$TEMP_DIR" && cd "$TEMP_DIR"
echo "--- Temporary working directory created: $(pwd) ---"

# 3. Identify system architecture and handle ncurses compatibility dependencies
ARCH_TYPE=$(uname -m)
if [ "$ARCH_TYPE" = "x86_64" ]; then 
    PT_LINUX_ARCH="x64"
    LIB_PATH_DIR="x86_64-linux-gnu"
    echo "--- Detected architecture: x86_64, attempting to resolve libncurses.so.5 dependency ---"
    
    # Try installing libncurses5 with package manager (manual extraction if fail)
    if [ "$PKG_MGR" = "apt" ] && apt-get install -y libncurses5 >/dev/null 2>&1; then
        echo "libncurses5 dependency installed via apt."
    elif [ "$PKG_MGR" = "yum" ] || [ "$PKG_MGR" = "dnf" ]; then
        (yum install -y ncurses-compat-libs >/dev/null 2>&1 || dnf install -y ncurses-compat-libs >/dev/null 2>&1)
        echo "ncurses-compat-libs dependency installed via $PKG_MGR."
    else
        echo "Attempting manual ncurses library extraction..."
        # Manually extract library files from .deb package
        wget -q http://archive.ubuntu.com/ubuntu/pool/universe/n/ncurses/libncursesw5_6.3-2ubuntu0.1_amd64.deb
        wget -q http://archive.ubuntu.com/ubuntu/pool/universe/n/ncurses/libtinfo5_6.3-2_amd64.deb
        dpkg-deb -xv libncursesw5_6.3-2ubuntu0.1_amd64.deb n_temp
        dpkg-deb -xv libtinfo5_6.3-2_amd64.deb t_temp
        
        # Find and rename required library files to the current directory (this is the critical compatibility fix)
        NCURSES_LIB_ORIG=$(find n_temp -name "libncursesw.so.5.9")
        TINFO_LIB_ORIG=$(find t_temp -name "libtinfo.so.5.9")

        if [ -z "$NCURSES_LIB_ORIG" ] || [ -z "$TINFO_LIB_ORIG" ]; then 
            echo "FATAL ERROR: Manual ncurses library extraction failed!"; exit 1; 
        fi
        
        mv "$NCURSES_LIB_ORIG" libncurses.so.5
        mv "$TINFO_LIB_ORIG" libtinfo.so.5
        echo "ncurses library files libncurses.so.5 and libtinfo.so.5 extracted successfully."
    fi
elif [ "$ARCH_TYPE" = "aarch64" ]; then 
    PT_LINUX_ARCH="arm64"
    LIB_PATH_DIR="aarch64-linux-gnu"
    echo "--- Detected architecture: aarch64 (adjust manual extraction logic as needed) ---"
    # aarch64 manual extraction logic is omitted here, assuming package manager works
else 
    echo "FATAL ERROR: Unsupported system architecture: $ARCH_TYPE"; exit 1; 
fi

# 4. Download, unzip, and prepare the Passmark main program
ZIP_FILE="pt_linux_$PT_LINUX_ARCH.zip"
echo "--- Downloading Passmark test tool ($PT_LINUX_ARCH) ---"
wget -O "$ZIP_FILE" "https://www.passmark.com/downloads/pt_linux_$PT_LINUX_ARCH.zip"
if [ ! -s "$ZIP_FILE" ]; then echo "FATAL ERROR: File download failed or file is empty!"; exit 1; fi

unzip -q "$ZIP_FILE"
EXECUTABLE_PATH=$(find PerformanceTest -type f -name "pt_linux*" -o -type f -name "PerformanceTest*" | head -n 1)
EXECUTABLE_NAME=$(basename "$EXECUTABLE_PATH")

if [ -z "$EXECUTABLE_NAME" ]; then echo "FATAL ERROR: Could not automatically find Passmark executable!"; exit 1; fi
chmod +x "$EXECUTABLE_PATH"
echo "Executable found: $EXECUTABLE_NAME"

# 5. Unify library file location and set execution environment
cd PerformanceTest # Enter the PerformanceTest directory

if [ -f ../libncurses.so.5 ]; then
    echo "Moving ncurses compatibility libraries to the same directory as the executable..."
    mv ../libncurses.so.5 .
    mv ../libtinfo.so.5 .
    # Set LD_LIBRARY_PATH to current directory (.), and set TERM variable
    LD_PATH_PREFIX="TERM=xterm LD_LIBRARY_PATH=."
    echo "LD_LIBRARY_PATH=. has been set."
else
    # If installed via package manager, only the TERM variable needs to be set
    LD_PATH_PREFIX="TERM=xterm"
fi

echo "Working directory switched to: $(pwd)"

# 6. Start non-interactive test (safe background mode)
echo ""
echo "-------------------------------------------"
echo "--- Starting Passmark non-interactive test (-r 3) ---"
echo "--- Please wait, the program will exit automatically after all tests are complete. ---"
echo "-------------------------------------------"
sleep 2

# Define a variable to save the raw test output
RAW_RESULT_FILE="passmark_raw_output.log"

# Use eval command to safely execute the command with environment variable prefix
eval $LD_PATH_PREFIX "./$EXECUTABLE_NAME" -r 3
echo "--- Passmark program: all tests finished, returned automatically. ---"

# Loop to check if the process is still running
while pgrep -f -x "$EXECUTABLE_NAME" > /dev/null; do
    if [ -f "results_all.yml" ]; then
        echo "--- WARNING: results_all.yml already exists, process will be forcibly terminated! ---"
        # Forcibly kill the process (using pkill -f -x for long process names)
        pkill -9 -f -x "$EXECUTABLE_NAME"
        cat results_all.yml
        echo "Process $EXECUTABLE_NAME has been forcibly terminated."
        break
    fi
    # Check every 5 seconds
    sleep 5
    SECONDS=$((SECONDS + 5))
done


echo "--- Passmark program: all tests finished or terminated. ---"


#RESULTS_YML_FILE=results_all.yml

YML_FILES=(results*.yml)
RESULTS_YML_FILE="${YML_FILES[0]}"

if [ -f "$RESULTS_YML_FILE" ]; then
    echo "--- Passmark program: all tests finished, returned automatically. ---"
    echo ""
    
    # 7. Format and output results (new logic)
    # ----------------------------------------
    echo "--- Diagnostic Results (Formatted) ---"
    
    # Define result extraction function
    # get_value(key)
    # - Purpose: Extract the value for a YAML key from the PassMark results
    #   file (results*.yml). Handles multi-word values and optional
    #   searching within the "SystemInformation:" block for processor/
    #   memory related keys.
    # - Input: one string argument matching the YAML key (e.g., "Processor:", "Memory:").
    # - Output: the matched value printed to stdout (no trailing commas/CRs).
    # - Example: P_NAME=$(get_value "Processor:")
    get_value() {
        # Use grep -A to find the SystemInformation: block, otherwise search the entire file
        if [[ "$1" =~ "Processor:" || "$1" =~ "NumCores:" || "$1" =~ "Memory:" || "$1" =~ "CPUFrequency:" ]]; then
            grep -A 10 "SystemInformation:" "$RESULTS_YML_FILE" | grep -m 1 "^[[:space:]]*$1"
        else
            grep -m 1 "^[[:space:]]*$1" "$RESULTS_YML_FILE"
        fi | awk '{
            # Concatenate multi-word key values, e.g., Processor: AMD EPYC 7B13
            if (NF > 2) {
                result=$2
                for (i=3; i<=NF; i++) result=result " "$i
                print result
            } else {
                print $NF
            }
        }' | tr -d '\r,'
    }
    
    # Define score extraction function (handles decimal points and rounding)
    # get_score(key)
    # - Purpose: Request a key from get_value and normalize/format numeric
    #   score output for display.
    # - Input: one string argument matching the YAML score key (e.g., "SUMM_CPU:").
    # - Behavior: Rounds to integer by default; some keys (e.g., CPU_PRIME:)
    #   are displayed with one decimal place. Non-numeric values return
    #   "N/A".
    # - Output: formatted value printed to stdout.
    # - Example: CPU_MARK=$(get_score "SUMM_CPU:")
    get_score() {
        local KEY_VALUE
        KEY_VALUE=$(get_value "$1")
        echo "$KEY_VALUE" | awk '
        {
            # Use int($1+0.5) for rounding
            if ($1 ~ /^[0-9.]*$/) {
                if ("'$1'" == "CPU_PRIME:") {
                    printf "%.1f", $1
                } else {
                    printf "%.0f", $1
                }
            } else {
                print "N/A"
            }
        }'
    }

    # --- Extract System Information ---
    V_MAJOR=$(get_value Major:)
    V_MINOR=$(get_value Minor:)
    V_BUILD=$(get_value Build:)
    P_NAME=$(get_value Processor:)
    V_ARCH=$(get_value ptArchitecture: | sed 's/_linux$//')
    P_CORES=$(get_value NumCores:)
    P_FREQ_RAW=$(get_value CPUFrequency:)
    R_MEM_MB=$(get_value Memory:)
    P_NUM_TESTS=$(get_value NumTestProcesses:)

    # --- Process System Information (fixing line with awk syntax error) ---
    PT_VERSION="${V_MAJOR}.${V_MINOR}.${V_BUILD}"
    PT_FREQ="${P_FREQ_RAW} MHz"
    # Fixed code: use -v to pass variables, and single quotes for the awk script
    PT_MEM_GIB=$(awk -v mem="$R_MEM_MB" 'BEGIN {if (mem > 0) printf "%.1f", mem/1024; else print "0"}')
    PT_MEM_DISPLAY="${PT_MEM_GIB} GiB RAM"
    PT_PROCESSES="Number of Processes: ${P_NUM_TESTS}"
    PT_ITERATIONS="Test Iterations: 1" 
    PT_DURATION="Test Duration: Medium" 

    # --- Extract performance scores and sub-test results ---
    CPU_MARK=$(get_score SUMM_CPU:)
    ME_MARK=$(get_score SUMM_ME:)
    
    CPU_INT=$(get_score CPU_INTEGER_MATH:)
    CPU_FP=$(get_score CPU_FLOATINGPOINT_MATH:)
    CPU_PRIME=$(get_score CPU_PRIME:)
    CPU_SORT=$(get_score CPU_SORTING:)
    CPU_ENC=$(get_score CPU_ENCRYPTION:)
    CPU_COMP=$(get_score CPU_COMPRESSION:)
    CPU_ST=$(get_score CPU_SINGLETHREAD:)
    CPU_PHYSICS=$(get_score CPU_PHYSICS:)
    CPU_SSE=$(get_score CPU_MATRIX_MULT_SSE:) # Corresponds to Extended Instructions (SSE)

    ME_ALLOC=$(get_score ME_ALLOC_S:)
    ME_READ_C=$(get_score ME_READ_S:)
    ME_READ_U=$(get_score ME_READ_L:)
    ME_WRITE=$(get_score ME_WRITE:)
    ME_AVAIL=$(get_score ME_LARGE:)
    ME_LATENCY=$(get_score ME_LATENCY:)
    ME_THREADED_VAL=$(get_score ME_THREADED:)


    # 8. Formatted Output (using printf for alignment)
    echo ""
    printf "%60s\n" "PassMark PerformanceTest Linux (${PT_VERSION})"
    echo ""
    printf "%s (%s)\n" "$P_NAME" "$V_ARCH"
    printf "%s cores @ %s  |  %s\n" "$P_CORES" "$PT_FREQ" "$PT_MEM_DISPLAY"
    printf "%s  |  %s  |  %s\n" "$PT_PROCESSES" "$PT_ITERATIONS" "$PT_DURATION"
    echo "--------------------------------------------------------------------------------"

    # CPU Results
    printf "%-35s%-30s\n" "CPU Mark:" "$CPU_MARK"
    printf "%-35s%-30s\n" "  Integer Math" "$CPU_INT Million Operations/s"
    printf "%-35s%-30s\n" "  Floating Point Math" "$CPU_FP Million Operations/s"
    printf "%-35s%-30s\n" "  Prime Numbers" "$CPU_PRIME Million Primes/s"
    printf "%-35s%-30s\n" "  Sorting" "$CPU_SORT Thousand Strings/s"
    printf "%-35s%-30s\n" "  Encryption" "$CPU_ENC MB/s"
    printf "%-35s%-30s\n" "  Compression" "$CPU_COMP KB/s"
    printf "%-35s%-30s\n" "  CPU Single Threaded" "$CPU_ST Million Operations/s"
    printf "%-35s%-30s\n" "  Physics" "$CPU_PHYSICS Frames/s"
    printf "%-35s%-30s\n" "  Extended Instructions (SSE)" "$CPU_SSE Million Matrices/s"

    echo ""

    # Memory Results
    printf "%-35s%-30s\n" "Memory Mark:" "$ME_MARK"
    printf "%-35s%-30s\n" "  Database Operations" "$ME_ALLOC Thousand Operations/s"
    printf "%-35s%-30s\n" "  Memory Read Cached" "$ME_READ_C MB/s"
    printf "%-35s%-30s\n" "  Memory Read Uncached" "$ME_READ_U MB/s"
    printf "%-35s%-30s\n" "  Memory Write" "$ME_WRITE MB/s"
    printf "%-35s%-30s\n" "  Available RAM" "$ME_AVAIL Megabytes"
    printf "%-35s%-30s\n" "  Memory Latency" "$ME_LATENCY Nanoseconds"
    printf "%-35s%-30s\n" "  Memory Threaded" "$ME_THREADED_VAL MB/s" 
    echo "--------------------------------------------------------------------------------"
    
else
    echo "FATAL ERROR: Passmark test program failed to run or did not generate a results file (results*.yml)."
    echo "Please check the raw output ($RAW_RESULT_FILE) for error information."
    cat "$RAW_RESULT_FILE"
    exit 1
fi


# 9. Cleanup
echo ""
echo "-------------------------------------------"
echo "--- Cleaning up temporary files ---"
cd ../..
rm -rf "$TEMP_DIR"
echo "Temporary directory $TEMP_DIR cleaned up."
echo "-------------------------------------------"
