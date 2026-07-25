[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

# 這一段必須是腳本的第一個動作，且只能使用 ConstrainedLanguage 允許的操作
# （屬性讀取、Write-Host、exit）。WDAC／AppLocker 會把 PowerShell 降到
# ConstrainedLanguage，此時任何非核心型別的屬性「設定」都會直接讓腳本中止，
# 學生只會看到一行看不懂的紅字。先擋在這裡，才有機會給出可讀的說明。
if ($ExecutionContext.SessionState.LanguageMode -ne 'FullLanguage') {
    Write-Host ""
    Write-Host "安裝未完成：這台電腦的 PowerShell 被限制在 $($ExecutionContext.SessionState.LanguageMode) 模式。" -ForegroundColor Red
    Write-Host "建議處理方式：這通常是單位的資訊安全政策（WDAC／AppLocker）造成，個人帳號無法自行解除。" -ForegroundColor Yellow
    Write-Host "請將這個畫面提供給講師，並改用另一台電腦或改為手動安裝：" -ForegroundColor Yellow
    Write-Host "  https://git-scm.com/download/win" -ForegroundColor Cyan
    Write-Host "  https://cli.github.com/" -ForegroundColor Cyan
    Read-Host "按 Enter 結束"
    exit 1
}

# 視窗標題是非核心型別的屬性設定，在受限模式下會失敗，因此放在語言模式檢查之後。
try { $Host.UI.RawUI.WindowTitle = "Git 與 GitHub CLI 課程環境安裝程式" } catch {}

$InstallSupportBaseUrl = "https://gemini.printii.com/api/install-support"
# 以一行指令從網路載入本腳本時 $PSScriptRoot 為空，此時沒有本機規則檔可用。
$InstallSupportPatternPath = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    ''
} else {
    Join-Path $PSScriptRoot 'install-support-patterns.json'
}

# Windows PowerShell 5.1 預設可能不啟用 TLS 1.2，會讓後續 HTTPS 請求直接失敗。
try {
    if ([Net.ServicePointManager]::SecurityProtocol -notmatch 'Tls12') {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    }
} catch {}

$CourseGitHubScopes = @('repo', 'read:org', 'workflow')

function Invoke-InstallSupportRequest {
    param([hashtable]$Request)

    $parameters = @{
        Uri = $Request.Uri
        Method = $Request.Method
        Headers = $Request.Headers
        ContentType = "application/json"
        TimeoutSec = $Request.TimeoutSec
    }
    if ($null -ne $Request.Body) {
        $parameters.Body = $Request.Body | ConvertTo-Json -Depth 8 -Compress
    }
    Invoke-RestMethod @parameters
}

function Get-InstallDiagnostics {
    param(
        [Parameter(Mandatory)][string]$Step,
        [string]$LastError = "",
        [scriptblock]$CommandLookup = { param($name) $null -ne (Get-Command $name -ErrorAction SilentlyContinue) },
        [scriptblock]$RawNetworkProbe = {
            if ($null -eq (Get-Command 'curl.exe' -ErrorAction SilentlyContinue)) { return $false }
            & curl.exe --head --silent --show-error --max-time 5 https://raw.githubusercontent.com *> $null
            return ($LASTEXITCODE -eq 0)
        }
    )

    $safeError = $LastError -replace '(?i)C:\\Users\\[^\\\s]+', 'C:\Users\<USER>'
    if ($safeError.Length -gt 4000) { $safeError = $safeError.Substring(0, 4000) }

    [pscustomobject]@{
        platform = "windows"
        step = $Step
        git_found = [bool](& $CommandLookup "git")
        gh_found = [bool](& $CommandLookup "gh")
        winget_available = [bool](& $CommandLookup "winget")
        github_auth_state = if ($Step -eq 'github_auth' -and (& $CommandLookup "gh")) {
            & gh auth status --hostname github.com *> $null
            if ($LASTEXITCODE -eq 0) { 'authenticated' } else { 'not_logged_in' }
        } else { 'unknown' }
        credential_helper_state = if ($Step -eq 'credential_helper' -and (& $CommandLookup "git")) {
            $configuredHelper = git config --global --get-regexp '^credential\..*\.helper$|^credential\.helper$' 2>$null
            if ($configuredHelper) { 'configured' } else { 'missing' }
        } else { 'unknown' }
        raw_github_network = if ($Step -eq 'network') {
            if (& $RawNetworkProbe) { 'ok' } else { 'blocked' }
        } else { 'unknown' }
        stderr = $safeError
    }
}

function New-InstallSupportSession {
    param(
        [Parameter(Mandatory)][string]$InstallerVersion,
        [scriptblock]$Transport = ${function:Invoke-InstallSupportRequest}
    )

    & $Transport @{
        Uri = "$InstallSupportBaseUrl/sessions"
        Method = "POST"
        Headers = @{}
        TimeoutSec = 20
        Body = @{ platform = "windows"; installer_version = $InstallerVersion }
    }
}

