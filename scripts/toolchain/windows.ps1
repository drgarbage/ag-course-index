Set-StrictMode -Version Latest

$script:WindowsPackageCatalog = @{
    node_lts = @{ id = 'OpenJS.NodeJS.LTS'; verify = @('node', '--version'); minimum_version = '24.4.0' }
    cloudflared = @{ id = 'Cloudflare.cloudflared'; verify = @('cloudflared', '--version') }
}

function Get-WindowsToolDefinition {
    param([Parameter(Mandatory)][string]$ToolId)

    $definition = $script:WindowsPackageCatalog[$ToolId]
    if ($null -eq $definition) { throw "Unknown Windows tool: $ToolId" }
    return $definition
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
