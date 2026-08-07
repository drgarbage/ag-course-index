# Free Live Dev Orchestrator Skill (`free-live-dev`)

`free-live-dev` 是一個專門為 AI Agent 設計的自動化網頁開發與預覽部署協同 Skill。它整合了 `gh` CLI、Vercel、Firebase/Firestore，旨在為學員建立一個**無人值守的開發流水線**：Agent 從零建立雲端專案、透過友善表單收集憑證、接管 Git 分支切換、本機 Playwright 自動測試與程式碼 Bug 自我修復 (Self-healing)，並在部署後自動提供 Vercel Preview 公開預覽連結供學員測試。學員只需要「授權」「提需求」「填憑證」，完全不用碰本機開發環境或後端設定，100% 專注於產品功能本身！

## 🌟 核心特色
- **後端基礎建設自動化 (Backend Bootstrap)**：Agent 自動建立 GitHub repo、連結 Vercel 專案、建立 Firebase 專案與 Firestore 資料庫並部署鎖死的預設安全規則——學員不用打開任何一個雲端主控台。
- **友善憑證收集 (Credential Form)**：需要金鑰時，Agent 在本機開啟一個瀏覽器表單（`resources/credential-form.js`），學員照著提示填寫、送出即可；憑證只會寫入本機被 gitignore 的 `.env.local`，絕不會出現在對話紀錄或指令列裡。同步進 Vercel/GitHub 密鑰庫時一律透過 `resources/read-env-value.js` 讀值後直接 pipe 給對應 CLI，全程不經過 shell 字串展開——避免金鑰內容剛好含有 `$(...)`、反引號等字元時被當成指令執行。
- **無人值守測試與自癒 (Auto-healing)**：Agent 自動在本機運行 Playwright 驗證 UI 與功能，若測試失敗，Agent 會**主動修復程式碼直至通過**才允許 Push，無需學員參與 Debug。
- **預覽優先 (Preview First)**：徹底告別 `localhost` 偵錯，Agent 會輪詢 Vercel API 取得最新的公開預覽連結 (Preview URL) 呈報給學員，提供最佳的跨裝置與遠端測試體驗。
- **Git Flow 自動化 Lifecycle**：Agent 根據 Git Flow 標準自動切換 `feature/` 分支，進行 PR 並等待 CI 綠燈才合併至 `develop`；功能確認無誤後，主動詢問學員並自動 PR 至 `main`、標記語意化版本 Tag。
- **憑證安全護欄 (Security Guardrails)**：嚴格隔離 Preview 與 Production 金鑰，強制檢查 `.gitignore`、`gitleaks` 密鑰掃描。對不良 React 架構或測試憑證洩漏，主動提出安全對比報告進行警告防範。

---

## 📦 安裝教學

你可以透過 `skills` CLI 在你的專案中一鍵安裝此 Skill 套件。

### ⚡️ 快速一鍵安裝 (Recommended)
在你的專案根目錄下，開啟終端機並執行以下指令，即可一鍵將 `free-live-dev` 協調器、開發規範參考手冊與 Actions 範本部署至專案中：
```bash
npx skills add drgarbage/ag-course-index --skill free-live-dev
```
若你想全域安裝此規則（套用到所有專案的 Agent 中），只需加上 `-g` 參數：
```bash
npx skills add drgarbage/ag-course-index --skill free-live-dev -g
```

---

## 📂 檔案目錄結構與分工

本套件安裝後會於專案中部署以下檔案，維持高密度的語意防護與物理隔離：

1. **[SKILL.md](SKILL.md)**：主協調器提示詞。定義後端基礎建設自動建立、憑證收集流程、Git Flow 流程決策、環境初始化登入引導、測試-修復自癒迴圈與 Vercel 預覽連結輪詢。
2. **[references/react-firestore-rules.md](references/react-firestore-rules.md)**：開發規範手冊。專門指導 Agent 如何撰寫 React Context API、TailwindCSS 與進行 Firestore 安全存取，含 Firestore Emulator 的具體啟動與隔離設定。
3. **[references/playwright-qa-rules.md](references/playwright-qa-rules.md)**：QA 自動化手冊。指導 Agent 如何在本地啟動 headless 測試，並在失敗時自我修復 (Self-healing)。
4. **[resources/vercel-preview.yml](resources/vercel-preview.yml)**：CI/CD 範本。Agent 會主動將此範本複製至學員專案的 `.github/workflows/` 下，實現 GitHub Actions 與 Vercel 的自動化集成；Node 版本讀取專案的 `.nvmrc`，與本機開發環境保持一致；有 `firebase.json` 的專案會自動裝 Java 並用 Firestore Emulator 包住測試指令，跟本機的 QA Loop 走同一套隔離規則。
5. **[resources/credential-form.js](resources/credential-form.js)**：本機憑證收集表單。零額外依賴的 Node 腳本，只綁定 `127.0.0.1`，收到表單送出後直接寫入 `.env.local` 並自動關閉，過程中金鑰內容不會被印出或送出到本機以外的地方；重複送出同一個欄位會就地覆寫舊值，而不是悄悄忽略。
6. **[resources/read-env-value.js](resources/read-env-value.js)**：安全讀值工具。從 `.env.local` 取出單一金鑰值並印到 stdout，過程完全不經過 shell（不用 `source`／不用字串展開），避免金鑰內容含有 shell 特殊字元時被誤當成指令執行；也能還原手動貼上的多行原始 JSON。
7. **[resources/resolve-preview-url.js](resources/resolve-preview-url.js)**：Vercel Preview 連結輪詢工具。用 Node 而非 bash 迴圈實作重試邏輯，不依賴 `seq`／`[ -n ]`／`sleep` 這類只有 POSIX shell 才有的語法，在 Windows 上即使 Agent 的 Bash 工具背後接的不是 Git Bash 也能正常運作。

## 🪟 跨平台注意事項

`SKILL.md` 裡凡是「重試迴圈」「檔案解析」「憑證處理」這類有實質邏輯的部分，都刻意寫成 `resources/` 底下的 Node script，而不是 bash 控制流程——這樣不管 Agent 的 Bash 工具在 Windows 上實際接的是 Git Bash、WSL 還是別的東西，行為都一致。剩下少數還是純 bash 片段的地方（例如單純的 CLI 呼叫、`|` pipe），本來就是任何 shell 都通的語法，不受影響。
