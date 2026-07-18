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

1. 下載 [`install-git-gh-windows.ps1`](../../scripts/install-git-gh-windows.ps1)。
2. 對下載檔按右鍵，選擇「使用 PowerShell 執行」。
3. 若系統不允許執行，開啟 PowerShell，切換到下載資料夾後執行：

```powershell
powershell -ExecutionPolicy Bypass -File .\install-git-gh-windows.ps1
```

4. 依中文提示輸入 Git 姓名與信箱，並在瀏覽器完成 GitHub 授權。
5. 看到「所有必要設定皆已完成」後，關閉並重新開啟終端機。

> `Invoke-RestMethod ... | Invoke-Expression` 會下載並立即執行腳本。請只使用本專案提供的 `raw.githubusercontent.com/drgarbage/ag-course-index` 網址。

若 PowerShell 顯示「無法辨識 `Invoke-RestMethod`」，代表 PowerShell 過舊或被單位政策停用，請改用下方「下載後執行」方式，並將錯誤畫面提供給講師。

## 程式會處理的常見狀況

- 已安裝 Git 或 `gh`：保留現有安裝並繼續設定。
- 找不到 WinGet：提供 Microsoft App Installer 的修復方向。
- 安裝後 PATH 尚未更新：自動重新載入 PATH。
- GitHub 憑證失效：引導重新登入。
- Git 未使用 `gh` 憑證：執行 `gh auth setup-git` 修復。
- 同時存在多個 GitHub 帳號：顯示目前使用中的帳號，讓學員確認。

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
