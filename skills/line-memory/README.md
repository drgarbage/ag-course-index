# LINE 對話記憶規劃師 Skill (`line-memory`)

`line-memory` 是一個為 AI Agent (例如 Antigravity) 設計的對話記憶與歷史管理設計輔助 Skill。它旨在協助 Agent 為 LINE 機器人規劃「該記住什麼、記多久、怎麼記」，在「AI 記得上下文」與「不浪費 Token」之間取得完美平衡，避免每次呼叫 LLM 時因塞入大量原始對話歷史而導致費用暴增或超出 Context 限制。

## 🌟 核心特色
- **三階段記憶策略導航**：
  1. **滑動視窗 (Sliding Window)**：維持近期 4~8 輪的短期記憶。
  2. **摘要記憶 (Rolling Summary)**：在長對話 (超過 10 輪) 中，將舊對話滾動壓縮成摘要併入上下文。
  3. **向量記憶 (Embedding Memory)**：跨 Session 儲存使用者長期事實與偏好（支援 cosine similarity 相似度搜尋）。
- **極簡記憶架構實作**：內含摘要滾動壓縮、輕量級向量轉化與 cosine similarity 計算底層實作邏輯，指導 Agent 避免過度設計，使用最輕量的 JSON 陣列或記憶體儲存來實現長期偏好記住。
- **智慧儲存決策**：引導 Agent 主動判斷是否值得存成長期記憶，避免將使用者的無意義對話全部寫入資料庫。

---

## 📦 安裝教學

你可以透過 `skills` CLI 在你的專案中一鍵安裝此 Skill。

### ⚡️ 快速一鍵安裝 (Recommended)
在你的專案根目錄下，開啟終端機並執行以下指令：
```bash
npx skills add drgarbage/ag-course-index --skill line-memory
```
若你想全域安裝此規則（套用到所有專案的 Agent 中），只需加上 `-g` 參數：
```bash
npx skills add drgarbage/ag-course-index --skill line-memory -g
```

---

### 🛠️ 手動安裝 (備用方案)
如果你的環境無法使用 CLI，也可以將本目錄下的 [SKILL.md](SKILL.md) 檔案下載並手動放置到你專案根目錄的 `.agents/skills/line-memory/` 下即可。
