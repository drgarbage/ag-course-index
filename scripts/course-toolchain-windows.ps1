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

function ConvertTo-CourseToolchainHashtable {
    # Windows PowerShell 5.1 lacks ConvertFrom-Json -AsHashtable, so deep-convert the
    # PSCustomObject it returns into nested hashtables/arrays. Behaviour matches the
    # -AsHashtable shape the catalog validation below expects on both 5.1 and 7+.
    param([Parameter(Mandatory)][AllowNull()][object]$InputObject)

    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        $result = @{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $result[$property.Name] = ConvertTo-CourseToolchainHashtable $property.Value
        }
        return $result
    }
    if ($InputObject -is [System.Collections.IDictionary]) {
        $result = @{}
        foreach ($key in @($InputObject.Keys)) {
            $result[$key] = ConvertTo-CourseToolchainHashtable $InputObject[$key]
        }
        return $result
    }
    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        return @(foreach ($item in $InputObject) { ConvertTo-CourseToolchainHashtable $item })
    }
    return $InputObject
}

function Get-CourseToolchainCatalog {
    param([string]$CatalogPath = $script:CourseToolchainCatalogPath)

    if (-not (Test-Path -LiteralPath $CatalogPath -PathType Leaf)) {
        throw "Course toolchain catalog was not found: $CatalogPath"
    }
    try {
        $parsedCatalog = Get-Content -LiteralPath $CatalogPath -Raw | ConvertFrom-Json
        $catalog = ConvertTo-CourseToolchainHashtable $parsedCatalog
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

function Get-CourseToolchainWindowsFailureValue {
    param(
        [Parameter(Mandatory)][object]$Result,
        [Parameter(Mandatory)][string]$Name
    )

    if ($Result -is [System.Collections.IDictionary] -and $Result.Contains($Name)) { return $Result[$Name] }
    $property = $Result.PSObject.Properties[$Name]
    if ($null -ne $property) { return $property.Value }
    return $null
}

function Get-CourseToolchainWindowsSupportStep {
    param(
        [Parameter(Mandatory)][string]$ToolId,
        [AllowNull()][object]$ErrorKind
    )

    if ($ToolId -cne 'git_gh' -or $ErrorKind -isnot [string]) { return $null }
    if ($ErrorKind -cin @('path', 'network', 'git_install', 'gh_install')) { return $ErrorKind }
    return $null
}

function New-CourseToolchainWindowsSafeDiagnostics {
    param(
        [Parameter(Mandatory)][string]$Step,
        [Parameter(Mandatory)][string]$ToolId,
        [Parameter(Mandatory)][object]$Result
    )

    $found = Get-CourseToolchainWindowsFailureValue -Result $Result -Name 'found'
    $version = Get-CourseToolchainWindowsFailureValue -Result $Result -Name 'version'
    $exitCode = Get-CourseToolchainWindowsFailureValue -Result $Result -Name 'exit_code'
    $errorKind = Get-CourseToolchainWindowsFailureValue -Result $Result -Name 'error_kind'
    $restartRequired = Get-CourseToolchainWindowsFailureValue -Result $Result -Name 'restart_required'
    $engineRunning = Get-CourseToolchainWindowsFailureValue -Result $Result -Name 'engine_running'
    $safeErrorKinds = @('path', 'network', 'git_install', 'gh_install', 'unknown')
    $safeExitCode = 0
    $hasExitCode = [int]::TryParse([string]$exitCode, [ref]$safeExitCode)

    [pscustomobject][ordered]@{
        platform = 'windows'
        step = $Step
        tool_id = $ToolId
        found = [bool]$found
        version = ConvertTo-ToolchainSafeText $version
        exit_code = if ($hasExitCode) { $safeExitCode } else { $null }
        error_kind = if ($errorKind -is [string] -and $errorKind -cin $safeErrorKinds) { $errorKind } else { 'unknown' }
        restart_required = [bool]$restartRequired
        engine_running = [bool]$engineRunning
    }
}

function Resolve-CourseToolchainWindowsFailure {
    param(
        [Parameter(Mandatory)][ValidateSet('base', 'line', 'data', 'full')][string]$Profile,
        [Parameter(Mandatory)][object]$Result,
        [scriptblock]$FallbackWriter = { param($message) Write-Host $message },
        [scriptblock]$ConsentProvider = { Read-Host '是否使用 AI 安裝助理？(y/N)' },
        [scriptblock]$SupportInvoker = {
            param($step, $diagnostics)
            $support = Get-Command Invoke-OptionalInstallSupport -ErrorAction SilentlyContinue
            if ($null -eq $support) { return [pscustomobject]@{ status = 'fallback' } }
            Invoke-OptionalInstallSupport -Step $step -Diagnostics $diagnostics -ConsentProvider { 'y' }
        }
    )

    $toolId = Get-CourseToolchainWindowsFailureValue -Result $Result -Name 'tool_id'
    $status = Get-CourseToolchainWindowsFailureValue -Result $Result -Name 'status'
    $requiredTools = @($script:CourseToolchainProfiles[$Profile])
    if ($toolId -isnot [string] -or $status -isnot [string] -or -not ($requiredTools -ccontains $toolId) -or $status -cne 'failed') {
        return [pscustomobject]@{ status = 'not_applicable'; support_code = $null }
    }

    $errorKind = Get-CourseToolchainWindowsFailureValue -Result $Result -Name 'error_kind'
    $safeMessage = ConvertTo-ToolchainSafeText (Get-CourseToolchainWindowsFailureValue -Result $Result -Name 'safe_message')
    if ([string]::IsNullOrWhiteSpace($safeMessage)) { $safeMessage = '本機固定排錯仍未完成。' }
    & $FallbackWriter $safeMessage

    $step = Get-CourseToolchainWindowsSupportStep -ToolId $toolId -ErrorKind $errorKind
    if ($null -eq $step) {
        & $FallbackWriter '此工具沒有可安全自動執行的支援動作；請聯絡講師。'
        return [pscustomobject]@{ status = 'contact_instructor'; action_id = 'CONTACT_INSTRUCTOR'; support_code = $null }
    }
    if ((& $ConsentProvider) -notmatch '^(?i:y|yes)$') {
        return [pscustomobject]@{ status = 'declined'; support_code = $null }
    }

    $diagnostics = New-CourseToolchainWindowsSafeDiagnostics -Step $step -ToolId $toolId -Result $Result
    try {
        $supportResult = & $SupportInvoker $step $diagnostics
        $supportStatus = Get-CourseToolchainWindowsFailureValue -Result $supportResult -Name 'status'
        $supportCode = ConvertTo-ToolchainSafeText (Get-CourseToolchainWindowsFailureValue -Result $supportResult -Name 'support_code')
        if ($supportStatus -cnotin @('local_resolved', 'resolved', 'fallback', 'action_declined', 'contact', 'limit', 'declined')) { $supportStatus = 'fallback' }
        return [pscustomobject]@{ status = $supportStatus; support_code = $supportCode }
    } catch {
        return [pscustomobject]@{ status = 'fallback'; support_code = $null }
    }
}
