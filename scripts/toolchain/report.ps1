Set-StrictMode -Version Latest

$script:ToolchainReportProfiles = [ordered]@{
    base = @('git_gh', 'node_lts')
    line = @('git_gh', 'node_lts', 'cloudflared')
    data = @('git_gh', 'node_lts', 'docker_desktop')
    full = @('git_gh', 'node_lts', 'cloudflared', 'docker_desktop')
}
$script:ToolchainReportGuiTools = @('antigravity', 'vscode', 'browser')
$script:ToolchainReportStatuses = @('installed', 'updated', 'skipped', 'needs_restart', 'failed')
$script:ToolchainReportRequiredBytes = [ordered]@{
    base = 2147483648
    line = 3221225472
    data = 12884901888
    full = 13958643712
}

function ConvertTo-ToolchainSafeText {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return '' }
    $text = [string]$Value
    $text = $text -replace '(?i)\b(?:gh[pousr]_[A-Za-z0-9_-]+|(?:sk|pk)_[A-Za-z0-9_-]+)\b', '[REDACTED]'
    $text = $text -replace '(?i)\b(token|password|secret|api[_-]?key)\s*[:=]?\s*\S+', '$1 [REDACTED]'
    $text = $text -replace '(?i)[A-Z]:\\Users\\[^\r\n"'']+', '[USER_PATH]'
    $text = $text -replace '(?i)/(?:Users|home)/[^\r\n"'']+', '[USER_PATH]'
    return $text
}

function Get-ToolchainResultValue {
    param(
        [Parameter(Mandatory)][object]$Result,
        [Parameter(Mandatory)][string]$Name
    )

    if ($Result -is [System.Collections.IDictionary] -and $Result.Contains($Name)) { return $Result[$Name] }
    $property = $Result.PSObject.Properties[$Name]
    if ($null -ne $property) { return $property.Value }
    return $null
}

function New-ToolchainReport {
    param(
        [Parameter(Mandatory)][ValidateSet('base', 'line', 'data', 'full')][string]$Profile,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Results,
        [AllowNull()][object]$FreeBytes = $null
    )

    $requiredTools = @($script:ToolchainReportProfiles[$Profile])
    $knownTools = @($requiredTools + $script:ToolchainReportGuiTools)
    $resultsByTool = @{}
    foreach ($result in $Results) {
        if ($null -eq $result) { continue }
        $toolId = $null
        if ($result -is [System.Collections.IDictionary]) {
            if (-not $result.Contains('tool_id')) { continue }
            $rawToolId = $result['tool_id']
            if ($rawToolId -isnot [string]) { continue }
            $toolId = $rawToolId
        } else {
            $property = $result.PSObject.Properties['tool_id']
            if ($null -eq $property) { continue }
            if ($property.Value -isnot [string]) { continue }
            $toolId = $property.Value
        }
        if ($toolId -notin $knownTools -or $resultsByTool.ContainsKey($toolId)) { continue }
        $resultsByTool[$toolId] = $result
    }

    $toolReports = [System.Collections.Generic.List[object]]::new()
    foreach ($toolId in $requiredTools + @($script:ToolchainReportGuiTools | Where-Object { $resultsByTool.ContainsKey($_) } | Sort-Object)) {
        $result = $resultsByTool[$toolId]
        $status = 'failed'
        if ($null -eq $result) {
            $status = 'failed'
        } elseif ($result -is [System.Collections.IDictionary]) {
            $rawStatus = $result['status']
            if ($rawStatus -is [string]) { $status = $rawStatus }
        } else {
            $property = $result.PSObject.Properties['status']
            if ($null -ne $property -and $property.Value -is [string]) { $status = $property.Value }
        }
        if ($status -eq 'ready') { $status = 'installed' }
        if ($status -notin $script:ToolchainReportStatuses) { $status = 'failed' }
        $version = ''
        $message = if ($null -eq $result) { '未取得工具結果。' } else { Get-ToolchainResultValue -Result $result -Name 'safe_message' }
        if ($null -ne $result) {
            foreach ($versionField in @('installed_version', 'detected_version', 'version')) {
                $candidate = Get-ToolchainResultValue -Result $result -Name $versionField
                if (-not [string]::IsNullOrWhiteSpace([string]$candidate)) { $version = $candidate; break }
            }
        }
        $toolReports.Add([pscustomobject][ordered]@{
            tool_id = $toolId
            requirement = if ($toolId -in $requiredTools) { 'required' } else { 'optional' }
            version = ConvertTo-ToolchainSafeText $version
            status = $status
            needs_restart = ($status -eq 'needs_restart')
            safe_message = ConvertTo-ToolchainSafeText $message
        })
    }

    $requiredReports = @($toolReports | Where-Object { $_.requirement -eq 'required' })
    $requiredBytes = [long]$script:ToolchainReportRequiredBytes[$Profile]
    $parsedFreeBytes = 0L
    $hasValidFreeBytes = $null -ne $FreeBytes -and
        [long]::TryParse([string]$FreeBytes, [ref]$parsedFreeBytes) -and
        $parsedFreeBytes -ge 0
    $effectiveFreeBytes = if ($hasValidFreeBytes) { $parsedFreeBytes } else { $null }
    $diskStatus = if ($null -eq $effectiveFreeBytes) { 'unknown' } elseif ($effectiveFreeBytes -ge $requiredBytes) { 'enough' } else { 'insufficient' }
    $toolsReady = @($requiredReports | Where-Object { $_.status -notin @('installed', 'updated') }).Count -eq 0
    $ready = $toolsReady -and $diskStatus -ne 'insufficient'
    $restartRequired = @($toolReports | Where-Object { $_.needs_restart }).Count -gt 0
    $nextStep = if ($diskStatus -eq 'insufficient') {
        '可用磁碟空間不足；請釋放空間後重新執行 readiness report。'
    } elseif ($restartRequired) {
        '請重新啟動電腦後重新執行 readiness report。'
    } elseif (-not $ready) {
        '請依報告中的固定安裝流程重試；仍失敗請聯絡講師。'
    } else {
        '課程工具鏈已就緒；依課程指引開啟專案。'
    }

    return [pscustomobject][ordered]@{
        profile = $Profile
        ready = $ready
        disk = [pscustomobject][ordered]@{
            free_bytes = $effectiveFreeBytes
            required_bytes = $requiredBytes
            status = $diskStatus
        }
        restart_required = $restartRequired
        next_step = $nextStep
        tools = @($toolReports)
    }
}