function Invoke-InstallDiagnosis {
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][string]$Step,
        [Parameter(Mandatory)][ValidateRange(1, 15)][int]$Attempt,
        [Parameter(Mandatory)]$Diagnostics,
        $PreviousAction = $null,
        [scriptblock]$Transport = ${function:Invoke-InstallSupportRequest}
    )

    & $Transport @{
        Uri = "$InstallSupportBaseUrl/diagnose"
        Method = "POST"
        Headers = @{ Authorization = "Bearer $($Session.session_token)" }
        TimeoutSec = 20
        Body = @{
            session_id = $Session.session_id
            step = $Step
            attempt = $Attempt
            diagnostics = $Diagnostics
            previous_action = $PreviousAction
        }
    }
}

function Invoke-FixedInstallCommand {
    param([string]$Command, [string[]]$Arguments)

    $stdoutFile = [System.IO.Path]::GetTempFileName()
    $stderrFile = [System.IO.Path]::GetTempFileName()
    try {
        $process = Start-Process -FilePath $Command -ArgumentList $Arguments -Wait -PassThru -NoNewWindow `
            -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile
        [pscustomobject]@{
            exit_code = $process.ExitCode
            stdout = Get-Content $stdoutFile -Raw -ErrorAction SilentlyContinue
            stderr = Get-Content $stderrFile -Raw -ErrorAction SilentlyContinue
        }
    } finally {
        Remove-Item $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-AllowlistedInstallAction {
    param(
        [Parameter(Mandatory)][string]$ActionId,
        [switch]$Confirmed,
        [scriptblock]$CommandRunner = ${function:Invoke-FixedInstallCommand}
    )

    $definitions = @{
        CHECK_GIT_VERSION = @{ command = 'git'; arguments = @('--version'); confirmation = $false }
        CHECK_GH_VERSION = @{ command = 'gh'; arguments = @('--version'); confirmation = $false }
        CHECK_WINGET_VERSION = @{ command = 'winget'; arguments = @('--version'); confirmation = $false }
        CHECK_GITHUB_NETWORK = @{ command = 'curl.exe'; arguments = @('--head', '--max-time', '10', 'https://github.com'); confirmation = $false }
        CHECK_RAW_GITHUB_NETWORK = @{ command = 'curl.exe'; arguments = @('--head', '--max-time', '10', 'https://raw.githubusercontent.com'); confirmation = $false }
        CHECK_GH_AUTH_STATUS = @{ command = 'gh'; arguments = @('auth', 'status', '--hostname', 'github.com'); confirmation = $false }
        CHECK_GIT_CREDENTIAL_HELPER = @{ command = 'git'; arguments = @('config', '--global', '--get-regexp', '^credential\..*\.helper$|^credential\.helper$'); confirmation = $false }
        REFRESH_WINDOWS_PATH = @{ command = '__refresh_path__'; arguments = @(); confirmation = $true }
        INSTALL_GIT_WINDOWS = @{ command = 'winget'; arguments = @('install', '--id', 'Git.Git', '--exact', '--source', 'winget', '--accept-source-agreements', '--accept-package-agreements'); confirmation = $true }
        INSTALL_GH_WINDOWS = @{ command = 'winget'; arguments = @('install', '--id', 'GitHub.cli', '--exact', '--source', 'winget', '--accept-source-agreements', '--accept-package-agreements'); confirmation = $true }
        GH_AUTH_LOGIN_WEB = @{ command = 'gh'; arguments = @('auth', 'login', '--hostname', 'github.com', '--git-protocol', 'https', '--web'); confirmation = $true }
        GH_AUTH_SETUP_GIT = @{ command = 'gh'; arguments = @('auth', 'setup-git', '--hostname', 'github.com'); confirmation = $true }
        GH_AUTH_SWITCH = @{ command = 'gh'; arguments = @('auth', 'switch', '--hostname', 'github.com'); confirmation = $true }
        CLEAR_STALE_GITHUB_CREDENTIAL_WINDOWS = @{ command = 'cmdkey.exe'; arguments = @('/delete:LegacyGeneric:target=git:https://github.com'); confirmation = $true }
        OPEN_WINDOWS_CREDENTIAL_MANAGER = @{ command = 'control.exe'; arguments = @('/name', 'Microsoft.CredentialManager'); confirmation = $false }
        RESTART_TERMINAL_REQUIRED = @{ command = '__no_op__'; arguments = @(); confirmation = $true }
        CONTACT_INSTRUCTOR = @{ command = '__no_op__'; arguments = @(); confirmation = $false }
    }

    $definition = $definitions[$ActionId]
    if ($null -eq $definition) { throw "Unknown install support action: $ActionId" }
    if ($definition.confirmation -and -not $Confirmed) {
        return [pscustomobject]@{
            action_id = $ActionId
            exit_code = -1
            stdout = ''
            stderr = 'Explicit confirmation is required.'
        }
    }

    if ($definition.command -eq '__refresh_path__') {
        Refresh-Path
        $commandResult = @{ exit_code = 0; stdout = 'Windows PATH refreshed.'; stderr = '' }
    } elseif ($definition.command -eq '__no_op__') {
        $commandResult = @{ exit_code = 0; stdout = ''; stderr = '' }
    } else {
        $commandResult = & $CommandRunner $definition.command ([string[]]$definition.arguments)
    }

    [pscustomobject]@{
        action_id = $ActionId
        exit_code = [int]$commandResult.exit_code
        stdout = [string]$commandResult.stdout
        stderr = [string]$commandResult.stderr
    }
}

function Test-WindowsActionRequiresConfirmation {
    param([Parameter(Mandatory)][string]$ActionId)
    $stateChangingActions = @(
        'REFRESH_WINDOWS_PATH', 'INSTALL_GIT_WINDOWS', 'INSTALL_GH_WINDOWS',
        'GH_AUTH_LOGIN_WEB', 'GH_AUTH_SETUP_GIT', 'GH_AUTH_SWITCH',
        'CLEAR_STALE_GITHUB_CREDENTIAL_WINDOWS', 'RESTART_TERMINAL_REQUIRED'
    )
    if ($ActionId -in $stateChangingActions) { return $true }
    $readOnlyActions = @(
        'CHECK_GIT_VERSION', 'CHECK_GH_VERSION', 'CHECK_WINGET_VERSION',
        'CHECK_GITHUB_NETWORK', 'CHECK_RAW_GITHUB_NETWORK', 'CHECK_GH_AUTH_STATUS',
        'CHECK_GIT_CREDENTIAL_HELPER', 'OPEN_WINDOWS_CREDENTIAL_MANAGER', 'CONTACT_INSTRUCTOR'
    )
    if ($ActionId -in $readOnlyActions) { return $false }
    throw "Unknown install support action: $ActionId"
}

function Invoke-LocalInstallPattern {
    param(
        [Parameter(Mandatory)][string]$Step,
        [Parameter(Mandatory)]$Diagnostics,
        [Parameter(Mandatory)][string]$RulesPath,
        [scriptblock]$ConfirmationProvider = { Read-Host '是否執行上述本機修復？(y/N)' },
        [scriptblock]$ActionRunner = { param($actionId, $confirmed) Invoke-AllowlistedInstallAction -ActionId $actionId -Confirmed:$confirmed }
    )

    if (-not (Test-Path $RulesPath -PathType Leaf)) { return $null }
    try { $document = Get-Content $RulesPath -Raw | ConvertFrom-Json } catch { return $null }
    if ($document.schema_version -ne 1 -or $null -eq $document.patterns) { return $null }
    $allowedActions = @(
        'CHECK_GIT_VERSION', 'CHECK_GH_VERSION', 'CHECK_WINGET_VERSION', 'CHECK_GITHUB_NETWORK',
        'CHECK_RAW_GITHUB_NETWORK', 'CHECK_GH_AUTH_STATUS', 'CHECK_GIT_CREDENTIAL_HELPER',
        'REFRESH_WINDOWS_PATH', 'INSTALL_GIT_WINDOWS', 'INSTALL_GH_WINDOWS', 'GH_AUTH_LOGIN_WEB',
        'GH_AUTH_SETUP_GIT', 'GH_AUTH_SWITCH', 'CLEAR_STALE_GITHUB_CREDENTIAL_WINDOWS',
        'OPEN_WINDOWS_CREDENTIAL_MANAGER', 'RESTART_TERMINAL_REQUIRED', 'CONTACT_INSTRUCTOR'
    )
    $allowedMatcherValues = @($true, $false, 'missing', 'expired', 'blocked', 'not_logged_in', 0, 1)

    foreach ($pattern in $document.patterns) {
        if ($pattern.platform -ne 'windows' -or $pattern.step -ne $Step) { continue }
        if ($pattern.action_id -notin $allowedActions -or $pattern.risk -notin @('read_only', 'low', 'medium')) { continue }
        $expectedConfirmation = $pattern.risk -in @('low', 'medium')
        if ([bool]$pattern.requires_confirmation -ne $expectedConfirmation) { continue }
        $matched = $true
        foreach ($matcher in $pattern.all.PSObject.Properties) {
            if ($matcher.Value -notin $allowedMatcherValues -or $Diagnostics[$matcher.Name] -ne $matcher.Value) {
                $matched = $false
                break
            }
        }
        if (-not $matched) { continue }

        $confirmed = $true
        if ($pattern.requires_confirmation) {
            $confirmed = ((& $ConfirmationProvider) -match '^(?i:y|yes)$')
        }
        $actionResult = & $ActionRunner ([string]$pattern.action_id) $confirmed
        return [pscustomobject]@{
            matched = $true
            local_pattern_key = [string]$pattern.pattern_key
            action_id = [string]$actionResult.action_id
            exit_code = [int]$actionResult.exit_code
            succeeded = ([int]$actionResult.exit_code -eq 0)
        }
    }
    return $null
}

function Invoke-OptionalInstallSupport {
    param(
        [Parameter(Mandatory)][string]$Step,
        [Parameter(Mandatory)]$Diagnostics,
        [string]$InstallerVersion = '1.0.0',
        [scriptblock]$ConsentProvider = { Read-Host '是否使用 AI 安裝助理？(y/N)' },
        [scriptblock]$ConfirmationProvider = { Read-Host '是否執行上述動作？(y/N)' },
        [scriptblock]$SessionFactory = { param($version) New-InstallSupportSession -InstallerVersion $version },
        [scriptblock]$DiagnosisProvider = {
            param($session, $supportStep, $attempt, $safeDiagnostics, $previousAction)
            Invoke-InstallDiagnosis -Session $session -Step $supportStep -Attempt $attempt `
                -Diagnostics $safeDiagnostics -PreviousAction $previousAction
        },
        [scriptblock]$ActionRunner = {
            param($actionId, $confirmed)
            Invoke-AllowlistedInstallAction -ActionId $actionId -Confirmed:$confirmed
        },
        [scriptblock]$LocalPatternProvider = {
            param($supportStep, $safeDiagnostics, $confirmationProvider, $actionRunner)
            if (-not [string]::IsNullOrWhiteSpace($script:InstallSupportPatternPath)) {
                Invoke-LocalInstallPattern -Step $supportStep -Diagnostics $safeDiagnostics `
                    -RulesPath $script:InstallSupportPatternPath -ConfirmationProvider $confirmationProvider -ActionRunner $actionRunner
            }
        },
        [scriptblock]$OutputWriter = { param($message) Write-Host $message }
    )

    $localResult = & $LocalPatternProvider $Step $Diagnostics $ConfirmationProvider $ActionRunner
    if ($localResult -and $localResult.matched -and $localResult.succeeded) {
        return [pscustomobject]@{
            status = 'local_resolved'
            local_pattern_key = [string]$localResult.local_pattern_key
            support_code = $null
        }
    }
    $initialPreviousAction = $null
    if ($localResult -and $localResult.matched) {
        $initialPreviousAction = @{
            local_pattern_key = [string]$localResult.local_pattern_key
            action_id = [string]$localResult.action_id
            exit_code = [int]$localResult.exit_code
            succeeded = [bool]$localResult.succeeded
        }
    }

    if ((& $ConsentProvider) -notmatch '^(?i:y|yes)$') {
        return [pscustomobject]@{ status = 'declined'; support_code = $null }
    }

    try {
        $session = & $SessionFactory $InstallerVersion
        $previousAction = $initialPreviousAction
        $supportCode = $null
        for ($attempt = 1; $attempt -le 15; $attempt++) {
            $diagnosis = & $DiagnosisProvider $session $Step $attempt $Diagnostics $previousAction
            if ($diagnosis.support_code) { $supportCode = $diagnosis.support_code }
            if ($diagnosis.resolved -isnot [bool]) {
                return [pscustomobject]@{ status = 'fallback'; support_code = $supportCode }
            }
            if ($diagnosis.summary_zh_tw) { & $OutputWriter ([string]$diagnosis.summary_zh_tw) }
            if ($diagnosis.explanation_zh_tw) { & $OutputWriter ([string]$diagnosis.explanation_zh_tw) }
            if ($diagnosis.resolved) {
                return [pscustomobject]@{ status = 'resolved'; support_code = $supportCode }
            }

            $action = $diagnosis.action
            if (-not $action -or -not $action.id) {
                return [pscustomobject]@{ status = 'fallback'; support_code = $supportCode }
            }
            if ($action.title_zh_tw) { & $OutputWriter ([string]$action.title_zh_tw) }
            if ($action.impact_zh_tw) { & $OutputWriter ([string]$action.impact_zh_tw) }
            if ($action.id -eq 'CONTACT_INSTRUCTOR') {
                return [pscustomobject]@{ status = 'contact'; support_code = $supportCode }
            }

            $requiresConfirmation = Test-WindowsActionRequiresConfirmation ([string]$action.id)
            $confirmed = -not $requiresConfirmation
            if ($requiresConfirmation) {
                $confirmed = ((& $ConfirmationProvider) -match '^(?i:y|yes)$')
                if (-not $confirmed) {
                    return [pscustomobject]@{ status = 'action_declined'; support_code = $supportCode }
                }
            }
            $actionResult = & $ActionRunner ([string]$action.id) $confirmed
            $previousAction = @{
                action_id = [string]$actionResult.action_id
                exit_code = [int]$actionResult.exit_code
                succeeded = ([int]$actionResult.exit_code -eq 0)
            }
        }
        [pscustomobject]@{ status = 'limit'; support_code = $supportCode }
    } catch {
        [pscustomobject]@{ status = 'fallback'; support_code = $supportCode }
    }
}

function Write-Step([string]$Message) { Write-Host "`n▶ $Message" -ForegroundColor Cyan }
function Write-Ok([string]$Message) { Write-Host "  ✓ $Message" -ForegroundColor Green }
function Write-WarnZh([string]$Message) { Write-Host "  ! $Message" -ForegroundColor Yellow }
function Stop-Zh(
    [string]$Message,
    [string]$Suggestion,
    [string]$Step = 'network'
) {
    Write-Host "`n安裝未完成：$Message" -ForegroundColor Red
    Write-Host "建議處理方式：$Suggestion" -ForegroundColor Yellow
    $diagnostics = Get-InstallDiagnostics -Step $Step -LastError $Message
    $recovery = Invoke-OptionalInstallSupport -Step $Step -Diagnostics $diagnostics
    if ($recovery.status -in @('resolved', 'local_resolved')) {
        Write-Ok 'AI 安裝助理已完成排錯。'
        exit 0
    }
    if ($recovery.support_code) {
        Write-Host "支援碼：$($recovery.support_code)" -ForegroundColor Yellow
    }
    Read-Host "按 Enter 結束"
    exit 1
}
function Refresh-Path {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}
function Has-Command([string]$Name) {
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-LanguageModeState {
    param(
        [scriptblock]$LanguageModeProvider = { $ExecutionContext.SessionState.LanguageMode }
    )

    # WDAC／AppLocker 會把 PowerShell 降到 ConstrainedLanguage，
    # 此時 .NET 型別呼叫會全面失敗，先擋下來比讓學生看一連串紅字好。
    $mode = try { [string](& $LanguageModeProvider) } catch { 'Unknown' }
    [pscustomobject]@{
        mode = $mode
        is_full = ($mode -eq 'FullLanguage')
    }
}

function Get-ExecutionPolicyState {
    param(
        [scriptblock]$PolicyProvider = { Get-ExecutionPolicy -List },
        [scriptblock]$EffectiveProvider = { Get-ExecutionPolicy }
    )

    $permissive = @('RemoteSigned', 'Unrestricted', 'Bypass')
    $effective = [string](& $EffectiveProvider)
    $lockedByPolicy = $false
    foreach ($entry in @(& $PolicyProvider)) {
        $scope = [string]$entry.Scope
        $value = [string]$entry.ExecutionPolicy
        if ($scope -in @('MachinePolicy', 'UserPolicy') -and $value -notin @('Undefined', '')) {
            # 群組原則的設定優先於 CurrentUser，學生自己改不動。
            if ($value -notin $permissive) { $lockedByPolicy = $true }
        }
    }

    [pscustomobject]@{
        effective = $effective
        allows_local_script = ($effective -in $permissive)
        locked_by_group_policy = $lockedByPolicy
    }
}

function Set-CourseExecutionPolicy {
    param(
        [scriptblock]$PolicySetter = { Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force }
    )

    try {
        & $PolicySetter
        return $true
    } catch {
        return $false
    }
}

function Unblock-CourseScriptFile {
    param(
        [string]$Directory,
        [scriptblock]$Unblocker = { param($path) Unblock-File -LiteralPath $path -ErrorAction Stop }
    )

    if ([string]::IsNullOrWhiteSpace($Directory)) { return 0 }
    $unblocked = 0
    foreach ($file in @(Get-ChildItem -LiteralPath $Directory -Filter '*.ps1' -File -ErrorAction SilentlyContinue)) {
        try {
            & $Unblocker $file.FullName
            $unblocked++
        } catch {}
    }
    return $unblocked
}

function Test-CourseElevation {
    param(
        [scriptblock]$IdentityProvider = {
            $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
            (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole(
                [Security.Principal.WindowsBuiltInRole]::Administrator)
        }
    )

    try { return [bool](& $IdentityProvider) } catch { return $false }
}

function Test-DefaultBrowserAssociation {
    param(
        [scriptblock]$AssociationProvider = {
            $key = 'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice'
            (Get-ItemProperty -Path $key -Name ProgId -ErrorAction Stop).ProgId
        }
    )

    try {
        $progId = [string](& $AssociationProvider)
        return -not [string]::IsNullOrWhiteSpace($progId)
    } catch {
        return $false
    }
}

function Test-GitHubLoginPrerequisite {
    param(
        [scriptblock]$NetworkProbe = {
            if ($null -eq (Get-Command 'curl.exe' -ErrorAction SilentlyContinue)) { return $true }
            & curl.exe --head --silent --show-error --max-time 10 https://github.com *> $null
            return ($LASTEXITCODE -eq 0)
        },
        [scriptblock]$BrowserProbe = { Test-DefaultBrowserAssociation }
    )

    $blockers = @()
    if (-not (& $NetworkProbe)) { $blockers += 'network' }
    if (-not (& $BrowserProbe)) { $blockers += 'browser' }

    [pscustomobject]@{
        ready = ($blockers.Count -eq 0)
        blockers = $blockers
    }
}

function Get-GitHubAuthState {
    param(
        [string[]]$RequiredScopes = @('repo', 'read:org', 'workflow'),
        [scriptblock]$StatusProvider = {
            $text = (& gh auth status --hostname github.com 2>&1 | Out-String)
            [pscustomobject]@{ exit_code = $LASTEXITCODE; text = $text }
        }
    )

    $status = & $StatusProvider
    $text = [string]$status.text
    if ([int]$status.exit_code -ne 0) {
        return [pscustomobject]@{ state = 'not_logged_in'; missing_scopes = @(); text = $text }
    }

    $granted = @()
    foreach ($line in ($text -split "`r?`n")) {
        if ($line -match '(?i)token scopes:\s*(.+)$') {
            $granted = @($Matches[1] -split '[,\s]+' |
                ForEach-Object { $_.Trim().Trim("'").Trim('"') } |
                Where-Object { $_ })
        }
    }

    # gh 未回報 scope 行時無從判斷，視為足夠以免誤擋已經可用的環境。
    if ($granted.Count -eq 0) {
        return [pscustomobject]@{ state = 'authenticated'; missing_scopes = @(); text = $text }
    }

    $missing = @($RequiredScopes | Where-Object { $_ -notin $granted })
    if ($missing.Count -gt 0) {
        return [pscustomobject]@{ state = 'insufficient_scope'; missing_scopes = $missing; text = $text }
    }
    [pscustomobject]@{ state = 'authenticated'; missing_scopes = @(); text = $text }
}

Write-Host "Git 與 GitHub CLI 課程環境安裝程式" -ForegroundColor White
Write-Host "程式只會安裝官方套件、設定 Git，並開啟 GitHub 官方登入頁。"

Write-Step "檢查執行環境權限"
# 受限模式已在腳本開頭擋掉，這裡只是把結果顯示給學生看。
Write-Ok "PowerShell 語言模式：$((Get-LanguageModeState).mode)"

$unblockedCount = Unblock-CourseScriptFile -Directory $PSScriptRoot
if ($unblockedCount -gt 0) {
    Write-Ok "已解除 $unblockedCount 個下載檔案的封鎖標記"
}

$policyState = Get-ExecutionPolicyState
if ($policyState.allows_local_script) {
    Write-Ok "PowerShell 指令碼執行政策：$($policyState.effective)"
} elseif ($policyState.locked_by_group_policy) {
    Write-WarnZh "指令碼執行政策由群組原則鎖定為 $($policyState.effective)，個人帳號無法自行變更。"
    Write-Host "  請改用下列方式啟動本程式（單次繞過，不變更系統設定）："
    Write-Host "  powershell -NoProfile -ExecutionPolicy Bypass -File .\install-git-gh-windows.ps1" -ForegroundColor Cyan
} else {
    Write-WarnZh "目前指令碼執行政策為 $($policyState.effective)，之後重新執行本程式可能會被阻擋。"
    Write-Host "  即將為你的使用者帳號套用 RemoteSigned（只影響目前登入帳號，不需系統管理員權限）。"
    if (Set-CourseExecutionPolicy) {
        Write-Ok "已設定執行政策：$((Get-ExecutionPolicyState).effective)"
    } else {
        Write-WarnZh "自動設定失敗，請自行執行：Set-ExecutionPolicy RemoteSigned -Scope CurrentUser"
    }
}

if (Test-CourseElevation) {
    Write-Ok "目前以系統管理員身分執行"
} else {
    Write-Host "  目前不是系統管理員；安裝 Git 時可能出現「使用者帳戶控制（UAC）」提示，請按「是」。"
}

Write-Step "檢查 WinGet"
if (-not (Has-Command "winget")) {
    Stop-Zh "找不到 WinGet。" "開啟 Microsoft Store，安裝或更新『應用程式安裝程式（App Installer）』，重新開機後再執行本程式。" 'git_install'
}
Write-Ok "WinGet 可使用"

Write-Step "檢查並安裝 Git"
if (Has-Command "git") {
    Write-Ok "已安裝：$(git --version)"
} else {
    Write-Host "  正在透過 Microsoft WinGet 安裝 Git，期間可能出現系統權限提示。"
    try {
        & winget install --id Git.Git --exact --source winget --accept-source-agreements --accept-package-agreements
        if ($LASTEXITCODE -ne 0) { throw "WinGet 結束代碼 $LASTEXITCODE" }
    } catch {
        Stop-Zh "Git 安裝失敗：$($_.Exception.Message)" "確認網路連線、Windows Update 與 Microsoft Store 可用，再以系統管理員身分重新執行。" 'git_install'
    }
    Refresh-Path
    if (-not (Has-Command "git")) {
        Stop-Zh "Git 已執行安裝，但目前終端機仍找不到 git。" "關閉所有 PowerShell／Windows Terminal 視窗，重新開啟後再執行本程式。" 'path'
    }
    Write-Ok "安裝完成：$(git --version)"
}

Write-Step "檢查並安裝 GitHub CLI"
if (Has-Command "gh") {
    Write-Ok "已安裝：$(gh --version | Select-Object -First 1)"
} else {
    try {
        & winget install --id GitHub.cli --exact --source winget --accept-source-agreements --accept-package-agreements
        if ($LASTEXITCODE -ne 0) { throw "WinGet 結束代碼 $LASTEXITCODE" }
    } catch {
        Stop-Zh "GitHub CLI 安裝失敗：$($_.Exception.Message)" "確認網路連線後重新執行；也可從 https://cli.github.com/ 手動安裝。" 'gh_install'
    }
    Refresh-Path
    if (-not (Has-Command "gh")) {
        Stop-Zh "GitHub CLI 已執行安裝，但目前終端機仍找不到 gh。" "關閉所有 PowerShell／Windows Terminal 視窗，重新開啟後再執行本程式。" 'path'
    }
    Write-Ok "安裝完成：$(gh --version | Select-Object -First 1)"
}

Write-Step "檢查 GitHub 登入"
$authState = Get-GitHubAuthState -RequiredScopes $CourseGitHubScopes
if ($authState.state -eq 'authenticated') {
    Write-Ok "GitHub CLI 已登入且授權範圍足夠"
    & gh auth status --hostname github.com
} elseif ($authState.state -eq 'insufficient_scope') {
    $missing = $authState.missing_scopes -join ', '
    Write-WarnZh "已登入，但授權範圍不足（缺少：$missing）。課程操作會在後續步驟失敗，現在補齊授權。"
    Write-Host "  即將開啟瀏覽器補授權，不需要重新登入。"
    & gh auth refresh --hostname github.com -s ($CourseGitHubScopes -join ',')
    if ($LASTEXITCODE -ne 0) {
        Stop-Zh "GitHub 授權範圍補齊失敗（缺少：$missing）。" `
            "請自行執行下列指令後重新執行本程式：gh auth refresh --hostname github.com -s $($CourseGitHubScopes -join ',')" 'github_auth'
    }
    Write-Ok "授權範圍已補齊"
} else {
    Write-WarnZh "尚未登入、授權已失效，或舊憑證無法使用。接下來會協助你登入 GitHub。"

    $prerequisite = Test-GitHubLoginPrerequisite
    if (-not $prerequisite.ready) {
        if ('network' -in $prerequisite.blockers) {
            Stop-Zh "目前無法連線到 github.com，登入流程一定會失敗。" `
                "確認網路、VPN、防火牆或學校代理伺服器設定，能用瀏覽器開啟 https://github.com 之後再重新執行本程式。" 'network'
        }
        Write-WarnZh "找不到預設瀏覽器設定；若登入頁沒有自動開啟，請手動複製畫面上的網址到瀏覽器。"
    }

    $hasAccount = Read-Host "你是否已經有 GitHub 帳號？(Y/n，若不確定就按 Enter)"
    if ($hasAccount -match '^(n|no|否)$') {
        Write-Host "  尚未有帳號沒關係，先完成註冊再繼續。"
        Write-Host "  即將開啟 GitHub 註冊頁面：https://github.com/signup"
        Write-Host "  若你想直接用 Google／Gmail 帳號註冊，請在該頁面選擇「Continue with Google」，並完成畫面上要求的使用者名稱等設定。"
        try { Start-Process "https://github.com/signup" } catch {}
        Read-Host "完成註冊（包含設定使用者名稱）後，按 Enter 繼續"
    }

    $loggedIn = $false
    $maxAttempts = 3
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        Write-Host "  正在開啟 GitHub 網頁登入（第 $attempt/$maxAttempts 次）。請登入正確帳號並完成裝置授權；完成前不要關閉這個視窗。"
        & gh auth login --hostname github.com --git-protocol https --web -s ($CourseGitHubScopes -join ',')
        if ($LASTEXITCODE -eq 0) {
            $loggedIn = $true
            break
        }

        Write-WarnZh "這次登入沒有成功。常見原因：註冊尚未完成（例如用 Google 登入後還沒設定 GitHub 使用者名稱）、瀏覽器分頁忘記按授權、或是等待逾時。"
        if ($attempt -lt $maxAttempts) {
            $retry = Read-Host "要再試一次嗎？(Y/n)"
            if ($retry -match '^(n|no|否)$') { break }
        }
    }

    if (-not $loggedIn) {
        Write-Host "`n你可以自行複製下列指令，在本視窗貼上並執行，完成登入後再重新執行本程式："
        Write-Host "  gh auth login --hostname github.com --git-protocol https --web" -ForegroundColor Cyan
        Write-Host "  若瀏覽器授權一直失敗，可改用互動模式並選擇貼上權杖（Paste an authentication token）："
        Write-Host "  gh auth login --hostname github.com --git-protocol https" -ForegroundColor Cyan
        Write-Host "  若電腦上有多個 GitHub 帳號，請先切換帳號："
        Write-Host "  gh auth switch --hostname github.com" -ForegroundColor Cyan
        Stop-Zh "GitHub 網頁登入未完成。" `
            "在本視窗執行 gh auth login --hostname github.com --git-protocol https --web 完成登入；若剛用 Google 帳號註冊，請先確認已設定好 GitHub 使用者名稱。" 'github_auth'
    }
}

Write-Step "設定 Git 提交身分"
$currentName = git config --global user.name
$currentEmail = git config --global user.email
if ($currentName) { Write-Host "  目前姓名：$currentName" }
do {
    $prompt = if ($currentName) { "Git 顯示姓名（直接按 Enter 保留目前設定）" } else { "Git 顯示姓名（必填）" }
    $inputName = Read-Host $prompt
    if ($inputName) { $currentName = $inputName.Trim() }
} while (-not $currentName)
if ($currentEmail) { Write-Host "  目前信箱：$currentEmail" }
do {
    $prompt = if ($currentEmail) { "Git 提交信箱（直接按 Enter 保留目前設定）" } else { "Git 提交信箱（必填）" }
    $inputEmail = Read-Host $prompt
    if ($inputEmail) { $currentEmail = $inputEmail.Trim() }
    if ($currentEmail -and $currentEmail -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
        Write-WarnZh "信箱格式看起來不正確，請重新輸入。"
        $currentEmail = $null
    }
} while (-not $currentEmail)
git config --global user.name "$currentName"
git config --global user.email "$currentEmail"
git config --global init.defaultBranch main
# Windows 預設 260 字元路徑上限會讓課程專案 clone 失敗。
git config --global core.longpaths true
Write-Ok "Git 身分、預設分支與長路徑支援已設定"

Write-Step "讓 Git 使用 GitHub CLI 保存 HTTPS 憑證"
& gh config set git_protocol https --host github.com
& gh auth setup-git --hostname github.com
if ($LASTEXITCODE -ne 0) {
    Stop-Zh "無法設定 Git credential helper。" "執行 gh auth status 確認登入，再執行 gh auth setup-git。若仍失敗，檢查 Windows 認證管理員中的舊 GitHub 項目。" 'credential_helper'
}
Write-Ok "Git 不應再於每次 pull／push 時重複要求登入"

Write-Step "最終驗證"
$failed = $false
if (-not (Has-Command "git")) { Write-WarnZh "找不到 Git"; $failed = $true }
if (-not (Has-Command "gh")) { Write-WarnZh "找不到 GitHub CLI"; $failed = $true }
$finalAuthState = Get-GitHubAuthState -RequiredScopes $CourseGitHubScopes
if ($finalAuthState.state -eq 'not_logged_in') { Write-WarnZh "GitHub 授權驗證失敗"; $failed = $true }
elseif ($finalAuthState.state -eq 'insufficient_scope') {
    Write-WarnZh "GitHub 授權範圍不足（缺少：$($finalAuthState.missing_scopes -join ', ')）"
    $failed = $true
}
$helper = git config --global --get-regexp '^credential\..*\.helper$|^credential\.helper$' 2>$null
if (-not $helper) { Write-WarnZh "找不到 Git 憑證助手設定"; $failed = $true }
if ($failed) {
    Stop-Zh "部分檢查未通過。" "重新執行本程式；若仍失敗，將畫面中的黃色訊息提供給講師。" 'credential_helper'
}

Write-Host "`n所有必要設定皆已完成。" -ForegroundColor Green
Write-Host "Git：$(git --version)"
Write-Host "GitHub CLI：$(gh --version | Select-Object -First 1)"
Write-Host "Git 姓名：$(git config --global user.name)"
Write-Host "Git 信箱：$(git config --global user.email)"
& gh auth status --hostname github.com
Write-Host "`n請關閉並重新開啟終端機，之後即可進行課程的 git 與 gh 操作。"
Read-Host "按 Enter 結束"
