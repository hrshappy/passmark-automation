#!/bin/bash
# --- Passmark PerformanceTest 终极诊断脚本 (v3 - 自动化非交互式) ---
set -e

# 0. 定义必要的变量
TEMP_DIR="passmark_auto_test_$$"
PT_LINUX_ARCH=""
EXECUTABLE_NAME="" # 最终可执行文件的名称
LD_PATH_PREFIX=""
LIB_PATH_DIR=""    # libncurses.so.5 所在的子路径

# --- 1. 自动识别包管理器并安装基础依赖 ---
echo "--- 正在安装基础依赖 (wget, unzip, dpkg) ---"
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
    echo "致命错误：无法找到支持的包管理器 (apt/yum/dnf)。"
    exit 1
fi

# 2. 创建临时目录并进入
mkdir "$TEMP_DIR" && cd "$TEMP_DIR"
echo "--- 已创建临时工作目录: $(pwd) ---"

# 3. 识别系统架构并处理 ncurses 兼容性依赖
ARCH_TYPE=$(uname -m)
if [ "$ARCH_TYPE" = "x86_64" ]; then 
    PT_LINUX_ARCH="x64"
    LIB_PATH_DIR="x86_64-linux-gnu"
    echo "--- 检测到架构: x86_64, 正在尝试解决 libncurses.so.5 依赖 ---"
    
    # 尝试用包管理器安装 libncurses5 (如果失败，手动提取)
    if [ "$PKG_MGR" = "apt" ] && apt-get install -y libncurses5 >/dev/null 2>&1; then
        echo "libncurses5 依赖已通过 apt 安装。"
    elif [ "$PKG_MGR" = "yum" ] || [ "$PKG_MGR" = "dnf" ]; then
        (yum install -y ncurses-compat-libs >/dev/null 2>&1 || dnf install -y ncurses-compat-libs >/dev/null 2>&1)
        echo "ncurses-compat-libs 依赖已通过 $PKG_MGR 安装。"
    else
        echo "尝试手动提取 ncurses 库..."
        # 手动提取 .deb 包中的库文件
        wget -q http://archive.ubuntu.com/ubuntu/pool/universe/n/ncurses/libncursesw5_6.3-2ubuntu0.1_amd64.deb
        wget -q http://archive.ubuntu.com/ubuntu/pool/universe/n/ncurses/libtinfo5_6.3-2_amd64.deb
        dpkg-deb -xv libncursesw5_6.3-2ubuntu0.1_amd64.deb n_temp
        dpkg-deb -xv libtinfo5_6.3-2_amd64.deb t_temp
        
        # 查找并重命名所需的库文件到当前目录 (这是最关键的兼容性处理)
        NCURSES_LIB_ORIG=$(find n_temp -name "libncursesw.so.5.9")
        TINFO_LIB_ORIG=$(find t_temp -name "libtinfo.so.5.9")

        if [ -z "$NCURSES_LIB_ORIG" ] || [ -z "$TINFO_LIB_ORIG" ]; then 
            echo "致命错误：手动提取 ncurses 库文件失败！"; exit 1; 
        fi
        
        mv "$NCURSES_LIB_ORIG" libncurses.so.5
        mv "$TINFO_LIB_ORIG" libtinfo.so.5
        echo "ncurses 库文件 libncurses.so.5 和 libtinfo.so.5 已提取成功。"
    fi
elif [ "$ARCH_TYPE" = "aarch64" ]; then 
    PT_LINUX_ARCH="arm64"
    LIB_PATH_DIR="aarch64-linux-gnu"
    echo "--- 检测到架构: aarch64 (请根据需要调整手动提取逻辑) ---"
    # 此处省略 aarch64 的手动提取逻辑，假设通过包管理器能解决
else 
    echo "致命错误：不支持的系统架构: $ARCH_TYPE"; exit 1; 
fi

# 4. 下载、解压并准备 Passmark 主程序
ZIP_FILE="pt_linux_$PT_LINUX_ARCH.zip"
echo "--- 正在下载 Passmark 测试工具 ($PT_LINUX_ARCH) ---"
wget -O "$ZIP_FILE" "https://www.passmark.com/downloads/pt_linux_$PT_LINUX_ARCH.zip"
if [ ! -s "$ZIP_FILE" ]; then echo "致命错误：文件下载失败或文件为空！"; exit 1; fi

unzip -q "$ZIP_FILE"
EXECUTABLE_PATH=$(find PerformanceTest -type f -name "pt_linux*" -o -type f -name "PerformanceTest*" | head -n 1)
EXECUTABLE_NAME=$(basename "$EXECUTABLE_PATH")

if [ -z "$EXECUTABLE_NAME" ]; then echo "致命错误：未能自动找到 Passmark 可执行文件！"; exit 1; fi
chmod +x "$EXECUTABLE_PATH"
echo "已找到可执行文件: $EXECUTABLE_NAME"

# 5. 统一库文件位置并设置执行环境
cd PerformanceTest # 进入 PerformanceTest 目录

if [ -f ../libncurses.so.5 ]; then
    echo "将 ncurses 兼容性库移动到可执行文件同级目录..."
    mv ../libncurses.so.5 .
    mv ../libtinfo.so.5 .
    # 设置 LD_LIBRARY_PATH 为当前目录 (.), 并设置 TERM 变量
    LD_PATH_PREFIX="TERM=xterm LD_LIBRARY_PATH=."
    echo "已设置 LD_LIBRARY_PATH=."
else
    # 如果通过包管理器安装，则只需要设置 TERM 变量
    LD_PATH_PREFIX="TERM=xterm"
fi

