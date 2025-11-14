# PassMark PerformanceTest Automation (Linux)

This repository contains a single automation script that downloads,
prepares, and runs PassMark PerformanceTest on Linux in non-interactive
mode and formats the results for display.

Files
- `passmark_auto.sh`
  - The main automation script (single-file, POSIX shell).
- `README.md`
  - This documentation and quick start guide.

Quick Start

Recommended — clone the repository and run the script (avoids filename encoding issues):

```bash
# clone the repo (shallow clone)
git clone --depth 1 https://github.com/hrshappy/passmark-automation.git
cd passmark-automation
# run the simplified script with elevated privileges so package installs can succeed
sudo bash passmark_auto.sh
```

Alternative — download the script directly and run (use only if you trust the source):

```bash
# curl (preferred) — save to /tmp, mark executable and run
curl -fsSL https://raw.githubusercontent.com/hrshappy/passmark-automation/main/passmark_auto.sh -o /tmp/passmark_auto.sh
chmod +x /tmp/passmark_auto.sh
sudo /tmp/passmark_auto.sh

# wget variant:
# wget -qO /tmp/passmark_auto.sh https://raw.githubusercontent.com/hrshappy/passmark-automation/main/passmark_auto.sh
# chmod +x /tmp/passmark_auto.sh && sudo /tmp/passmark_auto.sh
```

Prerequisites
- Internet access to download the PassMark package.
- A package manager available on the host (`apt`, `yum`, or `dnf`).
- The script will attempt to install `wget`, `unzip`, `dpkg` and
  ncurses compatibility packages when necessary.

What the script does (summary)
- Detects host architecture (`x86_64` or `aarch64`) and package manager.
- Attempts to install `libncurses5` or `ncurses-compat-libs` for
  PassMark compatibility; if unavailable, extracts compatible libraries
  from `.deb` packages and places them next to the executable.
- Downloads the PassMark Linux zip for the detected architecture.
- Runs the PerformanceTest in non-interactive mode, waits for results,
  and formats a concise human-readable report from `results*.yml`.

Key functions (in-script)
- `get_value(key)` — Extracts a single field value from the PassMark
  results YAML. Handles multi-word values and searches within the
  `SystemInformation:` block for processor/memory related keys.
- `get_score(key)` — Calls `get_value` and formats numeric test scores
  for display (rounds to integer by default; preserves one decimal for
  specified tests).

Notes and safety
- The repository currently intentionally contains only the automation
  script. Previous files were removed from the tracked branch.
- Local copies of removed files still exist in your working directory
  unless you delete them manually; the script will not remove files
  outside its temporary working directory.
- If you need to permanently erase files from Git history (force remove
  from all commits), use `git filter-repo` or `git filter-branch` with
  care. Contact me if you want help with that process.

Support / Changes
- If you want the script to support additional architectures or more
  conservative dependency handling (no package installs), I can add
  options and flags (e.g. `--no-install`, `--keep-temp`).

--
Short Chinese summary

此脚本在 Linux 上自动下载并运行 PassMark PerformanceTest，
并从生成的 `results*.yml` 中提取、格式化测试结果。需要网络、
并可能需要以 root 权限安装兼容库以运行 PassMark。
