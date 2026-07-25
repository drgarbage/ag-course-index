# Git 與 GitHub CLI：Windows 安裝指引

## 快速安裝（建議）

適用於 Windows 10／11。請依照以下步驟操作：

1. 按 **Windows 鍵 + R**，輸入 `powershell` 並按 **Enter**。
2. 在 PowerShell 貼上以下完整指令，再按 **Enter**：

```powershell
Invoke-RestMethod -Uri https://raw.githubusercontent.com/drgarbage/ag-course-index/main/scripts/install-git-gh-windows.ps1 | Invoke-Expression
```

3. 依中文提示輸入 Git 姓名與電子郵件；瀏覽器開啟後，登入自己的 GitHub 帳號並完成授權。
4. 回到 PowerShell，等待畫面顯示「所有必要設定皆已完成」。

## 下載後執行（備用）

1. 下載 [`install-git-gh-windows.ps1`](../../scripts/install-git-gh-windows.ps1) 與 [`install-git-gh-windows.cmd`](../../scripts/install-git-gh-windows.cmd)，並放在**同一個資料夾**。
2. **雙擊 `install-git-gh-windows.cmd`**。這個啟動檔會自動用單次繞過的方式執行指令碼，不會遇到「因為這個系統上已停用指令碼執行」的錯誤，也不會變更你的系統設定。
3. 依中文提示輸入 Git 姓名與信箱，並在瀏覽器完成 GitHub 授權。
4. 看到「所有必要設定皆已完成」後，關閉並重新開啟終端機。

若你想直接執行 `.ps1`（右鍵「使用 PowerShell 執行」）而看到錯誤，請改用上面的 `.cmd`，或在 PowerShell 執行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-git-gh-windows.ps1
```

## 指令碼被系統阻擋時

Windows 預設的指令碼執行政策（ExecutionPolicy）是 `Restricted`，直接執行 `.ps1` 會出現「因為這個系統上已停用指令碼執行」。本安裝程式已能在啟動時自動處理，但若你想手動一次解決，可執行：

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

`-Scope CurrentUser` 只影響目前登入的帳號，不需要系統管理員權限。

另外，從瀏覽器下載的檔案會被標記為「來自其他電腦」，即使政策已是 `RemoteSigned` 仍可能被封鎖。安裝程式會自動解除封鎖；若要手動處理：

```powershell
Unblock-File .\install-git-gh-windows.ps1
```

若執行 `Set-ExecutionPolicy` 出現「因為此電腦上的原則設定而無法變更」，表示政策由單位的群組原則鎖定，個人帳號改不動 — 請改用 `.cmd` 啟動檔，並把畫面提供給講師。

> `Invoke-RestMethod ... | Invoke-Expression` 會下載並立即執行腳本。請只使用本專案提供的 `raw.githubusercontent.com/drgarbage/ag-course-index` 網址。

若 PowerShell 顯示「無法辨識 `Invoke-RestMethod`」，代表 PowerShell 過舊或被單位政策停用，請改用下方「下載後執行」方式，並將錯誤畫面提供給講師。

## 程式會處理的常見狀況

- 指令碼執行政策被停用：自動為目前帳號套用 `RemoteSigned`；若被群組原則鎖定則改為提示用 `.cmd` 啟動。
- 下載檔案被標記封鎖：自動執行 `Unblock-File`。
- 已安裝 Git 或 `gh`：保留現有安裝並繼續設定。
- 找不到 WinGet：提供 Microsoft App Installer 的修復方向。
- 安裝後 PATH 尚未更新：自動重新載入 PATH。
- **登入前先檢查前置條件**：連不到 github.com 時直接說明是網路問題，不會讓你白等瀏覽器授權逾時。
- GitHub 憑證失效：引導重新登入，並在失敗時顯示可直接複製貼上的 `gh auth login` 指令。
- **已登入但授權範圍不足**：自動執行 `gh auth refresh` 補齊 `repo`、`read:org`、`workflow`。
- Git 未使用 `gh` 憑證：執行 `gh auth setup-git` 修復。
- 同時存在多個 GitHub 帳號：顯示目前使用中的帳號，讓學員確認。
- Windows 260 字元路徑上限：設定 `core.longpaths true`。

## 手動檢查

```powershell
git --version
gh --version
gh auth status
git config --global user.name
git config --global user.email
git config --global --get-regexp '^credential\..*\.helper$|^credential\.helper$'
```

[返回平台選擇](git-and-gh.md) · [返回 README](../../README.md)
