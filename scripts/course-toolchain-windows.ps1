[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:CourseToolchainWindowsModulePath = Join-Path $PSScriptRoot 'toolchain/windows.ps1'
. $script:CourseToolchainWindowsModulePath

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
        if ($Actual[$index] -ne $Expected[$index]) { throw "Invalid $Description." }
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
            if ($toolId -isnot [string] -or $toolId -notin $script:CourseToolchainToolIds) {
                throw "Unknown tool ID: $toolId"
            }
            if ($seenTools.ContainsKey($toolId)) { throw "Duplicate tool ID: $toolId" }
            $seenTools[$toolId] = $true
        }
    }

    $guiTools = @($catalog.gui_tools)
    $seenGuiTools = @{}
    foreach ($toolId in $guiTools) {
        if ($toolId -isnot [string] -or $toolId -notin $script:CourseToolchainGuiTools) {
            throw "Unknown GUI tool ID: $toolId"
        }
        if ($seenGuiTools.ContainsKey($toolId)) { throw "Duplicate GUI tool ID: $toolId" }
        $seenGuiTools[$toolId] = $true
    }

    if ($catalog.node_lts_major -ne 24) { throw 'Invalid Node LTS major.' }
    if (@($catalog.profiles.Keys).Count -ne $script:CourseToolchainProfiles.Count) { throw 'Invalid profile catalog.' }
    foreach ($profileName in $script:CourseToolchainProfiles.Keys) {
        if (-not $catalog.profiles.ContainsKey($profileName)) { throw "Invalid profile catalog: $profileName" }
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

    $catalog = Get-CourseToolchainCatalog
    if (-not $catalog.profiles.ContainsKey($Profile)) { throw "Unknown profile: $Profile" }

    $requestedGuiTools = @($GuiTools | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $seenGuiTools = @{}
    foreach ($toolId in $requestedGuiTools) {
        if ($toolId -notin @($catalog.gui_tools)) { throw "Unknown GUI tool: $toolId" }
        if ($seenGuiTools.ContainsKey($toolId)) { throw "Duplicate GUI tool: $toolId" }
        $seenGuiTools[$toolId] = $true
    }

    foreach ($toolId in @($catalog.profiles[$Profile]) + $requestedGuiTools) {
        [pscustomobject]@{ tool_id = [string]$toolId }
    }
}
