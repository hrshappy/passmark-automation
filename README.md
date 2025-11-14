# PassMark PerformanceTest Automation (Linux)

Fully automated, non-interactive downloader/installer/runner for PassMark PerformanceTest on Linux.

## Quick Start

**Recommended — clone and run:**
```bash
git clone --depth 1 https://github.com/hrshappy/passmark-automation.git
cd passmark-automation
sudo bash passmark_auto.sh
```

**Alternative — direct download:**
```bash
curl -fsSL https://raw.githubusercontent.com/hrshappy/passmark-automation/main/passmark_auto.sh -o /tmp/passmark_auto.sh
chmod +x /tmp/passmark_auto.sh
sudo /tmp/passmark_auto.sh
```

## What It Does

1. **Auto-detects** system architecture (x86_64 or aarch64) and package manager (apt/yum/dnf)
2. **Installs dependencies** — wget, unzip, dpkg, and ncurses compatibility libraries
3. **Downloads** the correct PassMark PerformanceTest package for your architecture
4. **Runs** the benchmark in non-interactive mode (`-r 3` iterations)
5. **Formats and displays** test results from the YAML output:
   - CPU performance (mark, integer math, floating-point, prime numbers, sorting, encryption, compression, single-threaded, physics, SSE)
   - Memory performance (mark, database operations, read cached/uncached, write, available RAM, latency, threaded)

## Requirements

- **Linux** (Ubuntu, CentOS, RHEL, Fedora, or other distros with apt/yum/dnf)
- **Internet access** to download PassMark package
- **Root/sudo privileges** to install packages (apt/yum/dnf)

## Key Features

- **Fully automated** — no manual steps after launching
- **Non-interactive** — safe to run in scripts or automation
- **Dependency resolution** — handles ncurses compatibility issues
- **Clean output** — human-readable formatted test report
- **Self-contained** — creates temporary working directory, cleans up after completion

## Script Functions

### `get_value(key)`
Extracts a single YAML field value from PassMark results file. Handles multi-word values and searches within `SystemInformation:` block for processor/memory keys.

**Example:**
```bash
P_NAME=$(get_value "Processor:")
```

### `get_score(key)`
Retrieves and formats a numeric benchmark score. Rounds to integer by default; displays one decimal for certain metrics like CPU_PRIME.

**Example:**
```bash
CPU_MARK=$(get_score "SUMM_CPU:")
```
                 PassMark PerformanceTest Linux (11.0.1004)

AMD EPYC 7B13 (x86_64)
1 cores @ 0 MHz  |  0 GiB RAM
Number of Processes: 1  |  Test Iterations: 1  |  Test Duration: Medium
--------------------------------------------------------------------------------
CPU Mark:                          2262                          
  Integer Math                     5210 Million Operations/s     
  Floating Point Math              4203 Million Operations/s     
  Prime Numbers                    16.1 Million Primes/s         
  Sorting                          3123 Thousand Strings/s       
  Encryption                       1129 MB/s                     
  Compression                      21164 KB/s                    
  CPU Single Threaded              2217 Million Operations/s     
  Physics                          291 Frames/s                  
  Extended Instructions (SSE)      1811 Million Matrices/s       

Memory Mark:                       1608                          
  Database Operations              903 Thousand Operations/s     
  Memory Read Cached               24277 MB/s                    
  Memory Read Uncached             16832 MB/s                    
  Memory Write                     17339 MB/s                    
  Available RAM                    2153 Megabytes                
  Memory Latency                   63 Nanoseconds                
  Memory Threaded                  16687 MB/s                    
--------------------------------------------------------------------------------

-------------------------------------------

## Notes

- The script creates a temporary directory (`passmark_auto_test_$$`) and cleans it up after completion
- Default test run is 3 iterations (`-r 3`); modify the `eval` line in the script to change
- Tested on x86_64 and aarch64 architectures
- If libncurses5 is unavailable via package manager, the script extracts it from .deb packages

## Troubleshooting

**404 error on download:**
- Use the git clone method instead (avoids URL encoding issues)

**Permission denied:**
- Ensure the script is executable: `chmod +x passmark_auto.sh`
- Run with `sudo`: `sudo bash passmark_auto.sh`

**Dependency installation fails:**
- The script attempts multiple fallback methods for ncurses libraries
- If all fail, manually install `libncurses5` or `ncurses-compat-libs` before running

## License & Attribution

PassMark PerformanceTest is owned by PassMark Software. This script is an automation wrapper for the Linux build.
