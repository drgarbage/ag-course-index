[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Host.UI.RawUI.WindowTitle = "Git 與 GitHub CLI 課程環境安裝程式"

function Write-Step([string]$Message) { Write-Host "`n▶ $Message" -ForegroundColor Cyan }
function Write-Ok([string]$Message) { Write-Host "  ✓ $Message" -ForegroundColor Green }
function Write-WarnZh([string]$Message) { Write-Host "  ! $Message" -ForegroundColor Yellow }
function Stop-Zh([string]$Message, [string]$Suggestion) {
    Write-Host "`n安裝未完成：$Message" -ForegroundColor Red
    Write-Host "建議處理方式：$Suggestion" -ForegroundColor Yellow
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

Write-Host "Git 與 GitHub CLI 課程環境安裝程式" -ForegroundColor White
Write-Host "程式只會安裝官方套件、設定 Git，並開啟 GitHub 官方登入頁。"

Write-Step "檢查 WinGet"
if (-not (Has-Command "winget")) {
    Stop-Zh "找不到 WinGet。" "開啟 Microsoft Store，安裝或更新『應用程式安裝程式（App Installer）』，重新開機後再執行本程式。"
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
        Stop-Zh "Git 安裝失敗：$($_.Exception.Message)" "確認網路連線、Windows Update 與 Microsoft Store 可用，再以系統管理員身分重新執行。"
    }
    Refresh-Path
    if (-not (Has-Command "git")) {
        Stop-Zh "Git 已執行安裝，但目前終端機仍找不到 git。" "關閉所有 PowerShell／Windows Terminal 視窗，重新開啟後再執行本程式。"
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
        Stop-Zh "GitHub CLI 安裝失敗：$($_.Exception.Message)" "確認網路連線後重新執行；也可從 https://cli.github.com/ 手動安裝。"
    }
    Refresh-Path
    if (-not (Has-Command "gh")) {
        Stop-Zh "GitHub CLI 已執行安裝，但目前終端機仍找不到 gh。" "關閉所有 PowerShell／Windows Terminal 視窗，重新開啟後再執行本程式。"
    }
    Write-Ok "安裝完成：$(gh --version | Select-Object -First 1)"
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
Write-Ok "Git 身分與預設分支已設定"

Write-Step "檢查 GitHub 登入"
& gh auth status --hostname github.com *> $null
if ($LASTEXITCODE -ne 0) {
    Write-WarnZh "尚未登入、授權已失效，或舊憑證無法使用。接下來會開啟 GitHub 官方網頁。"
    Write-Host "  請登入正確帳號並完成裝置授權；完成前不要關閉這個視窗。"
    & gh auth login --hostname github.com --git-protocol https --web
    if ($LASTEXITCODE -ne 0) {
        Stop-Zh "GitHub 網頁登入未完成。" "確認瀏覽器已完成授權，再重新執行本程式。若有多個帳號，先執行 gh auth switch。"
    }
} else {
    Write-Ok "GitHub CLI 已登入"
    & gh auth status --hostname github.com
}

Write-Step "讓 Git 使用 GitHub CLI 保存 HTTPS 憑證"
& gh config set git_protocol https --host github.com
& gh auth setup-git --hostname github.com
if ($LASTEXITCODE -ne 0) {
    Stop-Zh "無法設定 Git credential helper。" "執行 gh auth status 確認登入，再執行 gh auth setup-git。若仍失敗，檢查 Windows 認證管理員中的舊 GitHub 項目。"
}
Write-Ok "Git 不應再於每次 pull／push 時重複要求登入"

Write-Step "最終驗證"
$failed = $false
if (-not (Has-Command "git")) { Write-WarnZh "找不到 Git"; $failed = $true }
if (-not (Has-Command "gh")) { Write-WarnZh "找不到 GitHub CLI"; $failed = $true }
& gh auth status --hostname github.com *> $null
if ($LASTEXITCODE -ne 0) { Write-WarnZh "GitHub 授權驗證失敗"; $failed = $true }
$helper = git config --global --get-regexp '^credential\..*\.helper$|^credential\.helper$' 2>$null
if (-not $helper) { Write-WarnZh "找不到 Git 憑證助手設定"; $failed = $true }
if ($failed) {
    Stop-Zh "部分檢查未通過。" "重新執行本程式；若仍失敗，將畫面中的黃色訊息提供給講師。"
}

Write-Host "`n所有必要設定皆已完成。" -ForegroundColor Green
Write-Host "Git：$(git --version)"
Write-Host "GitHub CLI：$(gh --version | Select-Object -First 1)"
Write-Host "Git 姓名：$(git config --global user.name)"
Write-Host "Git 信箱：$(git config --global user.email)"
& gh auth status --hostname github.com
Write-Host "`n請關閉並重新開啟終端機，之後即可進行課程的 git 與 gh 操作。"
Read-Host "按 Enter 結束"
