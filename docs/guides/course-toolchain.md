# 課程工具鏈一鍵安裝指引

安裝程式會依你選擇的 profile，檢查並安裝課程需要的系統工具，最後印出就緒報告：

- `base`：Git／GitHub CLI、Node.js LTS（含 npm）— 適用 Class 01–04、07、09–12
- `line`：`base` + Cloudflare Tunnel（`cloudflared`）— 適用 Class 05–06（LINE Webhook）
- `data`：`base` + Docker Desktop（含 Compose v2）— 適用 Class 08
- `full`：`base` + `cloudflared` + Docker Desktop — 全課程都要用時選這個

執行時會逐一詢問是否安裝每個工具，你可以個別同意或跳過；也可以額外選擇安裝 Antigravity、VS Code、Chrome 等 GUI 工具。

> **請先完成 Git／GitHub 帳號設定**：安裝程式只會「偵測」Git 與 GitHub CLI 是否就緒，不會重複安裝。若尚未設定，請先執行下方的 [Git 與 GitHub CLI 一鍵安裝](git-and-gh.md)，再回來執行本安裝程式。

請依你的作業系統選擇一行指令：

## Windows

1. 同時按 **Windows 鍵 + R**。
2. 輸入 `powershell`，按 **Enter**。
3. 在藍色 PowerShell 視窗貼上以下完整指令，再按 **Enter**：

```powershell
Invoke-RestMethod -Uri https://raw.githubusercontent.com/drgarbage/ag-course-index/main/scripts/course-toolchain-windows.ps1 | Invoke-Expression
```

4. 依畫面提示輸入 profile（`base`／`line`／`data`／`full`），再逐項確認要安裝的工具。

## macOS

開啟「終端機」，貼上以下完整指令並按 Enter：

```bash
installer_file="$(mktemp)" && curl -fsSL https://raw.githubusercontent.com/drgarbage/ag-course-index/main/scripts/course-toolchain-macos.command -o "$installer_file" && bash "$installer_file"; rm -f "$installer_file"
```

## 注意事項

- **Docker Desktop**：`data`／`full` profile 需要至少 13 GB 可用磁碟空間；安裝報告會標示磁碟空間是否足夠。
- **Windows + Docker**：若電腦尚未啟用 WSL 2，安裝程式會先說明「需要重新開機」的影響並取得你的確認，不會自動強制重開機；重開機後請重新執行本安裝程式完成 Docker 安裝。
- **Cloudflare Tunnel**：只會安裝並驗證 `cloudflared` 指令本身，不會登入 Cloudflare 帳號、不會建立 named tunnel 或背景服務。上課用的臨時 Webhook URL 由課程範例程式在執行時另外產生。
- 安裝完成後會印出「課程就緒報告」，列出每個工具的版本與狀態；若有工具顯示 `failed`，畫面會提示是否要使用 AI 安裝助理協助排錯，或聯絡講師。
- 安裝程式不會讀取或傳送你的密碼、Token、SSH key 或 `.env` 內容。
- 請只從本專案 README 複製指令；不要執行別人傳來、來源不明的遠端腳本指令。

[返回 README](../../README.md)
