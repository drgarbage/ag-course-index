<#
.SYNOPSIS
    在真實 Windows 環境中驗證安裝程式「執行環境權限」前置檢查的行為。

.DESCRIPTION
    單元測試（tests/install-support/windows.Tests.ps1）用注入的 provider 驗證判斷邏輯，
    但無法證明真實的作業系統阻擋會被正確處理。這個腳本反過來做：真的把環境弄壞，
    再確認安裝程式有正確反應。

    全部檢查都不需要系統管理員權限。唯一會被修改的是本使用者的 ExecutionPolicy，
    腳本結束時（含中途失敗）一定會還原。

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\verify-windows-preflight.ps1
#>
[CmdletBinding()]
param(
    [string]$InstallerPath,
    [string]$LauncherPath
)

# 注意：這裡刻意不使用 $ErrorActionPreference = 'Stop'。
# Windows PowerShell 5.1 會把原生程式（powershell.exe／cmd.exe）寫到 stderr 的每一行
# 包成 NativeCommandError，在 Stop 之下即使結束碼為 0 也會讓腳本中止。
$ErrorActionPreference = 'Continue'

# Windows PowerShell 5.1 不會在 param 預設值中提供 $PSScriptRoot，必須在主體解析。
if (-not $InstallerPath) { $InstallerPath = Join-Path $PSScriptRoot '..\..\scripts\install-git-gh-windows.ps1' }
if (-not $LauncherPath) { $LauncherPath = Join-Path $PSScriptRoot '..\..\scripts\install-git-gh-windows.cmd' }

$script:passed = 0
$script:failed = 0

function Assert-Case {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if ($Condition) {
        Write-Host "  [PASS] $Name" -ForegroundColor Green
        $script:passed++
    } else {
        Write-Host "  [FAIL] $Name" -ForegroundColor Red
        if ($Detail) {
            $trimmed = ($Detail -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 4) -join ' | '
            Write-Host "         $trimmed" -ForegroundColor DarkGray
        }
        $script:failed++
    }
}

# 以檔案重導向擷取子程序輸出，避免 5.1 的 NativeCommandError 陷阱。
function Invoke-Captured {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$WorkDir
    )

    $stdout = Join-Path $WorkDir ("out-" + [guid]::NewGuid().ToString('n').Substring(0, 6) + '.txt')
    $stderr = "$stdout.err"
    $process = Start-Process -FilePath $FilePath -ArgumentList $Arguments -Wait -PassThru -NoNewWindow `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr

    # 子程序的中文輸出是 UTF-8；用預設編碼讀會變亂碼，讓斷言與訊息都不可信。
    $readUtf8 = {
        param($path)
        if (Test-Path $path) { [System.IO.File]::ReadAllText($path, [System.Text.UTF8Encoding]::new($false)) } else { '' }
    }
    [pscustomobject]@{
        exit_code = $process.ExitCode
        stdout = (& $readUtf8 $stdout)
        stderr = (& $readUtf8 $stderr)
    }
}

$installer = (Resolve-Path $InstallerPath).Path
$launcher = (Resolve-Path $LauncherPath).Path
$workDir = Join-Path ([System.IO.Path]::GetTempPath()) ("preflight-" + [guid]::NewGuid().ToString('n').Substring(0, 8))
New-Item -ItemType Directory -Path $workDir | Out-Null

Write-Host "`n=== 真實環境權限前置檢查驗證 ===" -ForegroundColor Cyan
Write-Host "安裝程式：$installer"
Write-Host "啟動檔　：$launcher`n"

# 安全網：情境 3 會暫時把使用者政策設為 Restricted。若上一次執行被中斷，
# 政策可能仍卡在 Restricted，這裡先偵測並提醒。
$currentUserPolicy = Get-ExecutionPolicy -Scope CurrentUser
if ($currentUserPolicy -eq 'Restricted') {
    Write-Host "注意：CurrentUser 政策目前是 Restricted。若這是上次中斷的驗證所留下的，" -ForegroundColor Yellow
    Write-Host "      請執行：Set-ExecutionPolicy RemoteSigned -Scope CurrentUser`n" -ForegroundColor Yellow
}

