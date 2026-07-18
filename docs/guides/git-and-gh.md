# Git 與 GitHub CLI 一鍵安裝指引

安裝程式會協助你安裝並完成以下設定：

- Git 與 GitHub CLI（`gh`）
- Git 提交使用的姓名與電子郵件
- GitHub 瀏覽器登入
- HTTPS Git 憑證保存，避免每次 `pull` 或 `push` 都重新登入
- 預設分支名稱 `main`
- 安裝及授權狀態驗證

請依你的作業系統選擇指引：

- [Windows 安裝指引](git-and-gh-windows.md)
- [macOS 安裝指引](git-and-gh-macos.md)

## 一行指令快速安裝

### Windows

1. 同時按 **Windows 鍵 + R**。
2. 輸入 `powershell`，按 **Enter**。
3. 在藍色 PowerShell 視窗貼上以下完整指令，再按 **Enter**：

```powershell
Invoke-RestMethod -Uri https://raw.githubusercontent.com/drgarbage/ag-course-index/main/scripts/install-git-gh-windows.ps1 | Invoke-Expression
```

### macOS

開啟「終端機」，貼上以下完整指令並按 Enter：

```bash
installer_file="$(mktemp)" && curl -fsSL https://raw.githubusercontent.com/drgarbage/ag-course-index/main/scripts/install-git-gh-macos.command -o "$installer_file" && bash "$installer_file"; rm -f "$installer_file"
```

> GitHub 登入必須由本人在瀏覽器授權。程式不會讀取、顯示或保存你的密碼。
> 請只從本專案 README 複製指令；不要執行別人傳來、來源不明的遠端腳本指令。

[返回 README](../../README.md)
