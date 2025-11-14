# v14 - PowerShell 核心脚本 (语法修正)

# ★★★ 核心修正：param 必须是脚本的第一个可执行语句 ★★★
param(
    [string]$selfScriptPath
)

try {
    $sourceEncodingName = 'GB2312'
    $fileTypes = @('*.txt', '*.bat')
    
    # 获取当前脚本所在的路径
    $searchPath = Split-Path -Parent $MyInvocation.MyCommand.Path
    
    Write-Host "将在以下路径中搜索文件: $searchPath" -ForegroundColor Cyan
    
    # 修正 selfScriptPath，确保它是一个完整的路径
    $selfBatPath = Join-Path -Path $searchPath -ChildPath $selfScriptPath

    Write-Host "将自动跳过批处理启动器: $selfBatPath" -ForegroundColor Cyan
    Write-Host ''
    
    $items = Get-ChildItem -Path $searchPath -Include $fileTypes -Recurse | Where-Object { $_.FullName -ne $selfBatPath }

    if ($items.Count -eq 0) {
        Write-Host '没有在当前目录及子目录中找到需要转换的文件。' -ForegroundColor Yellow
        # 等待用户按键，以便能看到信息
        Write-Host "按 Enter 键退出..." -ForegroundColor Yellow
        Read-Host
        exit 0
    }

    Write-Host "找到 $($items.Count) 个文件，开始转换..."
    Write-Host '----------------------------------------------------'
    $errorCount = 0

    foreach ($item in $items) {
        try {
            $sourceEncoding = [System.Text.Encoding]::GetEncoding($sourceEncodingName)
            $content = [System.IO.File]::ReadAllText($item.FullName, $sourceEncoding)
            $utf8Encoding = New-Object System.Text.UTF8Encoding($true) # true = 带BOM
            [System.IO.File]::WriteAllText($item.FullName, $content, $utf8Encoding)
            Write-Host ('成功: ' + $item.FullName) -ForegroundColor Green
        } catch {
            $errorCount++
            Write-Host ('失败: ' + $item.FullName) -ForegroundColor Red
            Write-Host ('  └─ 错误原因: ' + $_.Exception.Message.Trim()) -ForegroundColor Yellow
        }
    }

    Write-Host '----------------------------------------------------'
    if ($errorCount -gt 0) { 
        Write-Host "操作完成，但有 $errorCount 个文件转换失败。" -ForegroundColor Red
        exit 1 
    } else { 
        Write-Host "所有文件均已成功转换！" -ForegroundColor Cyan
        exit 0 
    }
} catch {
    Write-Host '脚本执行时发生严重错误！' -ForegroundColor Red
    Write-Host ('错误详情: ' + $_.Exception.Message.Trim()) -ForegroundColor Red
    exit 2
}    $searchPath = Split-Path -Parent $MyInvocation.MyCommand.Path
    Write-Host "将在以下路径中搜索文件: ^$searchPath" -ForegroundColor Cyan
    $selfBatPath = Join-Path -Path $searchPath -ChildPath $selfScriptPath
    Write-Host "将自动跳过批处理启动器: ^$selfBatPath" -ForegroundColor Cyan
    Write-Host '' 
    $items = Get-ChildItem -Path $searchPath -Include $fileTypes -Recurse | Where-Object { $_.FullName -ne $selfBatPath }
    if ($items.Count -eq 0) {
        Write-Host '没有在当前目录及子目录中找到需要转换的文件。' -ForegroundColor Yellow
        Write-Host "按 Enter 键退出..." -ForegroundColor Yellow
        Read-Host | Out-Null
        exit 0
    }
    Write-Host "找到 ^$^(^$items.Count^) 个文件，开始转换..."
    Write-Host '----------------------------------------------------'
    $errorCount = 0
    foreach ($item in $items) {
        try {
            $sourceEncoding = [System.Text.Encoding]::GetEncoding($sourceEncodingName)
            $content = [System.IO.File]::ReadAllText($item.FullName, $sourceEncoding)
            $utf8Encoding = New-Object System.Text.UTF8Encoding($true)
            [System.IO.File]::WriteAllText($item.FullName, $content, $utf8Encoding)
            Write-Host ('成功: ' + $item.FullName) -ForegroundColor Green
        } catch {
            $errorCount++
            Write-Host ('失败: ' + $item.FullName) -ForegroundColor Red
            Write-Host ('  └─ 错误原因: ' + $_.Exception.Message.Trim()) -ForegroundColor Yellow
        }
    }
    Write-Host '----------------------------------------------------'
    if ($errorCount -gt 0) { exit 1 } else { exit 0 }
} catch {
    Write-Host '脚本执行时发生严重错误！' -ForegroundColor Red
    Write-Host ('错误详情: ' + $_.Exception.Message.Trim()) -ForegroundColor Red
    exit 2
}
