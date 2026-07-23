# macOS 課程開發環境一鍵安裝器指引

本指引說明如何使用 macOS 整合式一鍵安裝程式，快速建立、更新與檢查課程所需要的所有軟體工具鏈，並包含開發環境中文化設定。

## 快速安裝（建議）

請依照以下步驟操作：

1. 按 **Command + Space**，輸入 `Terminal` 並按 **Enter** 開啟終端機視窗。
2. 複製以下完整指令並貼至終端機中，再按 **Enter** 執行：

```bash
curl -fsSL https://raw.githubusercontent.com/drgarbage/ag-course-index/main/scripts/install-course-toolchain-macos.command | bash
```

3. 執行後將會開啟互動式選單：

```text
=========================================================
           反重力 AI 課程環境一鍵安裝程式 (macOS)
=========================================================
 1) 完整安裝 (全裝) - 安裝並設定 Git/GH、Node、Cloudflared、Docker、GUI、中文化
 2) 自訂安裝 (選特定標的安裝)
 3) 執行環境 Readiness Report 檢查
 4) 結束退出
=========================================================
```

## 功能說明

### 1. 完整安裝 (全裝)
自動依序執行以下安裝與設定：
- **Git & GitHub CLI**：下載並安裝，並自動引導 Git 提交身分設定與 GitHub 帳號登入授權（將調用 `install-git-gh-macos.command`）。
- **Node.js LTS**：安裝 Node.js 執行環境。
- **Cloudflare Tunnel (cloudflared)**：安裝內網穿透工具。
- **Docker Desktop**：安裝 Docker Desktop。
- **GUI 工具**：安裝 VS Code、Google Chrome 瀏覽器以及 Antigravity 開發工具。
- **繁體中文化**：自動為 VS Code、Antigravity IDE 部署繁體中文語言包，並安全注入 Antigravity 2.0 繁體中文漢化修補檔（具備 SHA-256 完整性校驗與執行確認）。

### 2. 自訂安裝
如果您只想安裝特定工具或中文化，請選擇編號 `2`。您可以輸入編號進行多選（以逗號或空格分隔，例如：`1,2,6`）：
1. Git 與 GitHub CLI
2. Node.js LTS
3. Cloudflare Tunnel
4. Docker Desktop
5. GUI 工具 (可細選全部或特定軟體)
6. 繁體中文化 (可細選 VS Code/IDE 語言包或 Antigravity 2.0 桌面漢化)

### 3. Readiness Report 檢查
直接對本機環境進行掃描，確認磁碟空間是否充足、各項工具是否已安裝完成並就緒。

---

## 關於繁體中文化

整合安裝器提供以下中文化支援：
1. **VS Code 開發環境中文化**：透過語言包擴充套件自動切換為繁體中文。
2. **Antigravity IDE 中文化**：對 Antigravity IDE (VS Code 分支) 安裝繁體中文擴充功能（提示：由於擴充來源限制，此項目狀態標記為「待驗證」）。
3. **Antigravity 2.0 桌面版中文化**：
   - 採用 **qqxpee/antigravity2-cn** 專案的實體 `app.asar` 注入修補技術。
   - **安全性防護**：本專案已將漢化補丁鎖定在特定的 Safe Commit 程式碼，並在執行前利用 SHA-256 對補丁檔案進行完整性檢查。
   - **確認閥門**：執行前系統會跳出警告訊息，請務必詳細閱讀並輸入 `y` 以確認授權修改。

---

[返回 README](../../README.md)