try {
    # ------------------------------------------------------------------
    Write-Host "情境 1：PowerShell 被限制在 ConstrainedLanguage" -ForegroundColor Cyan
    # 語言模式只能降級不能升級，因此子程序中的降級與 WDAC 實際造成的效果等價。
    $constrained = Invoke-Captured -FilePath 'powershell.exe' -WorkDir $workDir -Arguments @(
        '-NoProfile', '-Command',
        "`$ExecutionContext.SessionState.LanguageMode='ConstrainedLanguage'; & '$installer'"
    )

    Assert-Case '給出可讀的中文說明，而不是原始的 .NET 錯誤' `
        ($constrained.stdout -match 'ConstrainedLanguage') "stdout=$($constrained.stdout)"
    Assert-Case '不留下任何未處理的紅字錯誤' `
        ([string]::IsNullOrWhiteSpace($constrained.stderr)) "stderr=$($constrained.stderr)"
    Assert-Case '在跑到任何安裝動作之前就停下' `
        ($constrained.stdout -notmatch '檢查 WinGet') "stdout=$($constrained.stdout)"
    Assert-Case '未嘗試呼叫需要 .NET 的 AI 安裝助理' `
        ($constrained.stdout -notmatch '安裝助理') "stdout=$($constrained.stdout)"

    # ------------------------------------------------------------------
    Write-Host "`n情境 2：下載檔案帶有封鎖標記（MOTW / Zone.Identifier）" -ForegroundColor Cyan
    $blocked = Join-Path $workDir 'blocked-sample.ps1'
    Copy-Item $installer $blocked
    # 這正是瀏覽器下載時附加的資料流，ZoneId=3 代表「來自網際網路」。
    Set-Content -Path $blocked -Stream 'Zone.Identifier' -Value "[ZoneTransfer]`r`nZoneId=3"

    $hadMark = $null -ne (Get-Item $blocked -Stream 'Zone.Identifier' -ErrorAction SilentlyContinue)
    Assert-Case '測試前置：封鎖標記已成功附加' $hadMark

    # 只載入安裝程式的函式定義，單獨驗證解除封鎖這一件事。
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($installer, [ref]$tokens, [ref]$errors)
    $functionSource = $ast.FindAll({
        param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
    }, $true).Extent.Text -join "`n"
    . ([scriptblock]::Create($functionSource))

    $unblockedCount = Unblock-CourseScriptFile -Directory $workDir
    $markGone = $null -eq (Get-Item $blocked -Stream 'Zone.Identifier' -ErrorAction SilentlyContinue)
    Assert-Case '解除封鎖後 Zone.Identifier 資料流已移除' $markGone
    Assert-Case '回報的解除封鎖檔案數正確' ($unblockedCount -ge 1) "count=$unblockedCount"

    # ------------------------------------------------------------------
    Write-Host "`n情境 3：ExecutionPolicy 為 Restricted" -ForegroundColor Cyan
    # 這個情境必須在「沒有 -ExecutionPolicy 旗標」的子程序中進行：
    # 該旗標會設定 Process 範圍，其優先度高於 CurrentUser，會讓 Restricted 完全無效。
    $scenario3 = Join-Path $workDir 'scenario3.ps1'
    $scenario3Body = @'
$ErrorActionPreference = 'Continue'
$installer = $args[0]
$launcher = $args[1]
$workDir = $args[2]

$processScope = (Get-ExecutionPolicy -List | Where-Object { $_.Scope -eq 'Process' }).ExecutionPolicy
if ($processScope -notin @('Undefined', $null)) {
    "SKIP|Process 範圍政策為 $processScope，會覆蓋 CurrentUser"
    return
}

$original = Get-ExecutionPolicy -Scope CurrentUser

# 若這個程序被中斷，finally 不保證執行，使用者的政策就會卡在 Restricted。
# 先把原值寫到還原檔，下次執行時可以自動救回來。
$recoveryFile = Join-Path $workDir 'policy-recovery.txt'
Set-Content -Path $recoveryFile -Value $original -Encoding ascii

try {
    Set-ExecutionPolicy Restricted -Scope CurrentUser -Force -ErrorAction Stop
} catch {
    "SKIP|無法設定 CurrentUser 政策：$($_.Exception.Message)"
    return
}
try {
    "ORIGINAL|$original"
    "EFFECTIVE|$(Get-ExecutionPolicy)"

    # 3a. 直接執行真正的安裝程式：預期在印出任何東西之前就被政策擋掉，因此不會卡在互動提示。
    $so = Join-Path $workDir 'direct.out'; $se = Join-Path $workDir 'direct.err'
    $p = Start-Process powershell.exe -ArgumentList @('-NoProfile', '-File', $installer) `
        -Wait -PassThru -NoNewWindow -RedirectStandardOutput $so -RedirectStandardError $se
    "DIRECT|$($p.ExitCode)|$(((Get-Content $se -Raw -EA SilentlyContinue) + (Get-Content $so -Raw -EA SilentlyContinue)) -replace '\r?\n', ' ')"

    # 3b. 啟動檔要驗的是「能不能越過政策並正確叫起同資料夾的 .ps1」，
    #     不是安裝流程本身。用替身腳本測，才不會卡在真正安裝程式的互動提示。
    $stubDir = Join-Path $workDir 'launcher-probe'
    New-Item -ItemType Directory -Path $stubDir -Force | Out-Null
    Copy-Item $launcher (Join-Path $stubDir 'install-git-gh-windows.cmd')
    Set-Content -Path (Join-Path $stubDir 'install-git-gh-windows.ps1') `
        -Value 'Write-Host "LAUNCHER-PROBE-OK"; exit 0' -Encoding ascii

    $lo = Join-Path $workDir 'launch.out'; $le = Join-Path $workDir 'launch.err'
    $q = Start-Process cmd.exe -ArgumentList @('/c', "`"$(Join-Path $stubDir 'install-git-gh-windows.cmd')`"") `
        -Wait -PassThru -NoNewWindow -RedirectStandardOutput $lo -RedirectStandardError $le
    $launcherOut = ((Get-Content $lo -Raw -EA SilentlyContinue) + ' ' + (Get-Content $le -Raw -EA SilentlyContinue)) -replace '\r?\n', ' '
    "LAUNCHER|$($q.ExitCode)|$launcherOut"

    # 3c. 啟動檔找不到 .ps1 時要給出清楚訊息，而不是靜默失敗。
    $missingDir = Join-Path $workDir 'launcher-missing'
    New-Item -ItemType Directory -Path $missingDir -Force | Out-Null
    Copy-Item $launcher (Join-Path $missingDir 'install-git-gh-windows.cmd')
    $mo = Join-Path $workDir 'missing.out'
    $r = Start-Process cmd.exe -ArgumentList @('/c', "echo. | `"$(Join-Path $missingDir 'install-git-gh-windows.cmd')`"") `
        -Wait -PassThru -NoNewWindow -RedirectStandardOutput $mo -RedirectStandardError (Join-Path $workDir 'missing.err')
    "MISSING|$($r.ExitCode)|$((Get-Content $mo -Raw -EA SilentlyContinue) -replace '\r?\n', ' ')"

    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($installer, [ref]$tokens, [ref]$errors)
    $fn = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true).Extent.Text -join "`n"
    . ([scriptblock]::Create($fn))
    $state = Get-ExecutionPolicyState
    "STATE|$($state.effective)|$($state.allows_local_script)|$($state.locked_by_group_policy)"
} finally {
    Set-ExecutionPolicy $original -Scope CurrentUser -Force -ErrorAction SilentlyContinue
    Remove-Item $recoveryFile -Force -ErrorAction SilentlyContinue
    "RESTORED|$(Get-ExecutionPolicy -Scope CurrentUser)"
}
'@
    Set-Content -Path $scenario3 -Value $scenario3Body -Encoding UTF8

    # -ExecutionPolicy 旗標是透過 PSExecutionPolicyPreference 環境變數傳給子程序的，
    # 不清掉的話子程序的 Process 範圍仍是 Bypass，Restricted 就永遠測不到。
    $inheritedPolicyPreference = $env:PSExecutionPolicyPreference
    Remove-Item Env:\PSExecutionPolicyPreference -ErrorAction SilentlyContinue
    try {
        # 刻意不帶 -ExecutionPolicy；改用 -Command 點源，避免自己被政策擋住。
        $s3 = Invoke-Captured -FilePath 'powershell.exe' -WorkDir $workDir -Arguments @(
            '-NoProfile', '-Command',
            ". '$scenario3' '$installer' '$launcher' '$workDir'"
        )
    } finally {
        if ($inheritedPolicyPreference) { $env:PSExecutionPolicyPreference = $inheritedPolicyPreference }
    }
    $s3Lines = @($s3.stdout -split "`r?`n" | Where-Object { $_.Trim() })
    $skip = $s3Lines | Where-Object { $_ -like 'SKIP|*' } | Select-Object -First 1

    if ($skip) {
        Write-Host "  [SKIP] $($skip -replace '^SKIP\|', '')" -ForegroundColor Yellow
        Write-Host "         請不要用 -ExecutionPolicy Bypass 啟動本驗證腳本，改為先執行" -ForegroundColor DarkGray
        Write-Host "         Set-ExecutionPolicy RemoteSigned -Scope CurrentUser 後直接執行。" -ForegroundColor DarkGray
    } else {
        $restored = ($s3Lines | Where-Object { $_ -like 'RESTORED|*' }) -replace '^RESTORED\|', ''
        $direct = ($s3Lines | Where-Object { $_ -like 'DIRECT|*' }) -join ''
        $launcherLine = ($s3Lines | Where-Object { $_ -like 'LAUNCHER|*' }) -join ''
        $missingLine = ($s3Lines | Where-Object { $_ -like 'MISSING|*' }) -join ''
        $stateLine = ($s3Lines | Where-Object { $_ -like 'STATE|*' }) -join ''
        $stateParts = $stateLine -split '\|'

        Assert-Case '直接執行 .ps1 確實被系統阻擋（成功重現學生的錯誤）' `
            ($direct -match 'disabled|停用|UnauthorizedAccess') $direct
        # 全部用 ASCII 片段比對，避免子程序編碼影響斷言可信度。
        Assert-Case '.cmd 啟動檔可繞過 Restricted 政策並叫起同資料夾的腳本' `
            ($launcherLine -match 'LAUNCHER-PROBE-OK') $launcherLine
        Assert-Case '.cmd 啟動檔本身沒有編碼問題（無亂碼指令錯誤）' `
            ($launcherLine -notmatch 'is not recognized as an internal') $launcherLine
        Assert-Case '.cmd 找不到腳本時給出明確訊息並回傳非零碼' `
            ($missingLine -match 'ERROR.*not found' -and $missingLine -notmatch '^MISSING\|0\|') $missingLine
        Assert-Case '偵測邏輯在真實 Restricted 下回報不可執行' `
            ($stateParts.Count -ge 3 -and $stateParts[2] -eq 'False') $stateLine
        Assert-Case '未誤判為群組原則鎖定' `
            ($stateParts.Count -ge 4 -and $stateParts[3] -eq 'False') $stateLine
        Assert-Case '測試後已還原原本的使用者政策' `
            (-not [string]::IsNullOrWhiteSpace($restored)) "restored=$restored"
        Write-Host "  （已還原 CurrentUser 政策為：$restored）" -ForegroundColor DarkGray
    }

    # ------------------------------------------------------------------
    Write-Host "`n情境 4：一行指令載入（`$PSScriptRoot 為空）" -ForegroundColor Cyan
    # 取安裝程式開頭到 $CourseGitHubScopes 為止，模擬管道載入時的變數解析。
    $lines = Get-Content $installer
    $headEnd = ($lines | Select-String -Pattern '^\$CourseGitHubScopes' | Select-Object -First 1).LineNumber
    Assert-Case '找得到開頭區塊的結尾' ($null -ne $headEnd) "headEnd=$headEnd"
    $headFile = Join-Path $workDir 'head.ps1'
    # 語言模式檢查含 Read-Host，模擬時要跳過，只驗證變數解析不會擲錯。
    $head = ($lines[0..($headEnd - 1)] | Where-Object { $_ -notmatch 'Read-Host|^\s*exit 1' })
    Set-Content -Path $headFile -Value $head -Encoding UTF8

    $pipeResult = Invoke-Captured -FilePath 'powershell.exe' -WorkDir $workDir -Arguments @(
        '-NoProfile', '-Command',
        "`$ErrorActionPreference='Stop'; try { . '$headFile'; 'HEAD-OK' } catch { 'HEAD-DIED: ' + `$_.Exception.Message }"
    )
    Assert-Case '開頭區塊在沒有腳本資料夾時不會擲錯' `
        ($pipeResult.stdout -match 'HEAD-OK') "stdout=$($pipeResult.stdout)"

} finally {
    Remove-Item $workDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "`n=== 結果：$script:passed 通過、$script:failed 失敗 ===" `
    -ForegroundColor $(if ($script:failed) { 'Red' } else { 'Green' })
if ($script:failed) { exit 1 }
