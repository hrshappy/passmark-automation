@echo off
rem v13.0 - 终极启动器 (手动分离)

rem ★★★ 核心修复：只调用，不创建 ★★★

echo.
echo --- 即将执行文件编码转换 ---
echo.
pause

rem 用最安全的方式调用我们手动创建的.ps1文件
%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0core_script.ps1" -selfScriptPath "%~nx0"

echo.
echo --- 执行完毕 ---
echo.
pause