echo "工作目录切换至: $(pwd)"

# 6. 启动非交互式测试 (安全后台模式)
echo ""
echo "-------------------------------------------"
echo "--- 正在启动 Passmark 非交互式测试 (-r 3) ---"
echo "--- 请耐心等待，程序将在所有测试完成后自动退出。---"
echo "-------------------------------------------"
sleep 2

# 定义一个变量来保存测试结果输出
RAW_RESULT_FILE="passmark_raw_output.log"

# 使用 eval 命令安全地执行带环境变量前缀的命令
eval $LD_PATH_PREFIX "./$EXECUTABLE_NAME" -r 3
echo "--- Passmark 程序 所有测试已完成，自动返回。---"

# 循环检查进程是否还在运行
while pgrep -f -x "$EXECUTABLE_NAME" > /dev/null; do
    if [ -f "results_all.yml" ]; then
        echo "--- 警告：results_all.yml已存在，将强制终止进程！---"
        # 强制杀死进程 (使用 pkill -f -x 应对长进程名)
        pkill -9 -f -x "$EXECUTABLE_NAME"
        cat results_all.yml
        echo "进程 $EXECUTABLE_NAME 已被强制终止。"
        break
    fi
    # 每 5 秒检查一次
    sleep 5
    SECONDS=$((SECONDS + 5))
done


echo "--- Passmark 程序所有测试已完成或已终止。---"


#RESULTS_YML_FILE=results_all.yml

YML_FILES=(results*.yml)
RESULTS_YML_FILE="${YML_FILES[0]}"

if [ -f "$RESULTS_YML_FILE" ]; then
    echo "--- Passmark 程序 所有测试已完成，自动返回。---"
    echo ""
    
    # 7. 格式化并输出结果 (新逻辑)
    # ----------------------------------------
    echo "--- 诊断结果 (格式化) ---"
    
    # 定义结果提取函数
    # $1: Key to search for (e.g., "Major:", "Processor:")
    get_value() {
        # 使用 grep -A 查找 SystemInformation: 块，否则查找整个文件
        if [[ "$1" =~ "Processor:" || "$1" =~ "NumCores:" || "$1" =~ "Memory:" || "$1" =~ "CPUFrequency:" ]]; then
            grep -A 10 "SystemInformation:" "$RESULTS_YML_FILE" | grep -m 1 "^[[:space:]]*$1"
        else
            grep -m 1 "^[[:space:]]*$1" "$RESULTS_YML_FILE"
        fi | awk '{
            # 拼接多词键值，如 Processor: AMD EPYC 7B13
            if (NF > 2) {
                result=$2
                for (i=3; i<=NF; i++) result=result " "$i
                print result
            } else {
                print $NF
            }
        }' | tr -d '\r,'
    }
    
    # 定义分数提取函数 (处理小数点和四舍五入)
    # $1: Key to search for (e.g., SUMM_CPU:)
    get_score() {
        local KEY_VALUE
        KEY_VALUE=$(get_value "$1")
        echo "$KEY_VALUE" | awk '
        {
            # 使用 int($1+0.5) 实现四舍五入
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

    # --- 提取系统信息 ---
    V_MAJOR=$(get_value Major:)
    V_MINOR=$(get_value Minor:)
    V_BUILD=$(get_value Build:)
    P_NAME=$(get_value Processor:)
    V_ARCH=$(get_value ptArchitecture: | sed 's/_linux$//')
    P_CORES=$(get_value NumCores:)
    P_FREQ_RAW=$(get_value CPUFrequency:)
    R_MEM_MB=$(get_value Memory:)
    P_NUM_TESTS=$(get_value NumTestProcesses:)

    # --- 处理系统信息 (修复 awk 语法错误的行) ---
    PT_VERSION="${V_MAJOR}.${V_MINOR}.${V_BUILD}"
    PT_FREQ="${P_FREQ_RAW} MHz"
    # 修复后的代码：使用 -v 传递变量，并使用单引号包围 awk 脚本
    PT_MEM_GIB=$(awk -v mem="$R_MEM_MB" 'BEGIN {if (mem > 0) printf "%.1f", mem/1024; else print "0"}')
    PT_MEM_DISPLAY="${PT_MEM_GIB} GiB RAM"
    PT_PROCESSES="Number of Processes: ${P_NUM_TESTS}"
    PT_ITERATIONS="Test Iterations: 1" 
    PT_DURATION="Test Duration: Medium" 

    # --- 提取性能分数及子测试结果 ---
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
    CPU_SSE=$(get_score CPU_MATRIX_MULT_SSE:) # 对应 Extended Instructions (SSE)

    ME_ALLOC=$(get_score ME_ALLOC_S:)
    ME_READ_C=$(get_score ME_READ_S:)
    ME_READ_U=$(get_score ME_READ_L:)
    ME_WRITE=$(get_score ME_WRITE:)
    ME_AVAIL=$(get_score ME_LARGE:)
    ME_LATENCY=$(get_score ME_LATENCY:)
    ME_THREADED_VAL=$(get_score ME_THREADED:)


    # 8. 格式化输出 (使用 printf 进行对齐)
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
    echo "致命错误：Passmark 测试程序运行失败或未生成结果文件 (results*.yml)。"
    echo "请查看原始输出 ($RAW_RESULT_FILE) 以获取错误信息。"
    cat "$RAW_RESULT_FILE"
    exit 1
fi




# 8. 清理
echo ""
echo "-------------------------------------------"
echo "--- 清理临时文件 ---"
cd ../..
rm -rf "$TEMP_DIR"
echo "临时目录 $TEMP_DIR 已清理完成。"
echo "-------------------------------------------"