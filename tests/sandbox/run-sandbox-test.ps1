param(
    [Parameter()][ValidateSet('Clean', 'NvmInstalled', 'DockerStopped')][string]$Scenario = 'Clean',
    [Parameter()][switch]$NoLaunch
)

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'

# Resolve directories
$repoRoot = (Get-Item "$PSScriptRoot\..\..").FullName
$sharedDir = Join-Path $PSScriptRoot "shared"
$wsbPath = Join-Path $PSScriptRoot "course-toolchain-test.wsb"

# Ensure shared directory exists
if (-not (Test-Path $sharedDir)) {
    New-Item -ItemType Directory -Path $sharedDir -Force | Out-Null
}

# Clean up old results
$configPath = Join-Path $sharedDir "config.json"
$resultPath = Join-Path $sharedDir "result.json"
if (Test-Path $configPath) { Remove-Item $configPath -Force }
if (Test-Path $resultPath) { Remove-Item $resultPath -Force }

# Write configuration
$configObj = [ordered]@{
    scenario = $Scenario
}
$configObj | ConvertTo-Json | Set-Content -Path $configPath -Encoding utf8 -Force

# Generate WSB config
$wsbContent = @"
<Configuration>
  <MappedFolders>
    <MappedFolder>
      <HostFolder>$repoRoot</HostFolder>
      <SandboxFolder>C:\ag-course-index</SandboxFolder>
      <ReadOnly>true</ReadOnly>
    </MappedFolder>
    <MappedFolder>
      <HostFolder>$sharedDir</HostFolder>
      <SandboxFolder>C:\shared</SandboxFolder>
      <ReadOnly>false</ReadOnly>
    </MappedFolder>
  </MappedFolders>
  <LogonCommand>
    <Command>powershell.exe -ExecutionPolicy Bypass -File C:\ag-course-index\tests\sandbox\sandbox-init.ps1</Command>
  </LogonCommand>
</Configuration>
"@

$wsbContent | Set-Content -Path $wsbPath -Encoding utf8 -Force

Write-Host "成功產生 Windows Sandbox 設定檔：$wsbPath" -ForegroundColor Green
Write-Host "已配置情境為：$Scenario" -ForegroundColor Green

if ($NoLaunch.IsPresent) {
    Write-Host "已指定 -NoLaunch，不安裝或啟動沙盒。" -ForegroundColor Yellow
    return
}

if (-not (Test-Path "C:\Windows\System32\WindowsSandbox.exe")) {
    throw "系統中未偵測到 Windows Sandbox。請確保已啟用「Windows 沙盒」功能。"
}

Write-Host "正在啟動 Windows Sandbox，請於沙盒視窗內觀察測試結果..." -ForegroundColor Cyan
Start-Process -FilePath "C:\Windows\System32\WindowsSandbox.exe" -ArgumentList "`"$wsbPath`"" -Wait
