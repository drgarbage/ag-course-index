# LINE 視覺呈現設計師 Skill (`line-ui-designer`)

`line-ui-designer` 是一個為 AI Agent (例如 Antigravity) 設計的 LINE 機器人視覺回覆設計輔助 Skill。它的核心任務是幫已經算好或查到的結構化資訊尋找最適合的 LINE 訊息呈現格式（如純文字、Flex 卡片 Bubble、Flex 輪播 Carousel、Buttons 樣板、Confirm 樣板、Quick Reply 等），避免機器人所有的回覆都流於冗長、死板的純文字，顯著提升 LINE 使用者體驗。

## 🌟 核心特色
- **資料形狀智慧映射**：
  * **單一實體（如一筆訂單/待辦）**：自動映射為 Flex 卡片（Bubble）。
  * **多筆實體（如商品清單）**：自動映射為 Flex 左右滑動輪播（Carousel，最多 10 張）。
  * **少量選項或破壞操作**：自動映射為 Buttons 樣板或 Confirm 確認樣板（是/否）。
- **Flex 卡片防禦性實作**：內含防止 Flex 卡片欄位輸出空字串（空字串會導致 LINE API 400 錯誤）的自檢機制、`altText` 預覽字串要求，以及單次 reply/push 訊息上限限制。
- **UI 封裝與風格一致性**：約束 Agent 必須重用與延伸專案內建的 `lib/lineMessages.js` 元件庫（使用如 `BRAND`、`MUTED` 等標準配色），避免代碼風格紊亂。

---

## 📦 安裝教學

你可以透過 `skills` CLI 在你的專案中一鍵安裝此 Skill。

### ⚡️ 快速一鍵安裝 (Recommended)
在你的專案根目錄下，開啟終端機並執行以下指令：
```bash
npx skills add https://github.com/drgarbage/ag-course-index --skill line-ui-designer
```
若你想全域安裝此規則（套用到所有專案的 Agent 中），只需加上 `-g` 參數：
```bash
npx skills add https://github.com/drgarbage/ag-course-index --skill line-ui-designer -g
```

---

### 🛠️ 手動安裝 (備用方案)
如果你的環境無法使用 CLI，也可以將本目錄下的 [SKILL.md](SKILL.md) 檔案下載並手動放置到你專案根目錄的 `.agents/skills/line-ui-designer/` 下即可。
