Set-StrictMode -Version Latest

$script:WindowsPackageCatalog = @{
    node_lts = @{ id = 'OpenJS.NodeJS.LTS'; verify = @('node', '--version'); minimum_version = '24.4.0' }
    cloudflared = @{ id = 'Cloudflare.cloudflared'; verify = @('cloudflared', '--version') }
}
$script:WindowsGuiPackageCatalog = @{
    antigravity = @{ id = 'Google.Antigravity' }
    vscode = @{ id = 'Microsoft.VisualStudioCode' }
    browser = @{ id = 'Google.Chrome' }
}
$script:WindowsDockerDesktopPackageId = 'Docker.DockerDesktop'
$script:WindowsDockerDesktopPath = 'C:\Program Files\Docker\Docker\Docker Desktop.exe'
$script:WindowsDockerDesktopWingetArguments = @(
    'install', '--id', $script:WindowsDockerDesktopPackageId, '--exact', '--source', 'winget',
    '--accept-source-agreements', '--accept-package-agreements'
)

function Get-WindowsToolDefinition {
    param([Parameter(Mandatory)][string]$ToolId)

    if (-not (@($script:WindowsPackageCatalog.Keys) -ccontains $ToolId)) { throw "Unknown Windows tool: $ToolId" }
    $definition = $script:WindowsPackageCatalog[$ToolId]
    return $definition
}

function Get-WindowsGuiToolDefinition {
    param([Parameter(Mandatory)][string]$ToolId)

    if (-not (@($script:WindowsGuiPackageCatalog.Keys) -ccontains $ToolId)) { throw "Unknown Windows GUI tool: $ToolId" }
    $definition = $script:WindowsGuiPackageCatalog[$ToolId]
    return $definition
}

