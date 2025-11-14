#!/bin/bash
# PassMark PerformanceTest diagnostic script (v3 - automated non-interactive)
set -euo pipefail

# 0. Define necessary variables
TEMP_DIR="passmark_auto_test_$$"
PT_LINUX_ARCH=""
EXECUTABLE_PATH=""
EXECUTABLE_NAME="" # Name of the final executable file
LD_PATH_PREFIX=""
RAW_RESULT_FILE="passmark_raw_output.log"

# 1. Auto-detect package manager and ensure base utilities are available
echo "--- Installing base dependencies (wget, unzip, dpkg) ---"
PKG_MGR=""
if command -v apt >/dev/null 2>&1; then
    PKG_MGR="apt"
    apt-get update -y >/dev/null
    apt-get install -y wget unzip dpkg >/dev/null 2>&1
elif command -v yum >/dev/null 2>&1; then
    PKG_MGR="yum"
    yum install -y wget unzip dpkg >/dev/null 2>&1
elif command -v dnf >/dev/null 2>&1; then
    PKG_MGR="dnf"
    dnf install -y wget unzip dpkg >/dev/null 2>&1
else
    echo "Fatal error: no supported package manager found (apt/yum/dnf)." >&2
    exit 1
fi

# 2. Create temporary directory and enter it
mkdir -p "$TEMP_DIR" && cd "$TEMP_DIR"
echo "--- Temporary working directory created: $(pwd) ---"

# 3. Detect system architecture and handle ncurses compatibility dependencies
ARCH_TYPE=$(uname -m)
if [ "$ARCH_TYPE" = "x86_64" ]; then
    PT_LINUX_ARCH="x64"
    echo "--- Detected architecture: x86_64 ---"
    # Try installing libncurses5 or compatibility libraries; fall back to manual extraction
    if [ "$PKG_MGR" = "apt" ] && apt-get install -y libncurses5 >/dev/null 2>&1; then
        echo "libncurses5 installed via apt."
    elif [ "$PKG_MGR" = "yum" ] || [ "$PKG_MGR" = "dnf" ]; then
        (yum install -y ncurses-compat-libs >/dev/null 2>&1 || dnf install -y ncurses-compat-libs >/dev/null 2>&1)
        echo "ncurses-compat-libs installed via $PKG_MGR."
    else
        echo "Attempting manual extraction of ncurses libraries..."
        # Download .deb packages and extract the needed libraries
        wget -q http://archive.ubuntu.com/ubuntu/pool/universe/n/ncurses/libncursesw5_6.3-2ubuntu0.1_amd64.deb
        wget -q http://archive.ubuntu.com/ubuntu/pool/universe/n/ncurses/libtinfo5_6.3-2_amd64.deb
        dpkg-deb -xv libncursesw5_6.3-2ubuntu0.1_amd64.deb n_temp >/dev/null 2>&1 || true
        dpkg-deb -xv libtinfo5_6.3-2_amd64.deb t_temp >/dev/null 2>&1 || true

        NCURSES_LIB_ORIG=$(find n_temp -type f -name "libncursesw.so*" | head -n1 || true)
        TINFO_LIB_ORIG=$(find t_temp -type f -name "libtinfo.so*" | head -n1 || true)

        if [ -z "$NCURSES_LIB_ORIG" ] || [ -z "$TINFO_LIB_ORIG" ]; then
            echo "Fatal error: manual extraction of ncurses library files failed!" >&2
            exit 1
        fi

        mv "$NCURSES_LIB_ORIG" libncurses.so.5
        mv "$TINFO_LIB_ORIG" libtinfo.so.5
        echo "ncurses libraries libncurses.so.5 and libtinfo.so.5 extracted."
    fi
elif [ "$ARCH_TYPE" = "aarch64" ]; then
    PT_LINUX_ARCH="arm64"
    echo "--- Detected architecture: aarch64 ---"
    # For aarch64, prefer package manager; manual extraction not implemented here
    if [ "$PKG_MGR" = "apt" ]; then
        apt-get install -y libncurses5 >/dev/null 2>&1 || true
    else
        (yum install -y ncurses-compat-libs >/dev/null 2>&1 || dnf install -y ncurses-compat-libs >/dev/null 2>&1) || true
    fi
else
    echo "Fatal error: unsupported system architecture: $ARCH_TYPE" >&2
    exit 1
