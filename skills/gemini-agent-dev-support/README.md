# Gemini Agent Development Support Skill (`gemini-agent-dev-support`)

`gemini-agent-dev-support` 是一個為 AI Agent (例如 Antigravity) 設計的專用開發輔助 Skill。它旨在幫助學員在使用 AI 輔助開發 Gemini API 與相關 Agent 專案時，預防 AI 犯下常見的 SDK 版本衝突、API 格式不符或前端金鑰洩漏等低級錯誤，讓學員能專心在核心功能邏輯的實作上。

## 🌟 核心特色
- **設計架構預定義 (Planning Grounding)**：在 Agent 提出實作計畫 (Implementation Plan) 前，強制約束必須先確認 SDK 依賴版本（禁用舊版 `@google/generative-ai`，一律使用 `@google/genai`）、金鑰後端保護政策、時間感知等架構。
- **物理事實程式自檢 (Code-driven Self-healing)**：內含無註解高密度的標準代碼骨架（包括 IME 輸入處理、動態選單 API、雙代 2.x/3.x 工具分流相容、XSS 安全防護、去敏錯誤結構等），引導 Agent 在開發與除錯階段自動套用正確範例。
- **防退化回報機制 (Anti-regression)**：交付體檢報告中強制包含 `Recurrence Protection`（防復發決策欄位），確保每次 Bug 修正皆具備防退化保護措施。

---

## 📦 安裝與配置教學

### ⚡️ 快速一鍵安裝 (Recommended)
在你的專案根目錄下，開啟終端機並執行以下指令，即可透過 `skills` CLI 一鍵將此 Skill 下載並配置到你專案的 `.agents/` 目錄中：
```bash
npx skills add https://github.com/drgarbage/ag-course-index --skill gemini-agent-dev-support
```
若你想將此自檢規則進行**全域安裝**（讓所有專案的 Agent 都套用），只需加上 `-g` 參數：
```bash
npx skills add https://github.com/drgarbage/ag-course-index --skill gemini-agent-dev-support -g
```

---

### 🛠️ 手動安裝與配置 (備用方案)
如果你的環境無法使用 CLI，也可以透過以下手動方式在你的 AI IDE/Agent 中啟用：

#### 方式 A：專案內啟用 (Project-scoped Customization)
這是最推薦的方式。將此 Skill 複製到你正在開發的專案根目錄下，作為該專案的 Agent 開發規則。

1. 在你的專案根目錄下建立 `.agents/skills/gemini-agent-dev-support` 目錄：
   ```bash
   mkdir -p .agents/skills/gemini-agent-dev-support
   ```
2. 將本目錄底下的 [SKILL.md](SKILL.md) 檔案複製或下載到該目錄下：
   ```bash
   # 複製 SKILL.md 到你的專案中
   cp path/to/this/skills/gemini-agent-dev-support/SKILL.md .agents/skills/gemini-agent-dev-support/SKILL.md
   ```
3. 重啟或重新整理你的 AI Agent，IDE 即會自動發現並載入 `gemini-agent-dev-support` 規則。

### 方式 B：全域啟用 (Global Customization)
如果你希望所有專案的 AI Agent 在與你 pair programming 時都遵守此規則，可以將其安裝至你的全域設定中。

1. 尋找你的 IDE 全域客製化根目錄。以 MacOS / Linux 的 Gemini-antigravity 為例，路徑通常為：
   ```bash
   ~/.gemini/config/skills/gemini-agent-dev-support
   ```
2. 在該目錄下建立對應資料夾，並放入本目錄的 `SKILL.md` 即可。

### 方式 C：透過 `skills.json` 進行參照分享
若你不希望複製檔案，而是直接參照本開源專案中的路徑，可以在你專案的 `.agents/` 底下建立 `skills.json`：

```json
{
  "entries": [
    { "path": "path/to/ai-class-examples/ag-course-index/skills/gemini-agent-dev-support" }
  ]
}
```

---

## 🚀 運作機制說明
安裝此 Skill 後，AI Agent 的執行邏輯將會自動改變：
1. **在 `/plan` 階段**：Agent 會依據此 Skill 規範的 `Planning Phase` 先查閱官方文檔 docs，並在實作計畫中排除 mock/stub 與 legacy SDK。
2. **在 `/execute` 階段**：Agent 會自動拿 [SKILL.md](SKILL.md) 內附的代碼作為對比基準，在 coding 或遭遇 API 異常時自行重構。
3. **在 `/verify` 階段**：Agent 會以此 Skill 規定的 Checklist 和產出格式向你回報體檢報告。