function Test-WindowsGuiToolInstalled {
    param(
        [Parameter(Mandatory)][string]$ToolId,
        [scriptblock]$PathProbe = { param($path) Test-Path -LiteralPath $path -PathType Leaf },
        [scriptblock]$CommandLookup = { param($command) $null -ne (Get-Command $command -ErrorAction SilentlyContinue) }
    )

    if (-not (@($script:WindowsGuiPackageCatalog.Keys) -ccontains $ToolId)) { throw "Unknown Windows GUI tool: $ToolId" }
    switch ($ToolId) {
        'antigravity' {
            $userLocal = $env:LOCALAPPDATA
            $systemFiles = $env:ProgramFiles
            $systemFilesX86 = ${env:ProgramFiles(x86)}
            
            $paths = @(
                "C:\Program Files\Antigravity\Antigravity.exe",
                "C:\Program Files\Antigravity IDE\Antigravity IDE.exe",
                "$userLocal\Programs\Antigravity\Antigravity.exe",
                "$userLocal\Programs\Antigravity IDE\Antigravity IDE.exe"
            )
            if ($systemFiles) {
                $paths += "$systemFiles\Antigravity\Antigravity.exe"
                $paths += "$systemFiles\Antigravity IDE\Antigravity IDE.exe"
            }
            if ($systemFilesX86) {
                $paths += "$systemFilesX86\Antigravity\Antigravity.exe"
                $paths += "$systemFilesX86\Antigravity IDE\Antigravity IDE.exe"
            }

            foreach ($p in $paths) {
                if (& $PathProbe $p) { return $true }
            }
            return [bool](& $CommandLookup 'antigravity') -or [bool](& $CommandLookup 'antigravity-ide')
        }
        'vscode' {
            return [bool](& $PathProbe 'C:\Program Files\Microsoft VS Code\Code.exe') -or [bool](& $CommandLookup 'code')
        }
        'browser' {
            return [bool](& $PathProbe 'C:\Program Files\Google\Chrome\Application\chrome.exe') -or
                [bool](& $PathProbe 'C:\Program Files\Microsoft\Edge\Application\msedge.exe') -or
                [bool](& $PathProbe 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe') -or
                [bool](& $CommandLookup 'chrome') -or [bool](& $CommandLookup 'msedge')
        }
        default { throw "Unknown Windows GUI tool: $ToolId" }
    }
}

function Refresh-WindowsProcessPath {
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $pathEntries = @($machinePath, $userPath) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $env:Path = $pathEntries -join ';'
}

function ConvertTo-WindowsNodeVersion {
    param([Parameter(Mandatory)][string]$Version)

    if ($Version -notmatch '^v?(?<major>0|[1-9]\d*)\.(?<minor>0|[1-9]\d*)\.(?<patch>0|[1-9]\d*)$') {
        return $null
    }
    return [version]"$($Matches.major).$($Matches.minor).$($Matches.patch)"
}

function Test-WindowsExactArgumentList {
    param(
        [Parameter(Mandatory)][string[]]$Actual,
        [Parameter(Mandatory)][string[]]$Expected
    )

    if ($Actual.Count -ne $Expected.Count) { return $false }
    for ($index = 0; $index -lt $Expected.Count; $index++) {
        if ($Actual[$index] -ne $Expected[$index]) { return $false }
    }
    return $true
}

function Get-WindowsToolState {
    param(
        [Parameter(Mandatory)][string]$ToolId,
        [scriptblock]$CommandLookup = { param($command) $null -ne (Get-Command $command -ErrorAction SilentlyContinue) },
        [scriptblock]$VersionRunner = { param($command, $arguments) & $command @arguments }
    )

    $definition = Get-WindowsToolDefinition -ToolId $ToolId
    $command = [string]$definition.verify[0]
    $arguments = @($definition.verify[1..($definition.verify.Count - 1)])
    if (-not [bool](& $CommandLookup $command)) {
        return [pscustomobject]@{ tool_id = $ToolId; status = 'missing' }
    }

    try {
        $version = [string](& $VersionRunner $command $arguments)
    } catch {
        return [pscustomobject]@{ tool_id = $ToolId; status = 'failed' }
    }
    if ([string]::IsNullOrWhiteSpace($version)) {
        return [pscustomobject]@{ tool_id = $ToolId; status = 'failed' }
    }
    if ($ToolId -eq 'node_lts') {
        $nodeVersion = ConvertTo-WindowsNodeVersion -Version $version
        if ($null -eq $nodeVersion) {
            return [pscustomobject]@{ tool_id = $ToolId; status = 'failed'; version = $version }
        }
        $minimumVersion = [version]$definition.minimum_version
        if ($nodeVersion.Major -ne $minimumVersion.Major -or $nodeVersion -lt $minimumVersion) {
            return [pscustomobject]@{ tool_id = $ToolId; status = 'outdated'; version = $version }
        }
    }

    return [pscustomobject]@{ tool_id = $ToolId; status = 'ready'; version = $version }
}

function Invoke-WindowsWingetCommand {
    param([Parameter(Mandatory)][string[]]$Arguments)

    $allowed = Test-WindowsExactArgumentList -Actual $Arguments -Expected @('--version')
    if (-not $allowed) {
        foreach ($definition in $script:WindowsPackageCatalog.Values) {
            $installArguments = @(
                'install', '--id', [string]$definition.id, '--exact', '--source', 'winget',
                '--accept-source-agreements', '--accept-package-agreements'
            )
            if (Test-WindowsExactArgumentList -Actual $Arguments -Expected $installArguments) {
                $allowed = $true
                break
            }
        }
        foreach ($definition in $script:WindowsGuiPackageCatalog.Values) {
            $installArguments = @(
                'install', '--id', [string]$definition.id, '--exact', '--source', 'winget',
                '--accept-source-agreements', '--accept-package-agreements'
            )
            if (Test-WindowsExactArgumentList -Actual $Arguments -Expected $installArguments) {
                $allowed = $true
                break
            }
        }
    }
    if (-not $allowed -and (Test-WindowsExactArgumentList -Actual $Arguments -Expected $script:WindowsDockerDesktopWingetArguments)) {
        $allowed = $true
    }
    if (-not $allowed) { throw 'Unknown WinGet arguments.' }

    try {
        $output = & winget @Arguments 2>&1
        $exitCode = if ($?) { [int]$LASTEXITCODE } else { 1 }
    } catch {
        $output = @($_.Exception.Message)
        $exitCode = 1
    }
    [pscustomobject]@{
        exit_code = $exitCode
        stdout = [string]($output -join [Environment]::NewLine)
        stderr = ''
    }
}

function Get-WindowsDockerPrerequisites {
    param(
        [scriptblock]$OsProbe = { (Get-CimInstance -ClassName Win32_OperatingSystem).Caption },
        [scriptblock]$VirtualizationProbe = {
            $processor = Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1
            [bool]$processor.VirtualizationFirmwareEnabled
        },
        [scriptblock]$WslProbe = {
            $output = & wsl.exe --status 2>$null
            if ($LASTEXITCODE -ne 0) { return $null }
            [string]($output -join [Environment]::NewLine)
        }
    )

    $wslProbeResult = & $WslProbe
    $wsl2 = if ($wslProbeResult -is [bool]) {
        [bool]$wslProbeResult
    } else {
        [string]$wslProbeResult -match '(?m)(?:^|\r?\n)[^\r\n0-9]*2\s*$'
    }
    [pscustomobject][ordered]@{
        os = [string](& $OsProbe)
        virtualization = [bool](& $VirtualizationProbe)
        wsl2 = $wsl2
    }
}

function Invoke-WindowsDockerCommand {
    param(
        [Parameter(Mandatory)][string]$Arguments,
        [Parameter(Mandatory)][int]$TimeoutMilliseconds
    )

    if ($Arguments -notin @('version', 'compose version')) { throw 'Unknown Docker arguments.' }
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = 'docker'
    $startInfo.Arguments = $Arguments
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    try {
        $process = [System.Diagnostics.Process]::Start($startInfo)
        if ($null -eq $process) { return 1 }
        if (-not $process.WaitForExit($TimeoutMilliseconds)) {
            $process.Kill()
            $process.WaitForExit()
            return 1
        }
        return [int]$process.ExitCode
    } catch {
        return 1
    }
}

function Test-WindowsDockerReady {
    param(
        [int]$CommandTimeoutMilliseconds = 10000,
        [scriptblock]$DockerProbe = {
            param($timeoutMilliseconds)
            Invoke-WindowsDockerCommand -Arguments 'version' -TimeoutMilliseconds $timeoutMilliseconds
        },
        [scriptblock]$ComposeProbe = {
            param($arguments, $timeoutMilliseconds)
            if ($arguments -ne 'compose version') { throw 'Unknown Docker Compose arguments.' }
            Invoke-WindowsDockerCommand -Arguments $arguments -TimeoutMilliseconds $timeoutMilliseconds
        }
    )

    try {
        $deadline = [DateTime]::UtcNow.AddMilliseconds([Math]::Max($CommandTimeoutMilliseconds, 1))
        $dockerTimeoutMilliseconds = [Math]::Max(1, [int][Math]::Ceiling(($deadline - [DateTime]::UtcNow).TotalMilliseconds))
        $dockerExitCode = & $DockerProbe $dockerTimeoutMilliseconds
        if ($dockerExitCode -ne 0) { return [pscustomobject]@{ status = 'failed' } }
        $composeTimeoutMilliseconds = [Math]::Max(1, [int][Math]::Ceiling(($deadline - [DateTime]::UtcNow).TotalMilliseconds))
        $composeExitCode = & $ComposeProbe 'compose version' $composeTimeoutMilliseconds
    } catch {
        return [pscustomobject]@{ status = 'failed' }
    }
    if ($dockerExitCode -eq 0 -and $composeExitCode -eq 0) {
        return [pscustomobject]@{ status = 'ready' }
    }
    return [pscustomobject]@{ status = 'failed' }
}

function Wait-WindowsDockerReady {
    param(
        [Parameter(Mandatory)][int]$TimeoutSeconds,
        [scriptblock]$Probe
    )

    $effectiveTimeoutSeconds = [Math]::Min([Math]::Max($TimeoutSeconds, 1), 120)
    $deadline = [DateTime]::UtcNow.AddSeconds($effectiveTimeoutSeconds)
    do {
        try {
            $remainingMilliseconds = [Math]::Max(1, [int][Math]::Ceiling(($deadline - [DateTime]::UtcNow).TotalMilliseconds))
            $ready = if ($null -eq $Probe) {
                (Test-WindowsDockerReady -CommandTimeoutMilliseconds $remainingMilliseconds).status -eq 'ready'
            } else {
                $probePowerShell = [System.Management.Automation.PowerShell]::Create()
                try {
                    [void]$probePowerShell.AddScript($Probe.ToString())
                    $probeInvocation = $probePowerShell.BeginInvoke()
                    if (-not $probeInvocation.AsyncWaitHandle.WaitOne($remainingMilliseconds)) {
                        $probePowerShell.Stop()
                        $false
                    } else {
                        [bool]($probePowerShell.EndInvoke($probeInvocation) | Select-Object -Last 1)
                    }
                } finally {
                    $probePowerShell.Dispose()
                }
            }
            if ($ready) {
                return [pscustomobject]@{ status = 'ready' }
            }
        } catch {
            # Docker Desktop can be launching; keep polling until the deadline.
        }
        if ([DateTime]::UtcNow -ge $deadline) { break }
        Start-Sleep -Milliseconds 250
    } while ($true)

    return [pscustomobject]@{ status = 'failed' }
}

function Install-WindowsDockerDesktop {
    param(
        [switch]$Confirmed,
        [switch]$WslChangeConfirmed,
        [scriptblock]$PrerequisiteProvider = { Get-WindowsDockerPrerequisites },
        [scriptblock]$WslInstaller = {
            param($arguments)
            & wsl.exe @arguments 2>&1 | Out-Null
            @{ exit_code = if ($LASTEXITCODE -eq 0) { 0 } else { 1 } }
        },
        [scriptblock]$PackageRunner = {
            param($command, $arguments)
            if ($command -ne 'winget') { throw 'Unknown package command.' }
            Invoke-WindowsWingetCommand -Arguments $arguments
        },
        [scriptblock]$AppStarter = {
            param($path)
            Start-Process -FilePath $path
            $true
        },
        [scriptblock]$ReadyWaiter = { Wait-WindowsDockerReady -TimeoutSeconds 120 }
    )

    if (-not $Confirmed) {
        return [pscustomobject]@{ tool_id = 'docker_desktop'; status = 'skipped' }
    }

    $prerequisites = & $PrerequisiteProvider
    $changeRequiresRestart = $false
    if ($prerequisites -is [System.Collections.IDictionary] -and $prerequisites.Contains('change_requires_restart')) {
        $changeRequiresRestart = [bool]$prerequisites['change_requires_restart']
    } elseif ($null -ne $prerequisites.PSObject.Properties['change_requires_restart']) {
        $changeRequiresRestart = [bool]$prerequisites.change_requires_restart
    }
    if ($changeRequiresRestart) {
        return [pscustomobject]@{ tool_id = 'docker_desktop'; status = 'needs_restart' }
    }
    if ([string]$prerequisites.os -notmatch '(?i)^windows\b') {
        return [pscustomobject]@{ tool_id = 'docker_desktop'; status = 'failed'; reason = 'unsupported_os' }
    }
    if (-not [bool]$prerequisites.virtualization) {
        return [pscustomobject]@{ tool_id = 'docker_desktop'; status = 'failed'; reason = 'virtualization_unavailable' }
    }
    if (-not [bool]$prerequisites.wsl2) {
        if (-not $WslChangeConfirmed) {
            return [pscustomobject]@{
                tool_id = 'docker_desktop'
                status = 'needs_wsl_confirmation'
                impact = 'WSL 2 installation will require a Windows restart.'
            }
        }
        $wslResult = & $WslInstaller @('--install', '--no-distribution')
        if ($null -eq $wslResult -or [int]$wslResult.exit_code -ne 0) {
            return [pscustomobject]@{ tool_id = 'docker_desktop'; status = 'failed'; reason = 'wsl_install_failed' }
        }
        return [pscustomobject]@{ tool_id = 'docker_desktop'; status = 'needs_restart' }
    }

    $wingetCheck = & $PackageRunner 'winget' @('--version')
    if ($null -eq $wingetCheck -or [int]$wingetCheck.exit_code -ne 0) {
        return [pscustomobject]@{ tool_id = 'docker_desktop'; status = 'failed'; reason = 'winget_unavailable' }
    }
    $installResult = & $PackageRunner 'winget' $script:WindowsDockerDesktopWingetArguments
    if ($null -eq $installResult -or [int]$installResult.exit_code -ne 0) {
        return [pscustomobject]@{ tool_id = 'docker_desktop'; status = 'failed'; reason = 'winget_install_failed' }
    }

    try {
        if (-not [bool](& $AppStarter $script:WindowsDockerDesktopPath)) {
            return [pscustomobject]@{ tool_id = 'docker_desktop'; status = 'failed'; reason = 'desktop_start_failed' }
        }
    } catch {
        return [pscustomobject]@{ tool_id = 'docker_desktop'; status = 'failed'; reason = 'desktop_start_failed' }
    }
    $readyResult = & $ReadyWaiter
    if ($null -ne $readyResult -and $readyResult.status -eq 'ready') {
        return [pscustomobject]@{ tool_id = 'docker_desktop'; status = 'ready' }
    }
    return [pscustomobject]@{ tool_id = 'docker_desktop'; status = 'failed'; reason = 'docker_not_ready' }
}

function Invoke-WindowsToolInstall {
    param(
        [Parameter(Mandatory)][string]$ToolId,
        [Parameter(Mandatory)][bool]$Confirmed,
        [scriptblock]$CommandLookup = { param($command) $null -ne (Get-Command $command -ErrorAction SilentlyContinue) },
        [scriptblock]$VersionRunner = { param($command, $arguments) & $command @arguments },
        [scriptblock]$PackageRunner = {
            param($command, $arguments)
            if ($command -ne 'winget') { throw 'Unknown package command.' }
            Invoke-WindowsWingetCommand -Arguments $arguments
        }
    )

    $definition = Get-WindowsToolDefinition -ToolId $ToolId
    if (-not $Confirmed) {
        return [pscustomobject]@{ tool_id = $ToolId; status = 'skipped' }
    }

    # NVM Support for Node.js LTS
    if ($ToolId -eq 'node_lts' -and [bool](& $CommandLookup 'nvm')) {
        $nvmVersion = '24.18.0'
        try {
            & nvm install $nvmVersion
            & nvm use $nvmVersion
        } catch {
            return [pscustomobject]@{ tool_id = $ToolId; status = 'failed'; reason = 'nvm_install_failed' }
        }
        Refresh-WindowsProcessPath
        $state = Get-WindowsToolState -ToolId $ToolId -CommandLookup $CommandLookup -VersionRunner $VersionRunner
        if ($state.status -eq 'ready') {
            return [pscustomobject]@{ tool_id = $ToolId; status = 'ready' }
        }
        if ($state.status -eq 'outdated') {
            return [pscustomobject]@{ tool_id = $ToolId; status = 'needs_restart' }
        }
        return [pscustomobject]@{ tool_id = $ToolId; status = 'failed'; reason = 'verification_failed' }
    }

    $wingetCheck = & $PackageRunner 'winget' @('--version')
    if ($null -eq $wingetCheck -or [int]$wingetCheck.exit_code -ne 0) {
        return [pscustomobject]@{ tool_id = $ToolId; status = 'failed'; reason = 'winget_unavailable' }
    }

    $installArguments = @(
        'install', '--id', [string]$definition.id, '--exact', '--source', 'winget',
        '--accept-source-agreements', '--accept-package-agreements'
    )
    $installResult = & $PackageRunner 'winget' $installArguments
    if ($null -eq $installResult -or [int]$installResult.exit_code -ne 0) {
        return [pscustomobject]@{ tool_id = $ToolId; status = 'failed'; reason = 'winget_install_failed' }
    }

    Refresh-WindowsProcessPath
    $state = Get-WindowsToolState -ToolId $ToolId -CommandLookup $CommandLookup -VersionRunner $VersionRunner
    if ($state.status -eq 'ready') {
        return [pscustomobject]@{ tool_id = $ToolId; status = 'ready' }
    }
    if ($state.status -eq 'missing') {
        return [pscustomobject]@{ tool_id = $ToolId; status = 'needs_restart' }
    }
    return [pscustomobject]@{ tool_id = $ToolId; status = 'failed'; reason = 'verification_failed' }
}

function Invoke-WindowsGuiToolInstall {
    param(
        [Parameter(Mandatory)][string]$ToolId,
        [Parameter(Mandatory)][bool]$Confirmed,
        [scriptblock]$AppProbe = { param($tool) Test-WindowsGuiToolInstalled -ToolId $tool },
        [scriptblock]$PackageRunner = {
            param($command, $arguments)
            if ($command -ne 'winget') { throw 'Unknown package command.' }
            Invoke-WindowsWingetCommand -Arguments $arguments
        }
    )

    $definition = Get-WindowsGuiToolDefinition -ToolId $ToolId
    if (-not $Confirmed) { return [pscustomobject]@{ tool_id = $ToolId; status = 'skipped' } }
    if ([bool](& $AppProbe $ToolId)) { return [pscustomobject]@{ tool_id = $ToolId; status = 'installed' } }

    $wingetCheck = & $PackageRunner 'winget' @('--version')
    if ($null -eq $wingetCheck -or [int]$wingetCheck.exit_code -ne 0) {
        return [pscustomobject]@{ tool_id = $ToolId; status = 'failed'; reason = 'winget_unavailable' }
    }
    $installArguments = @(
        'install', '--id', [string]$definition.id, '--exact', '--source', 'winget',
        '--accept-source-agreements', '--accept-package-agreements'
    )
    $installResult = & $PackageRunner 'winget' $installArguments
    if ($null -eq $installResult -or [int]$installResult.exit_code -ne 0) {
        return [pscustomobject]@{ tool_id = $ToolId; status = 'failed'; reason = 'winget_install_failed' }
    }
    if ([bool](& $AppProbe $ToolId)) { return [pscustomobject]@{ tool_id = $ToolId; status = 'installed' } }
    return [pscustomobject]@{ tool_id = $ToolId; status = 'needs_restart' }
}

function ConvertTo-WindowsLocalizationHashtable {
    param([Parameter(Mandatory)][AllowNull()][object]$InputObject)

    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        $result = @{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $result[$property.Name] = ConvertTo-WindowsLocalizationHashtable $property.Value
        }
        return $result
    }
    if ($InputObject -is [System.Collections.IDictionary]) {
        $result = @{}
        foreach ($key in @($InputObject.Keys)) {
            $result[$key] = ConvertTo-WindowsLocalizationHashtable $InputObject[$key]
        }
        return $result
    }
    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        return @(foreach ($item in $InputObject) { ConvertTo-WindowsLocalizationHashtable $item })
    }
    return $InputObject
}