fi

# 4. Download, unzip and prepare the Passmark main program
ZIP_FILE="pt_linux_${PT_LINUX_ARCH}.zip"
echo "--- Downloading Passmark test tool ($PT_LINUX_ARCH) ---"
wget -O "$ZIP_FILE" "https://www.passmark.com/downloads/pt_linux_${PT_LINUX_ARCH}.zip"
if [ ! -s "$ZIP_FILE" ]; then
    echo "Fatal error: file download failed or file is empty!" >&2
    exit 1
fi

unzip -q "$ZIP_FILE"
EXECUTABLE_PATH=$(find PerformanceTest -type f \( -name "pt_linux*" -o -name "PerformanceTest*" \) | head -n 1 || true)
EXECUTABLE_NAME=$(basename "$EXECUTABLE_PATH" 2>/dev/null || true)

if [ -z "$EXECUTABLE_NAME" ] || [ ! -f "$EXECUTABLE_PATH" ]; then
    echo "Fatal error: failed to automatically find Passmark executable!" >&2
    exit 1
fi
chmod +x "$EXECUTABLE_PATH"
echo "Found executable: $EXECUTABLE_NAME"

# 5. Consolidate library files and set up the execution environment
cd PerformanceTest || exit 1

if [ -f ../libncurses.so.5 ]; then
    echo "Moving ncurses compatibility libraries to the executable's directory..."
    mv ../libncurses.so.5 . || true
    mv ../libtinfo.so.5 . || true
    LD_PATH_PREFIX="TERM=xterm LD_LIBRARY_PATH=."
    echo "LD_LIBRARY_PATH set to current directory."
else
    # If system libraries are already installed, only set TERM
    LD_PATH_PREFIX="TERM=xterm"
fi

echo "Working directory: $(pwd)"

# 6. Launch non-interactive test (run in background and capture raw output)
echo "-------------------------------------------"
echo "--- Starting Passmark non-interactive test (-r 3) ---"
echo "--- Please wait; the program will exit automatically when all tests complete. ---"
echo "-------------------------------------------"
sleep 1

# Run executable in background and capture output
eval $LD_PATH_PREFIX "./$EXECUTABLE_NAME" -r 3 >"$RAW_RESULT_FILE" 2>&1 &
EXEC_PID=$!
echo "Passmark started with PID $EXEC_PID (logging to $RAW_RESULT_FILE)."

# Wait for the process to finish or for results file to appear
while kill -0 "$EXEC_PID" >/dev/null 2>&1; do
    if [ -f "results_all.yml" ]; then
        echo "Warning: results_all.yml already exists; will forcibly terminate the process."
        pkill -9 -f -x "$EXECUTABLE_NAME" >/dev/null 2>&1 || true
        cat results_all.yml
        echo "Process $EXECUTABLE_NAME has been terminated."
        break
    fi
    sleep 5
done

echo "All Passmark tests have completed or been terminated."

# Locate results YAML file
YML_FILES=(results*.yml)
RESULTS_YML_FILE="${YML_FILES[0]}"

