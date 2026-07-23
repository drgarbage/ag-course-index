Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "=========================================================" -ForegroundColor Cyan
Write-Host "         Windows Sandbox 整合測試引導程式" -ForegroundColor Cyan
Write-Host "=========================================================" -ForegroundColor Cyan

# Paths
$sharedDir = "C:\shared"
$configPath = Join-Path $sharedDir "config.json"
$logPath = Join-Path $sharedDir "log.txt"
$resultPath = Join-Path $sharedDir "result.json"

if (-not (Test-Path $configPath)) {
    Write-Warning "找不到情境設定檔 config.json，預設以 Clean 執行。"
    $scenario = "Clean"
} else {
    $config = Get-Content -Raw -Path $configPath | ConvertFrom-Json
    $scenario = $config.scenario
}

Write-Host "偵測到測試情境：$scenario" -ForegroundColor Green

# 1. Setup scenario
$setupScript = "C:\ag-course-index\tests\sandbox\scenarios\setup-scenario.ps1"
if (Test-Path $setupScript) {
    & $setupScript -Scenario $scenario
} else {
    Write-Warning "找不到情境設定腳本：$setupScript"
}

# Refresh PATH before installer execution
$machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$env:Path = "$machinePath;$userPath"

# 2. Run installer in non-interactive mode and capture log
Write-Host "正在執行一鍵安裝器..." -ForegroundColor Cyan
$installerPath = "C:\ag-course-index\scripts\install-course-toolchain-windows.ps1"
if (Test-Path $installerPath) {
    # Run the installer and redirect output to log file, also showing it on screen
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installerPath -NonInteractive *>&1 | Tee-Object -FilePath $logPath
} else {
    throw "找不到一鍵安裝器主程式：$installerPath"
}

# 3. Generate structured result report
Write-Host "正在產生結構化測試報告..." -ForegroundColor Cyan
$PSScriptRootVal = "C:\ag-course-index\scripts"
if (Test-Path $PSScriptRootVal) {
    . (Join-Path $PSScriptRootVal "course-toolchain-windows.ps1")
    . (Join-Path $PSScriptRootVal "toolchain/windows.ps1")
    . (Join-Path $PSScriptRootVal "toolchain/report.ps1")
    
    # Re-evaluate statuses in guest
    $results = @()
    
    try {
        $gitGh = Get-WindowsToolState -ToolId 'git_gh'
        $results += $gitGh
    } catch {
        $results += [pscustomobject]@{ tool_id = 'git_gh'; status = 'failed'; safe_message = $_.Exception.Message }
    }
    
    try {
        $node = Get-WindowsToolState -ToolId 'node_lts'
        $results += $node
    } catch {
        $results += [pscustomobject]@{ tool_id = 'node_lts'; status = 'failed'; safe_message = $_.Exception.Message }
    }
    
    try {
        $cf = Get-WindowsToolState -ToolId 'cloudflared'
        $results += $cf
    } catch {
        $results += [pscustomobject]@{ tool_id = 'cloudflared'; status = 'failed'; safe_message = $_.Exception.Message }
    }
    
    try {
        $dockerReady = (Test-WindowsDockerReady).status -eq 'ready'
        if ($dockerReady) {
            $results += [pscustomobject]@{ tool_id = 'docker_desktop'; status = 'ready' }
        } else {
            if (Get-Command 'docker' -ErrorAction SilentlyContinue) {
                $results += [pscustomobject]@{
                    tool_id = 'docker_desktop'
                    status = 'failed'
                    safe_message = '偵測到 Docker Desktop 已經安裝，但 Docker 守護行程（daemon）尚未啟動，請手動開啟 Docker Desktop 應用程式。'
                }
            } else {
                $results += [pscustomobject]@{ tool_id = 'docker_desktop'; status = 'failed'; safe_message = '未偵測到 Docker Desktop，請執行安裝。' }
            }
        }
    } catch {
        $results += [pscustomobject]@{ tool_id = 'docker_desktop'; status = 'failed'; safe_message = $_.Exception.Message }
    }
    
    # GUI Tools
    foreach ($guiId in @('antigravity', 'vscode', 'browser')) {
        try {
            $installed = Test-WindowsGuiToolInstalled -ToolId $guiId
            $results += [pscustomobject]@{
                tool_id = $guiId
                status = if ($installed) { 'ready' } else { 'missing' }
            }
        } catch {
            $results += [pscustomobject]@{ tool_id = $guiId; status = 'failed'; safe_message = $_.Exception.Message }
        }
    }
    
    $freeBytes = Get-DiskFreeBytes
    $report = New-ToolchainReport -Profile 'full' -Results $results -FreeBytes $freeBytes
    
    $report | ConvertTo-Json -Depth 5 | Set-Content -Path $resultPath -Encoding utf8 -Force
    Write-Host "結構化測試報告成功寫入：$resultPath" -ForegroundColor Green
}

Write-Host "=========================================================" -ForegroundColor Green
Write-Host "測試執行完畢！結果已同步至主機端共享資料夾。" -ForegroundColor Green
Write-Host "您可以關閉此沙盒視窗。" -ForegroundColor Green
Write-Host "=========================================================" -ForegroundColor Green
