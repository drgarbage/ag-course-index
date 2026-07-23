Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

param(
    [Parameter(Mandatory)][string]$Scenario
)

Write-Host "正在設定沙盒測試情境：$Scenario..." -ForegroundColor Cyan

switch ($Scenario) {
    "Clean" {
        Write-Host "Clean 情境，無需進行預裝。" -ForegroundColor Green
    }
    
    "NvmInstalled" {
        Write-Host "正在為 NvmInstalled 情境預裝 NVM..." -ForegroundColor Cyan
        
        # 1. Download and install NVM
        $zipPath = "$env:TEMP\nvm-setup.zip"
        $extractPath = "$env:TEMP\nvm-setup"
        
        Write-Host "  正在下載 NVM for Windows..."
        Invoke-WebRequest -Uri "https://github.com/coreybutler/nvm-windows/releases/download/1.1.12/nvm-setup.zip" -OutFile $zipPath
        
        Write-Host "  正在解壓縮與安裝..."
        if (Test-Path $extractPath) { Remove-Item $extractPath -Recurse -Force }
        Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
        
        $p = Start-Process -FilePath "$extractPath\nvm-setup.exe" -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES" -Wait -PassThru
        if ($p.ExitCode -ne 0) {
            throw "NVM 安裝失敗，錯誤碼：$($p.ExitCode)"
        }
        
        # Refresh environment Path
        $nvmPath = Join-Path $env:APPDATA "nvm"
        $nodejsSymlink = "C:\Program Files\nodejs"
        
        # Ensure PATH updated
        $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        $env:Path = "$machinePath;$userPath;$nvmPath;$nodejsSymlink"
        
        Write-Host "  NVM 安裝成功。正在安裝並使用 Node.js v20.19.6..."
        # Set NVM settings
        & nvm root $nvmPath
        & nvm install 20.19.6
        & nvm use 20.19.6
        
        Write-Host "  Node.js v20.19.6 設定完成。" -ForegroundColor Green
    }
    
    "DockerStopped" {
        Write-Host "正在為 DockerStopped 情境模擬已安裝但未啟動的 Docker..." -ForegroundColor Cyan
        
        # Create dummy Docker folder and script
        $binDir = "C:\Program Files\Docker\Docker\resources\bin"
        New-Item -ItemType Directory -Path $binDir -Force | Out-Null
        
        $dockerCmd = @"
@echo off
echo Client:
echo  Version:           29.6.1
echo failed to connect to the docker API at npipe:////./pipe/dockerDesktopLinuxEngine
exit /b 1
"@
        $dockerCmd | Set-Content -Path (Join-Path $binDir "docker.cmd") -Force
        
        # Update Machine PATH to include the dummy Docker bin folder
        $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
        [Environment]::SetEnvironmentVariable('Path', "$machinePath;$binDir", 'Machine')
        $env:Path = "$machinePath;$binDir"
        
        Write-Host "  模擬 Docker (Stopped) 設定完成。" -ForegroundColor Green
    }
}
