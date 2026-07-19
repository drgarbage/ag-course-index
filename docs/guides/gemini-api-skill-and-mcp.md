# 用 Skill 與 MCP 讓 Antigravity 寫出更新的 Gemini API 程式

AI 程式助理熟悉許多常見寫法，但它的既有知識不一定包含最新的 Gemini 模型、SDK 與 API 變更。這個專案因此同時加入一個精簡的 Gemini API skill，以及 Google 提供的 Gemini Docs MCP：skill 告訴助理「應該怎麼做」，MCP 則讓它在動手前查到最新官方文件。

## 專案已加入的設定

```text
.agents/
├── mcp_config.json
└── skills/
    └── gemini-api-dev/
        └── SKILL.md
```

- [`.agents/skills/gemini-api-dev/SKILL.md`](../../.agents/skills/gemini-api-dev/SKILL.md) 是精簡版 skill。當工作涉及 Gemini API、函式呼叫、多模態或結構化輸出時，它會要求代理先查官方文件，採用目前的 Google Gen AI SDK，並避免把 API key 寫進程式碼。
- [`.agents/mcp_config.json`](../../.agents/mcp_config.json) 將 Antigravity 連到 Google 公開代管的 Gemini Docs MCP。這個遠端服務不需要在本機安裝套件，也不需要 API key。

這些都是專案層級設定：clone 或下載本專案後，以 Antigravity 開啟專案根目錄即可使用，不會影響其他專案。

## 啟用與確認

1. 使用 Antigravity 開啟本專案，若原本已開啟，請重新載入視窗或重新啟動，讓它重新索引 skill。
2. 在代理面板右上角的選單開啟 **MCP Servers**；或到 **Settings → Customizations → Installed MCP Servers**。
3. 重新整理後，確認 `gemini-api-docs` 顯示為已連線。
4. 輸入 `/skills list`，或到 **Customizations → Rules**，確認 `gemini-api-dev` 已被發現。

可以用這段提示測試：

> 請先查詢 Gemini 官方文件，再用目前的 Python SDK 示範 Gemini API 的脈絡快取功能，並說明你使用的 MCP 工具與 skill。

設定成功時，代理應先呼叫文件搜尋工具，再根據搜尋結果回答；不要只以「回答看起來合理」作為 MCP 已連線的證明。

## 為什麼不用把完整官方 skill 全部複製進來？

完整的 `gemini-api-dev` skill 包含當下的模型清單、各語言範例與大量參考內容，很適合需要離線提示的環境。不過模型名稱與 API 會變動，課程版只保留穩定的工作原則，把即時細節交給 Docs MCP 查詢。這樣內容較短、較容易讀，也降低日後硬編碼資訊過期的風險。

如果你的工作環境沒有網路，或希望直接安裝 Google 維護的完整版，可以在專案根目錄執行：

```bash
npx skills add google-gemini/gemini-skills --skill gemini-api-dev
```

若安裝工具把 skill 放到別的位置，請確認最後位於本專案的 `.agents/skills/`，或 Antigravity 的全域 skill 目錄 `~/.gemini/config/skills/`。專案版與全域版若同名且內容不同，建議只保留一份，避免規則衝突。

## 手動加入其他專案

要讓另一個專案使用相同設定，可複製本專案的 `.agents/skills/gemini-api-dev/`，再把以下項目合併到該專案的 `.agents/mcp_config.json`：

```json
{
  "mcpServers": {
    "gemini-api-docs": {
      "serverUrl": "https://gemini-api-docs-mcp.dev"
    }
  }
}
```

若目標檔案已有其他 `mcpServers`，只新增 `gemini-api-docs` 這一項，不要覆蓋原有設定。遠端 MCP 會收到代理送出的文件查詢內容，因此不要在查詢中附上 API key、密碼、客戶資料或其他機密資訊。

## 疑難排解

- **找不到 skill**：完全重新啟動 Antigravity，並確認路徑與檔名是 `.agents/skills/gemini-api-dev/SKILL.md`。
- **MCP 未連線**：確認網路可連到 `https://gemini-api-docs-mcp.dev`，且 JSON 沒有多餘逗號或被其他設定覆蓋。
- **回答仍使用舊 SDK 或模型**：明確要求「先使用 Gemini Docs MCP 查詢」，並查看執行紀錄中是否真的呼叫 `search_documentation`（服務版本不同時可能顯示為 `search_docs`）。
- **只想供自己所有專案使用**：skill 可移到 `~/.gemini/config/skills/`，MCP 可合併到 `~/.gemini/config/mcp_config.json`。

## 參考資料

- [Google：使用 Gemini MCP 和 Skills 設定程式設計助理](https://ai.google.dev/gemini-api/docs/coding-agents?hl=zh-tw)
- [Antigravity：Agent Skills](https://antigravity.google/docs/skills)
- [Antigravity：Model Context Protocol](https://antigravity.google/docs/mcp)
- [Google 維護的 Gemini API skills](https://github.com/google-gemini/gemini-skills)

[返回 README](../../README.md)