if [ -f "$RESULTS_YML_FILE" ]; then
    echo "--- All PassMark tests completed. ---"
    echo ""
    echo "--- Diagnostic results (formatted) ---"

    # Define a function to extract values from the results
    # $1: Key to search for (e.g., "Major:", "Processor:")
    get_value() {
        if [[ "$1" =~ "Processor:" || "$1" =~ "NumCores:" || "$1" =~ "Memory:" || "$1" =~ "CPUFrequency:" ]]; then
            grep -A 10 "SystemInformation:" "$RESULTS_YML_FILE" | grep -m 1 "^[[:space:]]*$1"
        else
            grep -m 1 "^[[:space:]]*$1" "$RESULTS_YML_FILE"
        fi | awk '{
            # Concatenate multi-word key values, e.g., Processor: AMD EPYC 7B13
            if (NF > 2) {
                result=$2
                for (i=3; i<=NF; i++) result=result " " $i
                print result
            } else {
                print $NF
            }
        }' | tr -d '\r,'
    }

    # Define a function to extract scores (handle decimals and rounding)
    # $1: Key to search for (e.g., SUMM_CPU:)
    get_score() {
        local KEY_VALUE
        KEY_VALUE=$(get_value "$1")
        echo "$KEY_VALUE" | awk '
        {
            # Use int($1+0.5) to perform rounding
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

    # Extract system information
    V_MAJOR=$(get_value Major:)
    V_MINOR=$(get_value Minor:)
    V_BUILD=$(get_value Build:)
    P_NAME=$(get_value Processor:)
    V_ARCH=$(get_value ptArchitecture: | sed 's/_linux$//')
    P_CORES=$(get_value NumCores:)
    P_FREQ_RAW=$(get_value CPUFrequency:)
    R_MEM_MB=$(get_value Memory:)
    P_NUM_TESTS=$(get_value NumTestProcesses:)

    # Process system information
    PT_VERSION="${V_MAJOR}.${V_MINOR}.${V_BUILD}"
    PT_FREQ="${P_FREQ_RAW} MHz"
    PT_MEM_GIB=$(awk -v mem="$R_MEM_MB" 'BEGIN {if (mem > 0) printf "%.1f", mem/1024; else print "0"}')
    PT_MEM_DISPLAY="${PT_MEM_GIB} GiB RAM"
    PT_PROCESSES="Number of Processes: ${P_NUM_TESTS}"
    PT_ITERATIONS="Test Iterations: 1"
    PT_DURATION="Test Duration: Medium"

    # Extract performance scores and subtest results
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
    CPU_SSE=$(get_score CPU_MATRIX_MULT_SSE:)

    ME_ALLOC=$(get_score ME_ALLOC_S:)
    ME_READ_C=$(get_score ME_READ_S:)
    ME_READ_U=$(get_score ME_READ_L:)
    ME_WRITE=$(get_score ME_WRITE:)
    ME_AVAIL=$(get_score ME_LARGE:)
    ME_LATENCY=$(get_score ME_LATENCY:)
    ME_THREADED_VAL=$(get_score ME_THREADED:)

    # Format output (align using printf)
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
    echo "Fatal error: Passmark test program failed to run or did not generate result file (results*.yml)." >&2
    echo "Please check the raw output ($RAW_RESULT_FILE) for error information." >&2
    [ -f "$RAW_RESULT_FILE" ] && sed -n '1,200p' "$RAW_RESULT_FILE" || true
    exit 1
fi

# Cleanup
echo ""
echo "-------------------------------------------"
echo "--- Cleaning up temporary files ---"
cd ../..
rm -rf "$TEMP_DIR"
echo "Temporary directory $TEMP_DIR has been cleaned up."
echo "-------------------------------------------"
#!/bin/bash
# PassMark PerformanceTest diagnostic script (v3 - automated non-interactive)
set -euo pipefail

# 0. Define necessary variables
TEMP_DIR="passmark_auto_test_$$"
PT_LINUX_ARCH=""
EXECUTABLE_PATH=""
EXECUTABLE_NAME="" # Name of the final executable file
LD_PATH_PREFIX=""
RAW_RESULT_FILE="passmark_raw_output.log"

# 1. Auto-detect package manager and ensure base utilities are available
echo "--- Installing base dependencies (wget, unzip, dpkg) ---"
PKG_MGR=""
if command -v apt >/dev/null 2>&1; then
    PKG_MGR="apt"
    apt-get update -y >/dev/null
    apt-get install -y wget unzip dpkg >/dev/null 2>&1
elif command -v yum >/dev/null 2>&1; then
    PKG_MGR="yum"
    yum install -y wget unzip dpkg >/dev/null 2>&1
elif command -v dnf >/dev/null 2>&1; then
    PKG_MGR="dnf"
    dnf install -y wget unzip dpkg >/dev/null 2>&1
else
    echo "Fatal error: no supported package manager found (apt/yum/dnf)." >&2
    exit 1
fi

# 2. Create temporary directory and enter it
mkdir -p "$TEMP_DIR" && cd "$TEMP_DIR"
echo "--- Temporary working directory created: $(pwd) ---"

# 3. Detect system architecture and handle ncurses compatibility dependencies
ARCH_TYPE=$(uname -m)
if [ "$ARCH_TYPE" = "x86_64" ]; then
    PT_LINUX_ARCH="x64"
    echo "--- Detected architecture: x86_64 ---"
    # Try installing libncurses5 or compatibility libraries; fall back to manual extraction
    if [ "$PKG_MGR" = "apt" ] && apt-get install -y libncurses5 >/dev/null 2>&1; then
        echo "libncurses5 installed via apt."
    elif [ "$PKG_MGR" = "yum" ] || [ "$PKG_MGR" = "dnf" ]; then
        (yum install -y ncurses-compat-libs >/dev/null 2>&1 || dnf install -y ncurses-compat-libs >/dev/null 2>&1)
        echo "ncurses-compat-libs installed via $PKG_MGR."
    else
        echo "Attempting manual extraction of ncurses libraries..."
        # Download .deb packages and extract the needed libraries
        wget -q http://archive.ubuntu.com/ubuntu/pool/universe/n/ncurses/libncursesw5_6.3-2ubuntu0.1_amd64.deb
        wget -q http://archive.ubuntu.com/ubuntu/pool/universe/n/ncurses/libtinfo5_6.3-2_amd64.deb
        dpkg-deb -xv libncursesw5_6.3-2ubuntu0.1_amd64.deb n_temp >/dev/null 2>&1 || true
        dpkg-deb -xv libtinfo5_6.3-2_amd64.deb t_temp >/dev/null 2>&1 || true

        NCURSES_LIB_ORIG=$(find n_temp -type f -name "libncursesw.so*" | head -n1 || true)
        TINFO_LIB_ORIG=$(find t_temp -type f -name "libtinfo.so*" | head -n1 || true)

        if [ -z "$NCURSES_LIB_ORIG" ] || [ -z "$TINFO_LIB_ORIG" ]; then
            echo "Fatal error: manual extraction of ncurses library files failed!" >&2
            exit 1
        fi

        mv "$NCURSES_LIB_ORIG" libncurses.so.5
        mv "$TINFO_LIB_ORIG" libtinfo.so.5
        echo "ncurses libraries libncurses.so.5 and libtinfo.so.5 extracted."
    fi
elif [ "$ARCH_TYPE" = "aarch64" ]; then
    PT_LINUX_ARCH="arm64"
    echo "--- Detected architecture: aarch64 ---"
    # For aarch64, prefer package manager; manual extraction not implemented here
    if [ "$PKG_MGR" = "apt" ]; then
        apt-get install -y libncurses5 >/dev/null 2>&1 || true
    else
        (yum install -y ncurses-compat-libs >/dev/null 2>&1 || dnf install -y ncurses-compat-libs >/dev/null 2>&1) || true
    fi
else
    echo "Fatal error: unsupported system architecture: $ARCH_TYPE" >&2
    exit 1
fi

# 4. Download, unzip and prepare the Passmark main program
ZIP_FILE="pt_linux_${PT_LINUX_ARCH}.zip"
echo "--- Downloading Passmark test tool ($PT_LINUX_ARCH) ---"
wget -O "$ZIP_FILE" "https://www.passmark.com/downloads/pt_linux_${PT_LINUX_ARCH}.zip"
if [ ! -s "$ZIP_FILE" ]; then
    echo "Fatal error: file download failed or file is empty!" >&2
    exit 1
fi

unzip -q "$ZIP_FILE"
EXECUTABLE_PATH=$(find PerformanceTest -type f \( -name "pt_linux*" -o -name "PerformanceTest*" \) | head -n 1 || true)
EXECUTABLE_NAME=$(basename "$EXECUTABLE_PATH" 2>/dev/null || true)

if [ -z "$EXECUTABLE_NAME" ] || [ ! -f "$EXECUTABLE_PATH" ]; then
    echo "Fatal error: failed to automatically find Passmark executable!" >&2
    exit 1
fi
chmod +x "$EXECUTABLE_PATH"
echo "Found executable: $EXECUTABLE_NAME"

# 5. Consolidate library files and set up the execution environment
cd PerformanceTest || exit 1

if [ -f ../libncurses.so.5 ]; then
    echo "Moving ncurses compatibility libraries to the executable's directory..."
    mv ../libncurses.so.5 . || true
    mv ../libtinfo.so.5 . || true
    LD_PATH_PREFIX="TERM=xterm LD_LIBRARY_PATH=."
    echo "LD_LIBRARY_PATH set to current directory."
else
    # If system libraries are already installed, only set TERM
    LD_PATH_PREFIX="TERM=xterm"
fi

echo "Working directory: $(pwd)"

# 6. Launch non-interactive test (run in background and capture raw output)
echo "-------------------------------------------"
echo "--- Starting Passmark non-interactive test (-r 3) ---"
echo "--- Please wait; the program will exit automatically when all tests complete. ---"
echo "-------------------------------------------"
sleep 1

# Run executable in background and capture output
eval $LD_PATH_PREFIX "./$EXECUTABLE_NAME" -r 3 >"$RAW_RESULT_FILE" 2>&1 &
EXEC_PID=$!
echo "Passmark started with PID $EXEC_PID (logging to $RAW_RESULT_FILE)."

# Wait for the process to finish or for results file to appear
while kill -0 "$EXEC_PID" >/dev/null 2>&1; do
    if [ -f "results_all.yml" ]; then
        echo "Warning: results_all.yml already exists; will forcibly terminate the process."
        pkill -9 -f -x "$EXECUTABLE_NAME" >/dev/null 2>&1 || true
        cat results_all.yml
        echo "Process $EXECUTABLE_NAME has been terminated."
        break
    fi
    sleep 5
done

echo "All Passmark tests have completed or been terminated."

# Locate results YAML file
YML_FILES=(results*.yml)
RESULTS_YML_FILE="${YML_FILES[0]}"

if [ -f "$RESULTS_YML_FILE" ]; then
    echo "--- All PassMark tests completed. ---"
    echo ""
    echo "--- Diagnostic results (formatted) ---"

    # Define a function to extract values from the results
    # $1: Key to search for (e.g., "Major:", "Processor:")
    get_value() {
        if [[ "$1" =~ "Processor:" || "$1" =~ "NumCores:" || "$1" =~ "Memory:" || "$1" =~ "CPUFrequency:" ]]; then
            grep -A 10 "SystemInformation:" "$RESULTS_YML_FILE" | grep -m 1 "^[[:space:]]*$1"
        else
            grep -m 1 "^[[:space:]]*$1" "$RESULTS_YML_FILE"
        fi | awk '{
            # Concatenate multi-word key values, e.g., Processor: AMD EPYC 7B13
            if (NF > 2) {
                result=$2
                for (i=3; i<=NF; i++) result=result " " $i
                print result
            } else {
                print $NF
            }
        }' | tr -d '\r,'
    }

    # Define a function to extract scores (handle decimals and rounding)
    # $1: Key to search for (e.g., SUMM_CPU:)
    get_score() {
        local KEY_VALUE
        KEY_VALUE=$(get_value "$1")
        echo "$KEY_VALUE" | awk '
        {
            # Use int($1+0.5) to perform rounding
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

    # Extract system information
    V_MAJOR=$(get_value Major:)
    V_MINOR=$(get_value Minor:)
    V_BUILD=$(get_value Build:)
    P_NAME=$(get_value Processor:)
    V_ARCH=$(get_value ptArchitecture: | sed 's/_linux$//')
    P_CORES=$(get_value NumCores:)
    P_FREQ_RAW=$(get_value CPUFrequency:)
    R_MEM_MB=$(get_value Memory:)
    P_NUM_TESTS=$(get_value NumTestProcesses:)

    # Process system information
    PT_VERSION="${V_MAJOR}.${V_MINOR}.${V_BUILD}"
    PT_FREQ="${P_FREQ_RAW} MHz"
    PT_MEM_GIB=$(awk -v mem="$R_MEM_MB" 'BEGIN {if (mem > 0) printf "%.1f", mem/1024; else print "0"}')
    PT_MEM_DISPLAY="${PT_MEM_GIB} GiB RAM"
    PT_PROCESSES="Number of Processes: ${P_NUM_TESTS}"
    PT_ITERATIONS="Test Iterations: 1"
    PT_DURATION="Test Duration: Medium"

    # Extract performance scores and subtest results
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
    CPU_SSE=$(get_score CPU_MATRIX_MULT_SSE:)

    ME_ALLOC=$(get_score ME_ALLOC_S:)
    ME_READ_C=$(get_score ME_READ_S:)
    ME_READ_U=$(get_score ME_READ_L:)
    ME_WRITE=$(get_score ME_WRITE:)
    ME_AVAIL=$(get_score ME_LARGE:)
    ME_LATENCY=$(get_score ME_LATENCY:)
    ME_THREADED_VAL=$(get_score ME_THREADED:)

    # Format output (align using printf)
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
    echo "Fatal error: Passmark test program failed to run or did not generate result file (results*.yml)." >&2
    echo "Please check the raw output ($RAW_RESULT_FILE) for error information." >&2
    [ -f "$RAW_RESULT_FILE" ] && sed -n '1,200p' "$RAW_RESULT_FILE" || true
    exit 1
fi

# Cleanup
echo ""
echo "-------------------------------------------"
echo "--- Cleaning up temporary files ---"
cd ../..
rm -rf "$TEMP_DIR"
echo "Temporary directory $TEMP_DIR has been cleaned up."
echo "-------------------------------------------"
#!/bin/bash
# --- Passmark PerformanceTest diagnostic script (v3 - automated non-interactive) ---
set -e

# 0. Define necessary variables
TEMP_DIR="passmark_auto_test_$$"
PT_LINUX_ARCH=""
EXECUTABLE_NAME="" # Name of the final executable file
LD_PATH_PREFIX=""
LIB_PATH_DIR=""    # Subpath where libncurses.so.5 is located

# --- 1. Auto-detect package manager and install base dependencies ---
echo "--- 正在安装基础依赖 (wget, unzip, dpkg) ---"
if command -v apt >/dev/null; then
    PKG_MGR="apt"
    apt-get update -y >/dev/null
    apt-get install -y wget unzip dpkg >/dev/null 2>&1
    echo "--- Installing base dependencies (wget, unzip, dpkg) ---"
    PKG_MGR="yum"
    yum install -y wget unzip dpkg >/dev/null 2>&1
elif command -v dnf >/dev/null; then
    PKG_MGR="dnf"
    dnf install -y wget unzip dpkg >/dev/null 2>&1
else
    echo "致命错误：无法找到支持的包管理器 (apt/yum/dnf)。"
    exit 1
fi

# 2. Create temporary directory and enter it
        echo "Fatal error: no supported package manager found (apt/yum/dnf)."
echo "--- 已创建临时工作目录: $(pwd) ---"

# 3. Detect system architecture and handle ncurses compatibility dependencies
#!/bin/bash
# PassMark PerformanceTest diagnostic script (v3 - automated non-interactive)
set -euo pipefail

# 0. Define necessary variables
TEMP_DIR="passmark_auto_test_$$"
PT_LINUX_ARCH=""
EXECUTABLE_PATH=""
EXECUTABLE_NAME="" # Name of the final executable file
LD_PATH_PREFIX=""
LIB_TEMP_DIR=""    # temporary dir used when extracting .deb
RAW_RESULT_FILE="passmark_raw_output.log"

# 1. Auto-detect package manager and ensure base utilities are available
echo "--- Installing base dependencies (wget, unzip, dpkg) ---"
PKG_MGR=""
if command -v apt >/dev/null 2>&1; then
    PKG_MGR="apt"
    apt-get update -y >/dev/null
    apt-get install -y wget unzip dpkg >/dev/null 2>&1
elif command -v yum >/dev/null 2>&1; then
    PKG_MGR="yum"
    yum install -y wget unzip dpkg >/dev/null 2>&1
elif command -v dnf >/dev/null 2>&1; then
    PKG_MGR="dnf"
    dnf install -y wget unzip dpkg >/dev/null 2>&1
else
    echo "Fatal error: no supported package manager found (apt/yum/dnf)." >&2
    exit 1
fi

# 2. Create temporary directory and enter it
mkdir -p "$TEMP_DIR" && cd "$TEMP_DIR"
echo "--- Temporary working directory created: $(pwd) ---"

# 3. Detect system architecture and handle ncurses compatibility dependencies
ARCH_TYPE=$(uname -m)
if [ "$ARCH_TYPE" = "x86_64" ]; then
    PT_LINUX_ARCH="x64"
    echo "--- Detected architecture: x86_64 ---"
    # Try installing libncurses5 or compatibility libraries; fall back to manual extraction
    if [ "$PKG_MGR" = "apt" ] && apt-get install -y libncurses5 >/dev/null 2>&1; then
        echo "libncurses5 installed via apt."
    elif [ "$PKG_MGR" = "yum" ] || [ "$PKG_MGR" = "dnf" ]; then
        (yum install -y ncurses-compat-libs >/dev/null 2>&1 || dnf install -y ncurses-compat-libs >/dev/null 2>&1)
        echo "ncurses-compat-libs installed via $PKG_MGR."
    else
        echo "Attempting manual extraction of ncurses libraries..."
        # Download .deb packages and extract the needed libraries
        wget -q http://archive.ubuntu.com/ubuntu/pool/universe/n/ncurses/libncursesw5_6.3-2ubuntu0.1_amd64.deb
        wget -q http://archive.ubuntu.com/ubuntu/pool/universe/n/ncurses/libtinfo5_6.3-2_amd64.deb
        dpkg-deb -xv libncursesw5_6.3-2ubuntu0.1_amd64.deb n_temp >/dev/null 2>&1 || true
        dpkg-deb -xv libtinfo5_6.3-2_amd64.deb t_temp >/dev/null 2>&1 || true

        NCURSES_LIB_ORIG=$(find n_temp -type f -name "libncursesw.so*" | head -n1 || true)
        TINFO_LIB_ORIG=$(find t_temp -type f -name "libtinfo.so*" | head -n1 || true)

        if [ -z "$NCURSES_LIB_ORIG" ] || [ -z "$TINFO_LIB_ORIG" ]; then
            echo "Fatal error: manual extraction of ncurses library files failed!" >&2
            exit 1
        fi

        mv "$NCURSES_LIB_ORIG" libncurses.so.5
        mv "$TINFO_LIB_ORIG" libtinfo.so.5
        echo "ncurses libraries libncurses.so.5 and libtinfo.so.5 extracted."
    fi
elif [ "$ARCH_TYPE" = "aarch64" ]; then
    PT_LINUX_ARCH="arm64"
    echo "--- Detected architecture: aarch64 ---"
    # For aarch64, prefer package manager; manual extraction not implemented here
    if [ "$PKG_MGR" = "apt" ]; then
        apt-get install -y libncurses5 >/dev/null 2>&1 || true
    else
        (yum install -y ncurses-compat-libs >/dev/null 2>&1 || dnf install -y ncurses-compat-libs >/dev/null 2>&1) || true
    fi
else
    echo "Fatal error: unsupported system architecture: $ARCH_TYPE" >&2
    exit 1
fi

# 4. Download, unzip and prepare the Passmark main program
ZIP_FILE="pt_linux_${PT_LINUX_ARCH}.zip"
echo "--- Downloading Passmark test tool ($PT_LINUX_ARCH) ---"
wget -O "$ZIP_FILE" "https://www.passmark.com/downloads/pt_linux_${PT_LINUX_ARCH}.zip"
if [ ! -s "$ZIP_FILE" ]; then
    echo "Fatal error: file download failed or file is empty!" >&2
    exit 1
fi

unzip -q "$ZIP_FILE"
EXECUTABLE_PATH=$(find PerformanceTest -type f \( -name "pt_linux*" -o -name "PerformanceTest*" \) | head -n 1 || true)
EXECUTABLE_NAME=$(basename "$EXECUTABLE_PATH" 2>/dev/null || true)

if [ -z "$EXECUTABLE_NAME" ] || [ ! -f "$EXECUTABLE_PATH" ]; then
    echo "Fatal error: failed to automatically find Passmark executable!" >&2
    exit 1
fi
chmod +x "$EXECUTABLE_PATH"
echo "Found executable: $EXECUTABLE_NAME"

# 5. Consolidate library files and set up the execution environment
cd PerformanceTest || exit 1

if [ -f ../libncurses.so.5 ]; then
    echo "Moving ncurses compatibility libraries to the executable's directory..."
    mv ../libncurses.so.5 . || true
    mv ../libtinfo.so.5 . || true
    LD_PATH_PREFIX="TERM=xterm LD_LIBRARY_PATH=."
    echo "LD_LIBRARY_PATH set to current directory."
else
    # If system libraries are already installed, only set TERM
    LD_PATH_PREFIX="TERM=xterm"
fi

echo "Working directory: $(pwd)"

# 6. Launch non-interactive test (run in background and capture raw output)
echo "-------------------------------------------"
echo "--- Starting Passmark non-interactive test (-r 3) ---"
echo "--- Please wait; the program will exit automatically when all tests complete. ---"
echo "-------------------------------------------"
sleep 1

# Run executable in background and capture output
eval $LD_PATH_PREFIX "./$EXECUTABLE_NAME" -r 3 >"$RAW_RESULT_FILE" 2>&1 &
EXEC_PID=$!
echo "Passmark started with PID $EXEC_PID (logging to $RAW_RESULT_FILE)."

# Wait for the process to finish or for results file to appear
while kill -0 "$EXEC_PID" >/dev/null 2>&1; do
    if [ -f "results_all.yml" ]; then
        echo "Warning: results_all.yml already exists; will forcibly terminate the process."
        pkill -9 -f -x "$EXECUTABLE_NAME" >/dev/null 2>&1 || true
        cat results_all.yml
        echo "Process $EXECUTABLE_NAME has been terminated."
        break
    fi
    sleep 5
done

echo "All Passmark tests have completed or been terminated."

# Locate results YAML file
YML_FILES=(results*.yml)
RESULTS_YML_FILE="${YML_FILES[0]}"

if [ -f "$RESULTS_YML_FILE" ]; then
    echo "--- All PassMark tests completed. ---"
    echo ""
    echo "--- Diagnostic results (formatted) ---"

    # Define a function to extract values from the results
    # $1: Key to search for (e.g., "Major:", "Processor:")
    get_value() {
        if [[ "$1" =~ "Processor:" || "$1" =~ "NumCores:" || "$1" =~ "Memory:" || "$1" =~ "CPUFrequency:" ]]; then
            grep -A 10 "SystemInformation:" "$RESULTS_YML_FILE" | grep -m 1 "^[[:space:]]*$1"
        else
            grep -m 1 "^[[:space:]]*$1" "$RESULTS_YML_FILE"
        fi | awk '{
            # Concatenate multi-word key values, e.g., Processor: AMD EPYC 7B13
            if (NF > 2) {
                result=$2
                for (i=3; i<=NF; i++) result=result " " $i
                print result
            } else {
                print $NF
            }
        }' | tr -d '\r,'
    }

    # Define a function to extract scores (handle decimals and rounding)
    # $1: Key to search for (e.g., SUMM_CPU:)
    get_score() {
        local KEY_VALUE
        KEY_VALUE=$(get_value "$1")
        echo "$KEY_VALUE" | awk '
        {
            # Use int($1+0.5) to perform rounding
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

    # Extract system information
    V_MAJOR=$(get_value Major:)
    V_MINOR=$(get_value Minor:)
    V_BUILD=$(get_value Build:)
    P_NAME=$(get_value Processor:)
    V_ARCH=$(get_value ptArchitecture: | sed 's/_linux$//')
    P_CORES=$(get_value NumCores:)
    P_FREQ_RAW=$(get_value CPUFrequency:)
    R_MEM_MB=$(get_value Memory:)
    P_NUM_TESTS=$(get_value NumTestProcesses:)

    # Process system information
    PT_VERSION="${V_MAJOR}.${V_MINOR}.${V_BUILD}"
    PT_FREQ="${P_FREQ_RAW} MHz"
    PT_MEM_GIB=$(awk -v mem="$R_MEM_MB" 'BEGIN {if (mem > 0) printf "%.1f", mem/1024; else print "0"}')
    PT_MEM_DISPLAY="${PT_MEM_GIB} GiB RAM"
    PT_PROCESSES="Number of Processes: ${P_NUM_TESTS}"
    PT_ITERATIONS="Test Iterations: 1"
    PT_DURATION="Test Duration: Medium"

    # Extract performance scores and subtest results
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
    CPU_SSE=$(get_score CPU_MATRIX_MULT_SSE:)

    ME_ALLOC=$(get_score ME_ALLOC_S:)
    ME_READ_C=$(get_score ME_READ_S:)
    ME_READ_U=$(get_score ME_READ_L:)
    ME_WRITE=$(get_score ME_WRITE:)
    ME_AVAIL=$(get_score ME_LARGE:)
    ME_LATENCY=$(get_score ME_LATENCY:)
    ME_THREADED_VAL=$(get_score ME_THREADED:)

    # Format output (align using printf)
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
    echo "Fatal error: Passmark test program failed to run or did not generate result file (results*.yml)." >&2
    echo "Please check the raw output ($RAW_RESULT_FILE) for error information." >&2
    [ -f "$RAW_RESULT_FILE" ] && sed -n '1,200p' "$RAW_RESULT_FILE" || true
    exit 1
fi

# Cleanup
echo ""
echo "-------------------------------------------"
echo "--- Cleaning up temporary files ---"
cd ../..
rm -rf "$TEMP_DIR"
echo "Temporary directory $TEMP_DIR has been cleaned up."
echo "-------------------------------------------"