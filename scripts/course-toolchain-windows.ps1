[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:CourseToolchainWindowsModulePath = Join-Path $PSScriptRoot 'toolchain/windows.ps1'
. $script:CourseToolchainWindowsModulePath
$script:CourseToolchainReportModulePath = Join-Path $PSScriptRoot 'toolchain/report.ps1'
. $script:CourseToolchainReportModulePath

$script:CourseToolchainCatalogPath = Join-Path $PSScriptRoot 'toolchain/catalog.json'
$script:CourseToolchainToolIds = @(
    'git_gh', 'node_lts', 'cloudflared', 'docker_desktop',
    'antigravity', 'vscode', 'browser'
)
$script:CourseToolchainGuiTools = @('antigravity', 'vscode', 'browser')
$script:CourseToolchainProfiles = [ordered]@{
    base = @('git_gh', 'node_lts')
    line = @('git_gh', 'node_lts', 'cloudflared')
    data = @('git_gh', 'node_lts', 'docker_desktop')
    full = @('git_gh', 'node_lts', 'cloudflared', 'docker_desktop')
}

function Test-CourseToolchainExactList {
    param(
        [Parameter(Mandatory)][object[]]$Actual,
        [Parameter(Mandatory)][string[]]$Expected,
        [Parameter(Mandatory)][string]$Description
    )

    if ($Actual.Count -ne $Expected.Count) { throw "Invalid $Description." }
    for ($index = 0; $index -lt $Expected.Count; $index++) {
        if ($Actual[$index] -cne $Expected[$index]) { throw "Invalid $Description." }
    }
}

function Get-CourseToolchainCatalog {
    param([string]$CatalogPath = $script:CourseToolchainCatalogPath)

    if (-not (Test-Path -LiteralPath $CatalogPath -PathType Leaf)) {
        throw "Course toolchain catalog was not found: $CatalogPath"
    }
    try {
        $catalog = Get-Content -LiteralPath $CatalogPath -Raw | ConvertFrom-Json -AsHashtable -Depth 8
    } catch {
        throw "Invalid course toolchain catalog."
    }

    if ($catalog.schema_version -ne 1) { throw 'Unsupported catalog schema version.' }
    if ($catalog.profiles -isnot [System.Collections.IDictionary] -or $catalog.gui_tools -isnot [System.Collections.IEnumerable]) {
        throw 'Invalid course toolchain catalog.'
    }

    foreach ($profileName in $catalog.profiles.Keys) {
        $profileTools = @($catalog.profiles[$profileName])
        $seenTools = @{}
        foreach ($toolId in $profileTools) {
            if ($toolId -isnot [string] -or -not ($script:CourseToolchainToolIds -ccontains $toolId)) {
                throw "Unknown tool ID: $toolId"
            }
            if ($seenTools.ContainsKey($toolId)) { throw "Duplicate tool ID: $toolId" }
            $seenTools[$toolId] = $true
        }
    }

    $guiTools = @($catalog.gui_tools)
    $seenGuiTools = @{}
    foreach ($toolId in $guiTools) {
        if ($toolId -isnot [string] -or -not ($script:CourseToolchainGuiTools -ccontains $toolId)) {
            throw "Unknown GUI tool ID: $toolId"
        }
        if ($seenGuiTools.ContainsKey($toolId)) { throw "Duplicate GUI tool ID: $toolId" }
        $seenGuiTools[$toolId] = $true
    }

    if ($catalog.node_lts_major -ne 24) { throw 'Invalid Node LTS major.' }
    if (@($catalog.profiles.Keys).Count -ne $script:CourseToolchainProfiles.Count) { throw 'Invalid profile catalog.' }
    foreach ($profileName in $script:CourseToolchainProfiles.Keys) {
        if (-not (@($catalog.profiles.Keys) -ccontains $profileName)) { throw "Invalid profile catalog: $profileName" }
        Test-CourseToolchainExactList -Actual @($catalog.profiles[$profileName]) -Expected $script:CourseToolchainProfiles[$profileName] -Description "profile $profileName"
    }
    Test-CourseToolchainExactList -Actual $guiTools -Expected $script:CourseToolchainGuiTools -Description 'GUI tool catalog'

    return $catalog
}

function Get-CourseToolchainPlan {
    param(
        [Parameter(Mandatory)][string]$Profile,
        [string[]]$GuiTools = @()
    )

    if (-not (@($script:CourseToolchainProfiles.Keys) -ccontains $Profile)) { throw "Unknown profile: $Profile" }
    $catalog = Get-CourseToolchainCatalog

    $requestedGuiTools = @($GuiTools | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $seenGuiTools = @{}
    foreach ($toolId in $requestedGuiTools) {
        if (-not (@($catalog.gui_tools) -ccontains $toolId)) { throw "Unknown GUI tool: $toolId" }
        if ($seenGuiTools.ContainsKey($toolId)) { throw "Duplicate GUI tool: $toolId" }
        $seenGuiTools[$toolId] = $true
    }

    foreach ($toolId in @($catalog.profiles[$Profile]) + $requestedGuiTools) {
        [pscustomobject]@{ tool_id = [string]$toolId }
    }
}

function Install-CourseToolchainWindowsDockerDesktop {
    param(
        [scriptblock]$ConfirmationProvider = {
            param($message)
            (Read-Host "$message [y/N]") -match '^(?i:y|yes)$'
        },
        [scriptblock]$PrerequisiteProvider = { Get-WindowsDockerPrerequisites }
    )

    $prerequisites = & $PrerequisiteProvider
    $wslChangeConfirmed = $false
    if (-not [bool]$prerequisites.wsl2) {
        Write-Host 'Impact: installing WSL 2 changes Windows features and requires a restart. Docker Desktop will not be installed until Windows restarts.'
        $wslChangeConfirmed = [bool](& $ConfirmationProvider 'Install WSL 2')
    }

    Write-Host 'Impact: Docker Desktop installs Docker Desktop and starts its official application.'
    $dockerConfirmed = [bool](& $ConfirmationProvider 'Install Docker Desktop')
    Install-WindowsDockerDesktop -Confirmed:$dockerConfirmed -WslChangeConfirmed:$wslChangeConfirmed -PrerequisiteProvider $PrerequisiteProvider
}

function Install-CourseToolchainWindowsGuiTool {
    param(
        [Parameter(Mandatory)][ValidateSet('antigravity', 'vscode', 'browser')][string]$ToolId,
        [scriptblock]$ConfirmationProvider = {
            param($message)
            (Read-Host "$message [y/N]") -match '^(?i:y|yes)$'
        }
    )

    if (-not ($script:CourseToolchainGuiTools -ccontains $ToolId)) { throw "Unknown GUI tool: $ToolId" }
    Write-Host "Impact: $ToolId will be installed from its fixed WinGet package ID; no GUI application will be started."
    $confirmed = [bool](& $ConfirmationProvider "Install $ToolId")
    Invoke-WindowsGuiToolInstall -ToolId $ToolId -Confirmed:$confirmed
}

function Get-CourseToolchainWindowsReadinessReport {
    param(
        [Parameter(Mandatory)][ValidateSet('base', 'line', 'data', 'full')][string]$Profile,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Results,
        [AllowNull()][object]$FreeBytes = $null
    )

    New-ToolchainReport -Profile $Profile -Results $Results -FreeBytes $FreeBytes
}
