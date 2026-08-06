# LINE 互動流程規劃師 Skill (`line-interact-planner`)

`line-interact-planner` 是一個為 AI Agent (例如 Antigravity) 設計的 LINE 機器人對話架構規劃輔助 Skill。它的核心任務是幫整個機器人「節省 Token、減少呼叫次數」，主動將重複、固定且決定性的流程（如 `/說明`、`/help` 等）從原本昂貴的對話式 AI 迴圈中抽離，並「升級」成直接由程式處理的文字指令分流（完全不經過 LLM），使 Agent 與專案運作更有效率。

## 🌟 核心特色
- **省 Token 智慧決策**：自動評估使用者功能的「高頻度、決定性與參數複雜度」，自動在「交給 Gemini 的開放式對話」與「由程式處理的快速指令」之間做好取捨。
- **極簡指令分流實作**：內含在 `server.js` 或 webhook dispatch 入口處進行文字前綴（如 `startsWith('/')`）與白名單過濾的標準實作範例，防範 Agent 每次功能都使用 Function Calling 造成 Token 暴漲與反應遲鈍。
- **引導式互動設計**：指示 Agent 在 Gemini 自然語言回覆結尾，適當插入關聯指令的 Quick Reply，培養使用者以點擊按鈕直接觸發指令的習慣。

---

## 📦 安裝教學

你可以透過 `skills` CLI 在你的專案中一鍵安裝此 Skill。

### ⚡️ 快速一鍵安裝 (Recommended)
在你的專案根目錄下，開啟終端機並執行以下指令：
```bash
npx skills add https://github.com/drgarbage/ag-course-index --skill line-interact-planner
```
若你想全域安裝此規則（套用到所有專案的 Agent 中），只需加上 `-g` 參數：
```bash
npx skills add https://github.com/drgarbage/ag-course-index --skill line-interact-planner -g
```

---

### 🛠️ 手動安裝 (備用方案)
如果你的環境無法使用 CLI，也可以將本目錄下的 [SKILL.md](SKILL.md) 檔案下載並手動放置到你專案根目錄的 `.agents/skills/line-interact-planner/` 下即可。
