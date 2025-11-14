@echo off
title 系统修复工具

echo 正在尝试修复系统文件，请耐心等待...
echo.

echo --- 步骤 1: 运行系统文件检查器 (SFC) ---
sfc /scannow
echo.
echo SFC 扫描完成。
echo.

echo --- 步骤 2: 运行部署映像服务和管理工具 (DISM) ---
echo 检查系统健康状态...
DISM /Online /Cleanup-Image /CheckHealth
echo.
echo 扫描系统健康状态...
DISM /Online /Cleanup-Image /ScanHealth
echo.
echo 尝试修复系统映像...
DISM /Online /Cleanup-Image /RestoreHealth
echo.
echo DISM 操作完成。
echo.

echo --- 步骤 3: 再次运行系统文件检查器 (SFC) ---
sfc /scannow
echo.
echo SFC 扫描完成。

echo --- 修复尝试完成 ---
echo 请重新启动你的电脑以应用更改。
echo.
pause