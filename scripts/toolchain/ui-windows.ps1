# Windows Course Toolchain Installer UI Module
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Show-Menu {
    Clear-Host
    Write-Host "=========================================================" -ForegroundColor Cyan
    Write-Host "           反重力 AI 課程環境一鍵安裝程式" -ForegroundColor Cyan
    Write-Host "=========================================================" -ForegroundColor Cyan
    Write-Host " 1) 完整安裝 (全裝) - 安裝並設定 Git/GH、Node、Cloudflared、Docker、GUI、中文化"
    Write-Host " 2) 自訂安裝 (選特定標的安裝)"
    Write-Host " 3) 執行環境 Readiness Report 檢查"
    Write-Host " 4) 結束退出"
    Write-Host "=========================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Get-DiskFreeBytes {
    $systemDrive = [System.IO.Path]::GetPathRoot($PSScriptRootVal)
    try {
        $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$($systemDrive.TrimEnd('\'))'"
        return $disk.FreeSpace
    } catch {
        try {
            $driveInfo = [System.IO.DriveInfo]::new($systemDrive)
            return $driveInfo.AvailableFreeSpace
        } catch {
            return $null
        }
    }
}

function Get-EnvironmentReadiness {
    $results = @()

    # 1. git_gh
    $gitPresent = $null -ne (Get-Command 'git' -ErrorAction SilentlyContinue)
    $ghPresent = $null -ne (Get-Command 'gh' -ErrorAction SilentlyContinue)
    $gitVersion = ''
    $ghVersion = ''
    if ($gitPresent) {
        $gitVersion = (git --version) -replace 'git version '
    }
    if ($ghPresent) {
        $ghVersion = (gh --version | Select-Object -First 1) -replace 'gh version '
    }

    $ghAuthed = $false
    $authMsg = ''
    if ($ghPresent) {
        & gh auth status --hostname github.com *> $null
        $ghAuthed = ($LASTEXITCODE -eq 0)
        if (-not $ghAuthed) {
            $authMsg = 'GitHub CLI 尚未登入。'
        }
    } else {
        $authMsg = 'GitHub CLI 未安裝。'
    }

    $gitGhStatus = 'failed'
    if ($gitPresent -and $ghPresent -and $ghAuthed) {
        $gitGhStatus = 'ready'
    } elseif ($gitPresent -and $ghPresent) {
        $gitGhStatus = 'failed'
    } else {
        $gitGhStatus = 'missing'
    }
    $results += [pscustomobject]@{
        tool_id = 'git_gh'
        status = $gitGhStatus
        version = if ($gitVersion) { "git:$gitVersion; gh:$ghVersion" } else { '' }
        safe_message = $authMsg
    }

    # 2. node_lts
    try {
        $nodeState = Get-WindowsToolState -ToolId 'node_lts'
        $results += $nodeState
    } catch {
        $results += [pscustomobject]@{ tool_id = 'node_lts'; status = 'failed' }
    }

    # 3. cloudflared
    try {
        $cfState = Get-WindowsToolState -ToolId 'cloudflared'
        $results += $cfState
    } catch {
        $results += [pscustomobject]@{ tool_id = 'cloudflared'; status = 'failed' }
    }

    # 4. docker_desktop
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
        $results += [pscustomobject]@{ tool_id = 'docker_desktop'; status = 'failed'; safe_message = '檢查 Docker Desktop 狀態時發生錯誤。' }
    }

    # 5. GUI tools
    foreach ($guiId in @('antigravity', 'vscode', 'browser')) {
        $installed = Test-WindowsGuiToolInstalled -ToolId $guiId
        $results += [pscustomobject]@{
            tool_id = $guiId
            status = if ($installed) { 'ready' } else { 'missing' }
        }
    }

    $freeBytes = Get-DiskFreeBytes
    $report = New-ToolchainReport -Profile 'full' -Results $results -FreeBytes $freeBytes
    return $report
}

function Show-ReadinessReport {
    Write-Host "`n=== 執行環境 Readiness Report 檢查 ===" -ForegroundColor Cyan
    $report = Get-EnvironmentReadiness
    
    $readyColor = if ($report.ready) { 'Green' } else { 'Red' }
    $readyText = if ($report.ready) { '【就緒】' } else { '【未就緒】' }
    
    Write-Host "總體準備狀態: $readyText" -ForegroundColor $readyColor
    Write-Host "需求設定檔等級: $($report.profile)"
    
    if ($null -ne $report.disk.free_bytes) {
        $freeGB = [Math]::Round($report.disk.free_bytes / 1GB, 2)
        $reqGB = [Math]::Round($report.disk.required_bytes / 1GB, 2)
        Write-Host "磁碟可用空間: $freeGB GB (系統建議: $reqGB GB, 狀態: $($report.disk.status))"
    } else {
        Write-Host "磁碟可用空間: 未知"
    }
    
    Write-Host "下一步指引: $($report.next_step)" -ForegroundColor Yellow
    Write-Host "各工具細部狀態:"
    Write-Host "--------------------------------------------------------"
    foreach ($tool in $report.tools) {
        $statusColor = if ($tool.status -in @('installed', 'updated')) { 'Green' } else { 'Yellow' }
        $reqMark = if ($tool.requirement -eq 'required') { '[必備]' } else { '[選配]' }
        Write-Host " $reqMark $($tool.tool_id):" -NoNewline
        Write-Host " $($tool.status)" -ForegroundColor $statusColor -NoNewline
        if ($tool.version) {
            Write-Host " (版本: $($tool.version))" -NoNewline
        }
        Write-Host ""
        if ($tool.tool_id -eq 'node_lts' -and $tool.status -eq 'failed' -and (Get-Command 'nvm' -ErrorAction SilentlyContinue)) {
            Write-Host "   提示: 偵測到您系統中安裝了 NVM for Windows。WinGet 安裝的 Node 可能被 NVM 覆蓋。請手動執行 'nvm install 24.18.0' 與 'nvm use 24.18.0' 切換版本。" -ForegroundColor Yellow
        }
        if ($tool.safe_message) {
            Write-Host "   備註: $($tool.safe_message)" -ForegroundColor DarkGray
        }
    }
    Write-Host "=========================================================" -ForegroundColor Cyan
    Write-Host ""
}

function Install-GitGh {
    Write-Host "`n▶ 正在啟動 Git 與 GitHub CLI 獨立安裝程序..." -ForegroundColor Cyan
    $gitGhScript = Join-Path $PSScriptRootVal 'install-git-gh-windows.ps1'
    if (Test-Path -LiteralPath $gitGhScript -PathType Leaf) {
        $p = Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$gitGhScript`"" -Wait -PassThru -NoNewWindow
        if ($p.ExitCode -eq 0) {
            Write-Host "✓ Git 與 GitHub CLI 安裝與設定完成。" -ForegroundColor Green
            return $true
        } else {
            Write-Warning "Git 與 GitHub CLI 安裝程序返回錯誤碼 $($p.ExitCode)"
            return $false
        }
    } else {
        Write-Warning "找不到 Git/GH 安裝指令檔：$gitGhScript"
        return $false
    }
}

function Set-McpServerConfig {
    $appData = $env:APPDATA
    $paths = @(
        (Join-Path $appData "Code\User\globalStorage\saoudrizwan.claude-dev\settings\cline_mcp_settings.json"),
        (Join-Path $appData "Code\User\globalStorage\roovim.rogue-dev\settings\cline_mcp_settings.json"),
        (Join-Path $appData "Cursor\User\globalStorage\saoudrizwan.claude-dev\settings\cline_mcp_settings.json"),
        (Join-Path $appData "Cursor\User\globalStorage\roovim.rogue-dev\settings\cline_mcp_settings.json"),
        (Join-Path $appData "Antigravity\User\globalStorage\saoudrizwan.claude-dev\settings\cline_mcp_settings.json"),
        (Join-Path $appData "Antigravity\User\globalStorage\roovim.rogue-dev\settings\cline_mcp_settings.json"),
        (Join-Path $appData "Antigravity IDE\User\globalStorage\saoudrizwan.claude-dev\settings\cline_mcp_settings.json"),
        (Join-Path $appData "Antigravity IDE\User\globalStorage\roovim.rogue-dev\settings\cline_mcp_settings.json"),
        (Join-Path $appData "Claude\claude_desktop_config.json")
    )

    foreach ($path in $paths) {
        $appFolder = ""
        if ($path -match "Claude") {
            $appFolder = Join-Path $appData "Claude"
        } else {
            if ($path -match "Code\\User") { $appFolder = Join-Path $appData "Code" }
            elseif ($path -match "Cursor\\User") { $appFolder = Join-Path $appData "Cursor" }
            elseif ($path -match "Antigravity IDE\\User") { $appFolder = Join-Path $appData "Antigravity IDE" }
            elseif ($path -match "Antigravity\\User") { $appFolder = Join-Path $appData "Antigravity" }
        }

        if (-not (Test-Path $appFolder -PathType Container)) {
            continue
        }

        $dir = Split-Path $path
        if (-not (Test-Path $dir -PathType Container)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }

        $jsonObj = $null
        if (Test-Path $path -PathType Leaf) {
            try {
                $content = Get-Content -Raw -Path $path
                if (-not [string]::IsNullOrWhiteSpace($content)) {
                    $jsonObj = ConvertFrom-Json $content
                }
            } catch {
                $jsonObj = $null
            }
        }

        if ($null -eq $jsonObj) {
            $jsonObj = [PSCustomObject]@{ mcpServers = [PSCustomObject]@{} }
        }

        if ($null -eq $jsonObj.mcpServers -or -not ($jsonObj.PSObject.Properties['mcpServers'])) {
            $jsonObj | Add-Member -MemberType NoteProperty -Name 'mcpServers' -Value ([PSCustomObject]@{}) -Force
        }

        if ($jsonObj.mcpServers -is [System.Collections.IDictionary]) {
            $jsonObj.mcpServers['gemini-api-docs'] = @{
                command = "uvx"
                args = @("--from", "git+https://github.com/philschmid/gemini-api-docs-mcp", "gemini-docs-mcp")
            }
        } else {
            if (-not ($jsonObj.mcpServers.PSObject.Properties['gemini-api-docs'])) {
                $jsonObj.mcpServers | Add-Member -MemberType NoteProperty -Name 'gemini-api-docs' -Value ([PSCustomObject]@{
                    command = "uvx"
                    args = @("--from", "git+https://github.com/philschmid/gemini-api-docs-mcp", "gemini-docs-mcp")
                }) -Force
            } else {
                $jsonObj.mcpServers.'gemini-api-docs' = [PSCustomObject]@{
                    command = "uvx"
                    args = @("--from", "git+https://github.com/philschmid/gemini-api-docs-mcp", "gemini-docs-mcp")
                }
            }
        }

        try {
            $newJsonContent = ConvertTo-Json $jsonObj -Depth 100
            Set-Content -Path $path -Value $newJsonContent -Encoding utf8 -Force
            Write-Host "  ✓ 已更新 MCP 設定：$path" -ForegroundColor Green
        } catch {
            Write-Warning "無法寫入 MCP 設定：$path - $($_.Exception.Message)"
        }
    }
}

function Install-AllTools {
    Write-Host "`n正在執行完整一鍵安裝 (全裝)..." -ForegroundColor Cyan
    
    Install-GitGh | Out-Null
    Refresh-WindowsProcessPath
    
    Write-Host "`n▶ 檢查並安裝 Node.js LTS..." -ForegroundColor Cyan
    $nodeState = Get-WindowsToolState -ToolId 'node_lts'
    if ($nodeState.status -ne 'ready') {
        Invoke-WindowsToolInstall -ToolId 'node_lts' -Confirmed:$true | Out-Null
    } else {
        Write-Host "  ✓ NodeJS 已就緒" -ForegroundColor Green
    }
    
    Write-Host "`n▶ 檢查並安裝 uv..." -ForegroundColor Cyan
    try {
        powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
        Write-Host "  ✓ uv 安裝/更新完成。" -ForegroundColor Green
    } catch {
        Write-Warning "uv 安裝失敗：$($_.Exception.Message)"
    }
    
    Write-Host "`n▶ 設定 Gemini API Docs MCP..." -ForegroundColor Cyan
    Set-McpServerConfig
    
    Refresh-WindowsProcessPath
    if (Get-Command 'npx' -ErrorAction SilentlyContinue) {
        Write-Host "`n▶ 安裝 Google 官方 Gemini Skills..." -ForegroundColor Cyan
        try {
            & npx skills add google-gemini/gemini-skills --skill gemini-api-dev gemini-live-api-dev gemini-interactions-api --global --agent claude-code antigravity gemini-cli -y
            Write-Host "  ✓ Gemini Skills 安裝完成。" -ForegroundColor Green
        } catch {
            Write-Warning "Gemini Skills 安裝失敗：$($_.Exception.Message)"
        }
    }
    
    Write-Host "`n▶ 檢查並安裝 Cloudflared..." -ForegroundColor Cyan
    $cfState = Get-WindowsToolState -ToolId 'cloudflared'
    if ($cfState.status -ne 'ready') {
        Invoke-WindowsToolInstall -ToolId 'cloudflared' -Confirmed:$true | Out-Null
    } else {
        Write-Host "  ✓ Cloudflared 已就緒" -ForegroundColor Green
    }
    
    Write-Host "`n▶ 檢查並安裝 Docker Desktop..." -ForegroundColor Cyan
    Install-CourseToolchainWindowsDockerDesktop -ConfirmationProvider { $true } | Out-Null
    
    Write-Host "`n▶ 檢查並安裝 GUI 工具 (VS Code, Browser, Antigravity)..." -ForegroundColor Cyan
    Invoke-WindowsGuiToolInstall -ToolId 'vscode' -Confirmed:$true | Out-Null
    Invoke-WindowsGuiToolInstall -ToolId 'browser' -Confirmed:$true | Out-Null
    Invoke-WindowsGuiToolInstall -ToolId 'antigravity' -Confirmed:$true | Out-Null
    
    Write-Host "`n▶ 檢查並安裝中文化模組..." -ForegroundColor Cyan
    Invoke-WindowsLocalizationInstall -Target 'vscode' -Confirmed:$true | Out-Null
    Invoke-WindowsLocalizationInstall -Target 'antigravity_ide' -Confirmed:$true | Out-Null
    Invoke-WindowsLocalizationInstall -Target 'antigravity_app' -Confirmed:$true -ConfirmationProvider { $true } | Out-Null
    
    Write-Host "`n一鍵全裝程序執行完畢。" -ForegroundColor Green
    Show-ReadinessReport
}

function Install-Custom {
    Write-Host "`n自訂選擇安裝工具" -ForegroundColor Cyan
    Write-Host "請選擇要安裝的項目 (多選，以逗號分隔，例如: 1,3,5):"
    Write-Host " 1) Git 與 GitHub CLI (git_gh)"
    Write-Host " 2) Node.js LTS (node_lts)"
    Write-Host " 3) Cloudflare Tunnel (cloudflared)"
    Write-Host " 4) Docker Desktop (docker_desktop)"
    Write-Host " 5) GUI 工具 (Antigravity IDE, VS Code, Browser)"
    Write-Host " 6) Antigravity 2.0 中文化"
    Write-Host " 7) Antigravity IDE 中文化 (設定教學)"
    Write-Host " 8) VS Code 中文化 (設定教學)"
    Write-Host " 9) uv、MCP 與 Gemini Skills 安裝"
    Write-Host ""
    
    $selection = Read-Host "請輸入編號"
    if ([string]::IsNullOrWhiteSpace($selection)) {
        Write-Host "未輸入 any 項目，返回選單。"
        return
    }
    
    $parts = @($selection.Split(',; ') | Where-Object { $_ -match '^[1-9]$' })
    if ($parts.Count -eq 0) {
        Write-Host "無效的選擇，返回選單。"
        return
    }
    
    foreach ($opt in $parts) {
        switch ($opt) {
            "1" {
                Install-GitGh | Out-Null
            }
            "2" {
                Write-Host "`n▶ 檢查並安裝 Node.js LTS..." -ForegroundColor Cyan
                Invoke-WindowsToolInstall -ToolId 'node_lts' -Confirmed:$true | Out-Null
            }
            "3" {
                Write-Host "`n▶ 檢查並安裝 Cloudflared..." -ForegroundColor Cyan
                Invoke-WindowsToolInstall -ToolId 'cloudflared' -Confirmed:$true | Out-Null
            }
            "4" {
                Write-Host "`n▶ 檢查並安裝 Docker Desktop..." -ForegroundColor Cyan
                Install-CourseToolchainWindowsDockerDesktop | Out-Null
            }
            "5" {
                Write-Host "`n▶ 檢查並安裝 GUI 工具..." -ForegroundColor Cyan
                $choice = Read-Host "請選擇：1) 全部安裝 2) 僅安裝 Antigravity 3) 僅安裝 VS Code 4) 僅安裝瀏覽器 [預設: 1]"
                if ($choice -eq '2') {
                    Invoke-WindowsGuiToolInstall -ToolId 'antigravity' -Confirmed:$true | Out-Null
                } elseif ($choice -eq '3') {
                    Invoke-WindowsGuiToolInstall -ToolId 'vscode' -Confirmed:$true | Out-Null
                } elseif ($choice -eq '4') {
                    Invoke-WindowsGuiToolInstall -ToolId 'browser' -Confirmed:$true | Out-Null
                } else {
                    Invoke-WindowsGuiToolInstall -ToolId 'vscode' -Confirmed:$true | Out-Null
                    Invoke-WindowsGuiToolInstall -ToolId 'browser' -Confirmed:$true | Out-Null
                    Invoke-WindowsGuiToolInstall -ToolId 'antigravity' -Confirmed:$true | Out-Null
                }
            }
            "6" {
                Write-Host "`n▶ 檢查並執行 Antigravity 2.0 中文化..." -ForegroundColor Cyan
                $res = Invoke-WindowsLocalizationInstall -Target 'antigravity_app' -Confirmed:$true
                if ($res.status -eq 'ready') {
                    Write-Host "✓ Antigravity 2.0 中文化完成。" -ForegroundColor Green
                } elseif ($res.status -eq 'failed') {
                    Write-Host "✗ Antigravity 2.0 中文化失敗：$($res.reason)" -ForegroundColor Red
                } else {
                    Write-Host "  Antigravity 2.0 中文化已取消。" -ForegroundColor Yellow
                }
            }
            "7" {
                Write-Host "`n▶ 檢查並執行 Antigravity IDE 中文化..." -ForegroundColor Cyan
                $res = Invoke-WindowsLocalizationInstall -Target 'antigravity_ide' -Confirmed:$true
                if ($res.status -eq 'ready') {
                    Write-Host "✓ Antigravity IDE 中文化完成。" -ForegroundColor Green
                } elseif ($res.status -eq 'failed') {
                    Write-Host "✗ Antigravity IDE 中文化失敗：$($res.reason)" -ForegroundColor Red
                }
            }
            "8" {
                Write-Host "`n▶ 檢查並執行 VS Code 中文化..." -ForegroundColor Cyan
                $res = Invoke-WindowsLocalizationInstall -Target 'vscode' -Confirmed:$true
                if ($res.status -eq 'ready') {
                    Write-Host "✓ VS Code 中文化完成。" -ForegroundColor Green
                } elseif ($res.status -eq 'failed') {
                    Write-Host "✗ VS Code 中文化失敗：$($res.reason)" -ForegroundColor Red
                }
            }
            "9" {
                Write-Host "`n▶ 檢查並安裝 uv..." -ForegroundColor Cyan
                try {
                    powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
                    Write-Host "  ✓ uv 安裝/更新完成。" -ForegroundColor Green
                } catch {
                    Write-Warning "uv 安裝失敗：$($_.Exception.Message)"
                }
                Write-Host "`n▶ 設定 Gemini API Docs MCP..." -ForegroundColor Cyan
                Set-McpServerConfig
                Write-Host "`n▶ 安裝 Google 官方 Gemini Skills..." -ForegroundColor Cyan
                if (Get-Command 'npx' -ErrorAction SilentlyContinue) {
                    try {
                        & npx skills add google-gemini/gemini-skills --skill gemini-api-dev gemini-live-api-dev gemini-interactions-api --global --agent claude-code antigravity gemini-cli -y
                        Write-Host "  ✓ Gemini Skills 安裝完成。" -ForegroundColor Green
                    } catch {
                        Write-Warning "Gemini Skills 安裝失敗：$($_.Exception.Message)"
                    }
                }
            }
        }
    }
    
    Refresh-WindowsProcessPath
    Show-ReadinessReport
}

if ($NonInteractive) {
    Install-AllTools
    exit 0
}

# Main Loop
$running = $true
do {
    Show-Menu
    $choice = Read-Host "請輸入選擇編號 (1-4)"
    switch ($choice) {
        "1" {
            Install-AllTools
            Read-Host "執行完畢，按 Enter 繼續"
        }
        "2" {
            Install-Custom
            Read-Host "執行完畢，按 Enter 繼續"
        }
        "3" {
            Show-ReadinessReport
            Read-Host "按 Enter 繼續"
        }
        "4" {
            Write-Host "感謝使用，再見！"
            $running = $false
        }
        default {
            Write-Host "無效的選擇，請輸入 1-4 之間的數字。" -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
} while ($running)
