Set-StrictMode -Version Latest

$script:ToolchainReportProfiles = [ordered]@{
    base = @('git_gh', 'node_lts')
    line = @('git_gh', 'node_lts', 'cloudflared')
    data = @('git_gh', 'node_lts', 'docker_desktop')
    full = @('git_gh', 'node_lts', 'cloudflared', 'docker_desktop')
}
$script:ToolchainReportGuiTools = @('antigravity', 'vscode', 'browser')
$script:ToolchainReportStatuses = @('installed', 'updated', 'skipped', 'needs_restart', 'failed')

function ConvertTo-ToolchainSafeText {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return '' }
    $text = [string]$Value
    $text = $text -replace '(?i)\b(?:gh[pousr]_[A-Za-z0-9_-]+|(?:sk|pk)_[A-Za-z0-9_-]+)\b', '[REDACTED]'
    $text = $text -replace '(?i)\b(token|password|secret|api[_-]?key)\s*[:=]?\s*\S+', '$1 [REDACTED]'
    $text = $text -replace '(?i)[A-Z]:\\Users\\[^\\\s]+', '[USER_PATH]'
    $text = $text -replace '(?i)/(?:Users|home)/[^/\s]+', '[USER_PATH]'
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
        [Parameter(Mandatory)][object[]]$Results
    )

    $requiredTools = @($script:ToolchainReportProfiles[$Profile])
    $knownTools = @($requiredTools + $script:ToolchainReportGuiTools)
    $resultsByTool = @{}
    foreach ($result in $Results) {
        if ($null -eq $result) { continue }
        $toolId = [string](Get-ToolchainResultValue -Result $result -Name 'tool_id')
        if ($toolId -notin $knownTools -or $resultsByTool.ContainsKey($toolId)) { continue }
        $resultsByTool[$toolId] = $result
    }

    $toolReports = [System.Collections.Generic.List[object]]::new()
    foreach ($toolId in $requiredTools + @($script:ToolchainReportGuiTools | Where-Object { $resultsByTool.ContainsKey($_) } | Sort-Object)) {
        $result = $resultsByTool[$toolId]
        $status = if ($null -eq $result) { 'failed' } else { [string](Get-ToolchainResultValue -Result $result -Name 'status') }
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
    $ready = @($requiredReports | Where-Object { $_.status -notin @('installed', 'updated') }).Count -eq 0
    $restartRequired = @($toolReports | Where-Object { $_.needs_restart }).Count -gt 0
    $nextStep = if (-not $ready) {
        '請依報告中的固定安裝流程重試；仍失敗請聯絡講師。'
    } elseif ($restartRequired) {
        '請重新啟動電腦後重新執行 readiness report。'
    } else {
        '課程工具鏈已就緒；依課程指引開啟專案。'
    }

    return [pscustomobject][ordered]@{
        profile = $Profile
        ready = $ready
        disk = 'not_assessed'
        restart_required = $restartRequired
        next_step = $nextStep
        tools = @($toolReports)
    }
}
