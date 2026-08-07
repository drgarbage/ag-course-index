# LINE 互動入口設計師 Skill (`line-command-designer`)

`line-command-designer` 是一個為 AI Agent (例如 Antigravity) 設計的 LINE 機器人操作入口設計輔助 Skill。它能幫助 Agent 評估文字指令、Quick Reply、Buttons 樣板與圖文選單（Rich Menu）之間的取捨，並自動協助設計、生成選單底圖與上架選單，讓學員在實作 LINE 機器人互動入口時少走彎路。

## 🌟 核心特色
- **互動機制智慧決策**：根據功能高頻度與上下文，自動為學員選擇最佳觸發方式（常駐導覽選單、快速回覆 Quick Reply 或是非確認按鈕）。
- **Rich Menu 自動化產生與上架**：內含大圖/小圖的標準座標切割配置，配合專案內建 CLI 進行一鍵創立、清單查詢、預設設定、特定連結與刪除等維護。
- **UI & 控制流程完美拆分**：自動引導 Agent 專注在「怎麼觸發新功能」，並在功能完成後將邏輯分工給 `line-ui-designer` 與 `line-interact-planner`。

---

## 📦 安裝教學

你可以透過 `skills` CLI 在你的專案中一鍵安裝此 Skill。

### ⚡️ 快速一鍵安裝 (Recommended)
在你的專案根目錄下，開啟終端機並執行以下指令：
```bash
npx skills add drgarbage/ag-course-index --skill line-command-designer
```
若你想全域安裝此規則（套用到所有專案的 Agent 中），只需加上 `-g` 參數：
```bash
npx skills add drgarbage/ag-course-index --skill line-command-designer -g
```

---

### 🛠️ 手動安裝 (備用方案)
如果你的環境無法使用 CLI，也可以將本目錄下的 [SKILL.md](SKILL.md) 檔案下載並手動放置到你專案根目錄的 `.agents/skills/line-command-designer/` 下即可。