function Test-WindowsLocalizationManifest {
    param(
        [string]$VendorDir = (Join-Path $PSScriptRoot '../vendor/antigravity2-cn'),
        [scriptblock]$HashVerifier = {
            param($filePath)
            if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) { return $null }
            (Get-FileHash -Path $filePath -Algorithm SHA256).Hash.ToLower()
        },
        [scriptblock]$PathProbe = { param($path) Test-Path -LiteralPath $path -PathType Leaf }
    )

    $manifestPath = Join-Path $VendorDir 'manifest.json'
    if (-not (& $PathProbe $manifestPath)) {
        return $false
    }
    try {
        $content = Get-Content -LiteralPath $manifestPath -Raw
        $parsed = ConvertFrom-Json $content
        $manifest = ConvertTo-WindowsLocalizationHashtable $parsed
    } catch {
        return $false
    }
    if ($null -eq $manifest -or $null -eq $manifest.files) {
        return $false
    }
    foreach ($file in $manifest.files) {
        $filePath = Join-Path $VendorDir $file.path
        if (-not (& $PathProbe $filePath)) {
            return $false
        }
        $calculatedHash = & $HashVerifier $filePath
        if ($calculatedHash -cne $file.sha256) {
            return $false
        }
    }
    return $true
}

function Invoke-WindowsLocalizationInstall {
    param(
        [Parameter(Mandatory)][ValidateSet('vscode', 'antigravity_ide', 'antigravity_app')][string]$Target,
        [Parameter(Mandatory)][bool]$Confirmed,
        [scriptblock]$ConfirmationProvider = {
            param($message)
            (Read-Host "$message [y/N]") -match '^(?i:y|yes)$'
        },
        [scriptblock]$HashVerifier = {
            param($dir)
            Test-WindowsLocalizationManifest -VendorDir $dir
        },
        [scriptblock]$CommandRunner = {
            param($command, $arguments)
            try {
                $output = & $command @arguments 2>&1
                $exitCode = if ($?) { [int]$LASTEXITCODE } else { 0 }
            } catch {
                $exitCode = 1
            }
            [pscustomobject]@{ exit_code = $exitCode }
        },
        [scriptblock]$AppProbe = {
            param($toolId)
            Test-WindowsGuiToolInstalled -ToolId $toolId
        }
    )

    if (-not $Confirmed) {
        return [pscustomobject]@{ target = $Target; status = 'skipped' }
    }

    if ($Target -eq 'vscode') {
        Write-Host "`n[中文化設定教學] (VS Code)" -ForegroundColor Yellow
        Write-Host "1. 在 VS Code 中按下快捷鍵 Ctrl + Shift + P"
        Write-Host "2. 輸入 'Language' 並選取 'Configure Display Language' (設定顯示語言)"
        Write-Host "3. 選擇 '繁體中文 (Traditional Chinese)' 即可完成中文化。"
        Write-Host ""
        $isNonInteractive = (Test-Path 'variable:NonInteractive') -and (Get-Variable 'NonInteractive' -ValueOnly)
        if (-not $isNonInteractive) {
            [void](Read-Host "設定完成後請按 Enter 鍵繼續")
        }
        return [pscustomobject]@{ target = $Target; status = 'ready' }
    }

    if ($Target -eq 'antigravity_ide') {
        Write-Host "`n[中文化設定教學] (Antigravity IDE)" -ForegroundColor Yellow
        Write-Host "1. 在 Antigravity IDE 中按下快捷鍵 Ctrl + Shift + P"
        Write-Host "2. 輸入 'Language' 並選取 'Configure Display Language' (設定顯示語言)"
        Write-Host "3. 選擇 '繁體中文 (Traditional Chinese)' 即可完成中文化。"
        Write-Host ""
        $isNonInteractive = (Test-Path 'variable:NonInteractive') -and (Get-Variable 'NonInteractive' -ValueOnly)
        if (-not $isNonInteractive) {
            [void](Read-Host "設定完成後請按 Enter 鍵繼續")
        }
        return [pscustomobject]@{ target = $Target; status = 'ready' }
    }

    if ($Target -eq 'antigravity_app') {
        if (-not (& $AppProbe 'antigravity')) {
            return [pscustomobject]@{ target = $Target; status = 'failed'; reason = 'antigravity_missing' }
        }
        $vendorDir = Join-Path $PSScriptRoot '../vendor/antigravity2-cn'
        $verified = & $HashVerifier $vendorDir
        if (-not $verified) {
            return [pscustomobject]@{ target = $Target; status = 'failed'; reason = 'hash_verification_failed' }
        }
        if (-not (& $ConfirmationProvider '警告：即將執行 Antigravity 2.0 中文化修改。確認要繼續嗎？')) {
            return [pscustomobject]@{ target = $Target; status = 'skipped' }
        }
        if (-not (Get-Command 'node' -ErrorAction SilentlyContinue)) {
            return [pscustomobject]@{ target = $Target; status = 'failed'; reason = 'node_missing' }
        }
        $scriptPath = Join-Path $vendorDir 'localization_engine.js'
        $res = & $CommandRunner 'node' @($scriptPath, '--tw', '--brand-title', 'translated')
        if ($res.exit_code -ne 0) {
            return [pscustomobject]@{ target = $Target; status = 'failed'; reason = 'engine_failed' }
        }
        return [pscustomobject]@{ target = $Target; status = 'ready' }
    }
}

