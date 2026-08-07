# 修正 Gemini 總是出現模型錯誤的問題

AI 程式助理在編寫 Gemini API 時，經常因為使用了已淘汰的舊版模型（例如 `gemini-2.0-*`）而遭遇 404 錯誤，或是因為不當組合內建工具（例如將 Google 搜尋與自訂 Tool 同時傳遞）而導致 API 報錯。

透過在本機安裝 Google 官方的 Gemini Skills 並設定 Gemini Docs MCP 伺服器，可以讓助理在動手前自動比對並遵循 `gemini-agent-dev-support` 等開發規範，確保程式碼使用最新的模型與 SDK，避免錯誤寫法。

## 安裝與設定步驟

### 步驟一：安裝 Google 官方 Gemini Skills

請在終端機執行以下指令，將 Google 官方的 Gemini Skills 安裝至全域環境：

```bash
npx skills add google-gemini/gemini-skills --skill gemini-api-dev --global
npx skills add google-gemini/gemini-skills --skill gemini-live-api-dev --global
npx skills add google-gemini/gemini-skills --skill gemini-interactions-api --global
```

> [!NOTE]
> 使用 `--global` 參數會將 Skill 安裝至 Antigravity 的全域目錄中（例如 Windows 環境的 `C:\Users\<UserName>\.gemini\config\skills\`），讓所有專案皆能共享使用。

---

### 步驟二：設定 Gemini Docs MCP 伺服器

將 Antigravity 連接到 Google 公開代管的 Gemini Docs MCP。此服務不需要在本機安裝額外套件，也不需要 API key。

請編輯或建立全域設定檔 `~/.gemini/config/mcp_config.json`（若只想套用於單一專案，可於專案根目錄下建立 `.agents/mcp_config.json`），並加入以下內容：

```json
{
  "mcpServers": {
    "gemini-api-docs": {
      "serverUrl": "https://gemini-api-docs-mcp.dev"
    }
  }
}
```

> [!IMPORTANT]
> 如果設定檔中已有其他 `mcpServers`，請將 `gemini-api-docs` 新增至其列表中，不要直接覆蓋原有的其他設定。

---

### 步驟三：重啟與確認

1. **重啟助理**：完全重新啟動 Antigravity 視窗或 IDE，使其重新讀取全域設定與 Skill。
2. **確認 MCP 連線**：
   - 在助理面板右上角的選單點選 **MCP Servers**，或進入 **Settings → Customizations → Installed MCP Servers**。
   - 確認 `gemini-api-docs` 顯示為**已連線 (Connected)**。
3. **確認 Skill 載入**：
   - 在聊天輸入框輸入 `/skills list`，或進入 **Settings → Customizations → Rules**。
   - 確認已載入 `gemini-api-dev`、`gemini-live-api-dev` 與 `gemini-interactions-api` 三個 Skill。

---

### 步驟四：功能測試

您可以使用以下提示詞（Prompt）來測試設定是否生效：

> 請先查詢 Gemini 官方文件，再用目前的 Python SDK 示範 Gemini API 的脈絡快取功能，並說明你使用的 MCP 工具與 skill。

**測試成功指標**：代理在回答前應會先呼叫 `search_documentation` MCP 工具，並根據最新官方文件生成正確的程式碼與回覆。

---

## 疑難排解

- **找不到 Skill**：確認 Skill 已正確下載至全域目錄 `~/.gemini/config/skills/` 下，並完全重啟 Antigravity。
- **MCP 未連線**：確認網路連線正常且能存取 `https://gemini-api-docs-mcp.dev`，並檢查 `mcp_config.json` 的 JSON 語法是否正確（如是否漏掉逗號或大括號）。
- **回答仍使用舊版 SDK**：如果助理沒有主動呼叫，可在提示詞中明確指示：「請先使用 Gemini Docs MCP 查詢最新文件」。

## 參考資料

- [Google：使用 Gemini MCP 和 Skills 設定程式設計助理](https://ai.google.dev/gemini-api/docs/coding-agents?hl=zh-tw)
- [Antigravity：Agent Skills](https://antigravity.google/docs/skills)
- [Antigravity：Model Context Protocol](https://antigravity.google/docs/mcp)
- [Google 維護的 Gemini API skills 專案倉庫](https://github.com/google-gemini/gemini-skills)

[返回 README](../../README.md)
