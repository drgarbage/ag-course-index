# Gemini／AI Agent 課程範例自檢提示詞

以下提示詞整理自課程範例曾發生的問題。請在新增功能、修改 Gemini API、移植範例或交付前，將整段貼給 AI Agent。它是檢查框架，不是舊實作的固定答案；SDK、模型與 API schema 一律以執行當下的官方文件為準。

## AI Agent 自檢提示詞

````markdown
# Gemini／AI Agent 課程範例交付前體檢

你現在是本專案的資深維護者。請對本次變更做「查證、檢查、修正、驗證」四階段體檢，不要只閱讀程式後口頭保證，也不要把這份清單中的歷史解法直接視為現行 API 規格。

## 工作原則

1. 先讀取目標專案的 `AGENTS.md`／平台 rules、相關程式、package manifest／lockfile、設定檔與既有測試，確認實際 SDK 及版本。若規則檔不存在，先記錄缺口，不要因此中止檢查。
2. Gemini 的模型、SDK、API、工具欄位及限制會變動。先查 Google Gemini API 最新官方文件，再決定實作；列出使用的官方文件連結與查證日期。不得只憑 AI 記憶猜模型名稱或欄位。
3. 保留使用者既有且與任務無關的變更。只修改本次問題所需範圍；發現額外問題時先列為風險，不要無限擴張工作。
4. 先提出檢查結果與預計修改，再完成最小而完整的修正。最後執行可用的 lint、typecheck、build、unit／integration／E2E 測試。

## A. SDK、模型與請求來源

- [ ] JavaScript／TypeScript 專案是否使用現行 `@google/genai`？新增或更新功能禁止安裝、匯入或透過 CDN 載入舊版 `@google/generative-ai`。掃描 `package.json`、lockfile、import、dynamic import、import map、CDN URL 與文件範例，不得只檢查其中一處。
- [ ] 若目標是刻意保存、尚未遷移的歷史課程範例，舊版 `@google/generative-ai` 只能搭配該教材已驗證的 Gemini 2.x 模型，不得接上 Gemini 3.x 或更新模型，也不得為它新增功能。必須明確標示 legacy、鎖定套件與模型版本、隔離於現行範例，並提出遷移至 `@google/genai` 的方案；除此之外一律判定 FAIL。
- [ ] 使用 `@google/genai` 的 Web App 是否以 HTTP(S) 伺服器運行為設計與交付目標？開發／課堂示範應提供可重現的 dev server 指令（例如專案既有的 `npm run dev`），不得把雙擊 `index.html` 形成的 `file://` 頁面當成支援的啟動方式或為它維護另一套 CDN／inline 實作。`file://` 缺少正常 Web origin，可能使 SDK 請求、ES modules、CORS、Secure Context、路由與資源載入失敗；必須在實際 HTTP(S) origin 驗證。
- [ ] 正式環境的 Gemini API 呼叫與長效 API Key 是否位於 server-side／backend proxy？即使 SDK 技術上能在 browser 初始化，也不得把正式金鑰編譯或寫入前端。若課程刻意示範 browser-only 呼叫，須清楚標示僅供本機學習、說明風險、使用受限或短效憑證（若適用），且仍透過 localhost dev server 運行。
- [ ] 模型選單是否由 SDK／Models API 動態取得並依能力過濾，而非硬編碼一份容易過期的「可用模型」清單？課程若刻意鎖定單一模型，是否清楚標示為課程設定？
- [ ] 模型 ID、endpoint、HTTP method、request casing 與型別是否符合目前所用 SDK 或 REST schema？不要把 REST 錯誤訊息中的 `snake_case` 直接貼進使用 `camelCase` 的 SDK。
- [ ] API Key／虛擬金鑰是否只經安全設定取得，且不會出現在原始碼、錯誤 UI、log 或測試快照？

## B. 輸入與聊天 UI

- [ ] 成功送出後是否清空輸入框？空白訊息、重複送出、loading 狀態與 `Shift+Enter` 是否合理？
- [ ] IME 是否同時防護 `event.isComposing`、應用程式組字狀態及 `keyCode === 229`？請測試一般 Enter，以及 macOS Chrome／Safari 可用環境中的中文或日文選字 Enter；不要只靠 `setTimeout(..., 0)`。
- [ ] 若有語音輸入規格，是否真的串接權限與辨識／錄音流程，顯示聆聽、停止、錯誤、重試狀態，說明 HTTPS／localhost 限制，並在不支援時保留文字輸入 fallback？不可只有麥克風按鈕。

## C. 錯誤處理與內容渲染

- [ ] 503／過載、400／API Key、401／403、429／配額、網路中斷及未知錯誤，是否提供親切的繁體中文摘要和可採取的下一步？
- [ ] 是否可展開查看已去敏的原始錯誤？插入 HTML 前是否 escape／sanitize，以免 XSS 或祕密洩漏？不得只靠易碎的英文關鍵字；可用時優先讀 status、code 與結構化 error details。
- [ ] Markdown 是否真的解析並具有可辨識的標題、清單、引用、連結、inline code 與 code block 樣式？若用 Tailwind `prose`，Typography plugin／CSS 是否確實載入？HTML 是否經安全清理？

## D. UI 與 API 行為一致

- [ ] 逐一列出 Web Search、模型選擇、語音、工具等 UI 控制，追蹤到 request payload 或實際處理器，證明不是只有畫面、沒有功能的假開關。
- [ ] 產品與課程交付功能是否完全禁止 mock／placeholder／demo-only 假實作？搜尋 hard-coded response、假資料、隨機結果、`setTimeout` 假 loading、永遠成功的 stub、未呼叫真實 API／tool 的 handler、`TODO` 假按鈕，以及捕捉錯誤後改回傳成功資料的 fallback。功能尚未完成時應明確停用並標示，不得偽裝成可用。
- [ ] 測試中的 mock／fake／stub 可以保留，但只能位於測試或明確的 development fixture 範圍，名稱與 UI 必須清楚揭露，不得被 production build、正式路由或課程成果預設載入。至少要有一條整合或 E2E 路徑驗證真實 SDK／API／tool wiring；不能只用 mock 測試就宣稱功能完成。
- [ ] 用可觀察證據驗證狀態：request payload、mock assertion、API response metadata 或 E2E 結果。若快取可能遮蔽修正，使用正常的開發伺服器／建置與 cache invalidation，並確認瀏覽器載入的是新資源。
- [ ] README／課程步驟是否只提供伺服器式啟動流程，且從全新 clone 能以文件中的命令啟動？掃描是否仍有「雙擊 `index.html`」、「直接開啟 HTML」、`file://` 相容分支或為直開模式載入的 CDN SDK；若非 Electron 等明確且已驗證的特殊 runtime，應移除或改寫。

## E. Google Search 與 Custom Tools

- [ ] 若課程規格要求 Search 與 Custom Tools always-on，每次 request 是否都宣告兩類工具，交由模型決定用哪個，而非前端用關鍵字猜測？保留的舊 UI 欄位是否清楚標示只為相容用途？
- [ ] 使用 Generate Content API 混合 server-side built-in tool 與 client-side function calling 時，是否依目前官方文件設定 server-side tool invocation opt-in？對 `@google/genai` 應由型別確認 `camelCase`；對 REST 應依 JSON schema，不可混用。
- [ ] 工具流程是否形成完整迴圈：接收 function call → 驗證名稱與參數 → 執行 handler → 回傳對應 function response → 取得最終回答？是否處理未知工具、執行失敗、平行／連續呼叫及最大迴圈次數？

## F. 多輪歷史與工具上下文

- [ ] 不得使用不存在的 plural `functionCalls` part，也不得自行把工具過程壓成一段顯示文字。檢查每個 `functionCall` 是否有名稱、參數與對應的 `functionResponse`／call ID。
- [ ] 優先把 SDK 的完整 model response 直接加入 history，或使用官方 server-side continuation。若手動重建，須依目前 API 保留正確角色、順序、tool call／response、thought signature 與 server-side tool context；不要只保存 UI message。
- [ ] 建立含工具呼叫的多輪測試：第一輪呼叫工具並回答，第二輪引用先前結果，重新載入／還原後再追問。確認不是只在單一模型、單一 happy path 偶然成功。
- [ ] 若使用舊版 SDK `startChat` session，跨模型記憶必須實測；不要把過去「只有某模型可用」的觀察當永久規格。若需要穩定切換模型，採官方支援的完整歷史或 continuation 機制。

## G. 代理層、虛擬金鑰與模型映射

- [ ] 若有 BFF／Caddy／LiteLLM 等代理，追蹤 SDK 實際發出的 method、path、query、headers、body 與 streaming；確認虛擬金鑰會先被驗證，再安全換成上游憑證。
- [ ] Models、Files、Caches 等 GET endpoint 是否能正確轉送，而不是落入只支援 POST `generateContent` 的路由？上游 status、必要 headers 與 response body 是否正確保留？
- [ ] 代理模型映射是否涵蓋本課程實際使用的文字、image、video 與 embedding 模型？模型名稱與供應商能力須由目前配置和官方資料驗證。
- [ ] 至少執行模型清單 GET、一般／串流生成、Custom Tool、Search、embedding；專案有使用時再測 image／video。測試應能防止路由與模型映射日後回歸。

## H. Gemini API Skill 與 Docs MCP 設定

以下檢查要求已完整包含在本提示詞中，不依賴來源專案的其他指南或模板。把「檔案存在」、「設定正確」與「執行時真的啟用」分開驗證，不得因檔案存在就直接判定完成。

### 靜態設定

- [ ] 是否存在 `.agents/skills/gemini-api-dev/SKILL.md`，且 frontmatter 至少具有正確的 `name` 與 `description`？內容是否要求先查最新官方文件、使用現行 SDK、避免猜測模型／欄位及保護 API Key？
- [ ] 是否存在合法 JSON 的 `.agents/mcp_config.json`，其中 `mcpServers.gemini-api-docs.serverUrl` 是否為 `https://gemini-api-docs-mcp.dev`？若原本已有其他 servers，是否採合併而非覆蓋？最低設定如下：

  ```json
  {
    "mcpServers": {
      "gemini-api-docs": {
        "serverUrl": "https://gemini-api-docs-mcp.dev"
      }
    }
  }
  ```
- [ ] skill 路徑、檔名、名稱與 MCP server 名稱是否符合使用者實際採用的 Agent 平台？是否存在專案版與全域版同名、內容不同而造成優先順序或規則衝突？
- [ ] `.gitignore`、下載／打包流程或課程 starter 是否會漏掉 `.agents` 隱藏目錄？clone 或解壓後能否保留完整設定？
- [ ] MCP 設定與 skill 是否不含 API Key、密碼、客戶資料或其他機密？送往遠端 MCP 的查詢是否禁止包含敏感內容？

### 執行時驗證

- [ ] 重新載入／啟動 Agent 後，skill 清單或 Rules UI 是否能找到 `gemini-api-dev`？請提供命令輸出或畫面觀察結果；若目前環境無法操作 UI，標記為 `未驗證`，不可填 PASS。
- [ ] MCP Servers UI 或可用工具清單是否顯示 `gemini-api-docs` 已連線，並暴露 `search_documentation` 或 `search_docs`？只有 JSON 設定不算連線成功。
- [ ] 是否執行以下 smoke prompt，並從工具執行紀錄證明 Agent **先呼叫 Docs MCP**、再根據搜尋結果回答？「答案看起來正確」不能作為 MCP 已啟用的證據。

  > 請先查詢 Gemini 官方文件，再用目前的 Python SDK 示範 Gemini API 的脈絡快取功能，並說明你使用的 MCP 工具與 skill。
- [ ] MCP 無法連線時，skill 是否會 fallback 到 `https://ai.google.dev/gemini-api/docs/llms.txt` 或相關 Gemini 官方文件，並在結果中明確揭露 fallback，而不是靜默依賴模型記憶？
- [ ] 若設定不足，是否以最小變更補齊，重新執行 JSON 解析、skill discovery、MCP connection 與 smoke test？若無權修改使用者的全域設定，只提出明確步驟，不擅自寫入家目錄。

## I. 防止問題再次發生的機制

修正每個 `FAIL` 後，評估它應由哪一層長期防護。不要只修當下程式，也不要不加判斷地為每個問題都建立新 skill。

- [ ] **Rule／AGENTS.md**：跨任務必須遵守且需要語意判斷的原則，是否已加入最接近作用範圍的規則？若目標專案沒有規則檔，是否先確認確有持續性需求，再選擇該 Agent 平台支援的位置？
- [ ] **Hook／CI／自動測試**：能由確定性命令判定的問題，是否加入可重現的檢查，例如 JSON schema、禁止舊 SDK 或靜態模型清單、lint、typecheck、build、工具歷史與代理路由整合測試？
- [ ] **Skill**：需要專門知識、官方文件查證、固定流程或重用腳本的工作，現有 skill 是否已涵蓋？只有確實缺少可重用能力時才新增或更新 skill，並檢查名稱衝突與觸發描述。
- [ ] **文件**：背景、人工操作與疑難排解是否更新？可以自動驗證的條件不得只留下文件提醒。
- [ ] 新增任何 rule、hook、CI 或 skill 後，是否實際證明它會在預期時機被載入、觸發、失敗與通過？是否保留既有設定並避免覆蓋其他 hooks、MCP servers 或 skills？

請在結果中為每個修正附上「復發防護決策」：`Rule`、`Hook/CI/Test`、`Skill`、`Document`、`不需新增`（含理由），以及本次是否已實作。若建立新機制超出使用者授權，只能提出建議，不得擅自擴張變更。

### 內嵌的候選專案規則模板

若評估結果需要新增或更新 Rule，使用下列模板作為候選內容。先刪除與目標專案無關的條目，再合併到該 Agent 平台支援、且最接近作用範圍的規則檔。不得假設檔名一定是 `AGENTS.md`，不得整份盲目複製，也不得覆蓋既有規則。

```markdown
## Gemini API 開發規則

### 開工前

1. 先讀取相關程式、依賴與 lockfile、設定及測試，確認實際 SDK、版本與 API。
2. Gemini 模型、SDK、API 與工具 schema 屬於時效性資訊。實作前先查 Google Gemini API 最新官方文件，不得只依賴模型記憶或舊範例。
3. JavaScript／TypeScript 新增或更新功能一律使用 `@google/genai`，禁止使用舊版 `@google/generative-ai`，包含 npm dependency、import、import map 與 CDN 載入。
4. 只有刻意保留且隔離的 legacy 教材可暫用 `@google/generative-ai`，並只能搭配教材已驗證的 Gemini 2.x 模型；不得用於 Gemini 3.x／更新模型或新功能。須鎖定版本、標示限制並附遷移方案。
5. 使用 `@google/genai` 的 Web App 必須透過 HTTP(S) 開發伺服器、preview server 或正式伺服器運行，不支援以 `file://` 雙擊 `index.html`。提供可重現的啟動命令，並以實際 origin 驗證 SDK 請求、ES modules、CORS、Secure Context、路由與資源載入。
6. 正式環境的 Gemini API 呼叫與長效 API Key 必須置於 server-side／backend proxy，不得將金鑰編譯或寫入瀏覽器程式。browser-only 課堂示範須標示用途與風險，且仍透過 localhost dev server 執行。
7. 模型選單應由 SDK／Models API 取得並依能力過濾。課程若鎖定模型，標示為相容性設定，不得宣稱是完整可用模型清單。
8. 檢查 Gemini API skill 與 Docs MCP 的靜態設定及執行狀態。MCP 不可用時，改讀 Gemini 官方 `llms.txt` 或相關官方文件並揭露 fallback。

### 實作要求

- 文字送出流程須處理 IME、一般 Enter、Shift+Enter、重複送出與成功後清空。
- 使用者可見錯誤須提供繁體中文摘要、下一步與已去敏的詳細資訊；HTML／Markdown 必須安全渲染並具備實際排版樣式。
- 每個 UI 功能須連到真實請求、權限或處理器，並以 request／response 或測試證明生效。
- 產品與課程交付禁止 mock／placeholder／demo-only 假功能，包括 hard-coded response、假資料、假 loading、永遠成功的 stub、未連接真實 API／tool 的 handler，以及把錯誤偽裝成成功資料的 fallback。未完成功能應停用並清楚標示。
- 測試替身只能存在於 tests 或明確的 development fixtures，不得進入 production path。至少保留一條整合或 E2E 測試驗證真實 SDK／API／tool wiring，不得只憑 mock 測試宣稱完成。
- README 與課程操作只提供伺服器式啟動流程；不得為雙擊直開 HTML 維護 CDN／inline 的第二套實作。Electron 等特殊 runtime 必須另行驗證 protocol 與 Secure Context，不能當成一般 Web App 例外。
- 混合 Google Search 與 Custom Tools 時，依目前 SDK／REST 官方 schema 設定工具與 server-side invocation，不猜測欄位 casing。
- Custom Tool 須完成呼叫、參數驗證、執行、回傳結果與最終回答的閉環，並處理未知工具、失敗、平行／連續呼叫及迴圈上限。
- 對話歷史優先保留 SDK 完整 response；手動序列化時須保留官方要求的角色、tool call／response、call ID、thought signature 與 server-side tool context。
- 不得將單一模型或舊 SDK 的測試結果泛化成永久限制；跨模型與多輪工具歷史必須實測。
- 語音輸入若在規格內，須處理權限、狀態、停止、錯誤、重試、HTTPS／localhost 限制與文字 fallback，不能只有麥克風圖示。
- 代理／虛擬金鑰須驗證實際 method、path、query、headers、streaming、GET endpoints 及課程使用的文字、媒體與 embedding 模型映射。
- API Key、token、客戶資料及其他祕密不得出現在原始碼、log、錯誤 UI、測試快照或遠端 MCP 查詢。

### 完工前

1. 依範圍執行 lint、型別檢查、build、單元與整合測試；不能執行的項目須說明原因。
2. 從全新 clone 依 README 的 dev／preview 命令啟動，確認頁面來源為 `http://localhost`、`http://127.0.0.1` 或 HTTPS，而不是 `file://`；驗證重新整理、靜態資源、API／proxy 與 CORS。
3. 聊天 UI 至少驗證 Enter、Shift+Enter、中文／日文 IME、輸入清除、Markdown、錯誤摘要、詳細資訊與去敏。
4. 工具至少驗證不用工具、只用 Search、只用 Custom Tool、兩者串接、工具失敗及工具後續追問。
5. 代理存在時至少驗證模型清單 GET、一般生成、串流、Custom Tool、Search、embedding，以及專案有使用的影像／影片功能。
6. 回報修改檔案、測試證據與未驗證風險；沒有證據時不得宣稱「完全解決」或「全覆蓋」。
```

## 最低驗證矩陣

| 範圍 | 必測案例 |
| --- | --- |
| UI | 一般 Enter、Shift+Enter、中文／日文 IME、送出後清空、loading 防重複送出 |
| Web 啟動 | 全新 clone、依 README 啟動 dev／preview server、HTTP(S) origin、重新整理、靜態資源、API／proxy、CORS；確認沒有要求雙擊 `index.html` 的文件或分支 |
| SDK／模型 | dependency、lockfile、imports、CDN 與文件均無 `@google/generative-ai`；若為隔離 legacy 教材，確認只使用已驗證的 2.x 模型、版本鎖定與遷移說明 |
| 真實功能 | 掃描 hard-coded response、假資料、假 loading、stub 與 mock fallback；確認 production path 無測試替身，並以 integration／E2E 證明真實 SDK、API 與 tools wiring |
| 顯示 | Markdown 標題／清單／code、惡意 HTML、友善錯誤、詳細錯誤展開與去敏 |
| 工具 | 不用工具、只用 Search、只用 Custom Tool、兩者串接、工具失敗、工具後續追問 |
| API | 模型清單與能力過濾、目前選定模型的正常生成、代理存在時的 GET／streaming／媒體／embedding 路徑 |
| Agent 設定 | skill 靜態檔案、MCP JSON、skill discovery、MCP connection、Docs MCP smoke prompt、官方文件 fallback |
| 復發防護 | rule 載入、hook／CI／test 的失敗與通過案例、skill 觸發與衝突檢查 |

## 輸出格式

請嚴格使用以下 Markdown 結構交付：

### 官方文件查證

| 項目 | 採用內容 | 官方文件 | 查證日期 |
| --- | --- | --- | --- |
| SDK／版本 |  |  |  |
| API／模型策略 |  |  |  |

### 檢查結果

| 編號 | 檢查項目 | 結果 | 證據或原因 |
| --- | --- | --- | --- |
| A1 |  | PASS／FAIL／N/A |  |

> `N/A` 必須說明不適用原因；`PASS` 必須附上程式位置、測試或其他可觀察證據。

### 已修正

- `path/to/file`：關鍵變更與理由

### 復發防護決策

| 問題 | 防護層 | 本次是否實作 | 檔案／機制 | 理由與觸發證據 |
| --- | --- | --- | --- | --- |
|  | Rule／Hook/CI/Test／Skill／Document／不需新增 | 是／否 |  |  |

### 驗證證據

```text
實際執行的命令與結果摘要
```

### 剩餘風險

- 未能測試的瀏覽器、真實 API、代理或付費媒體能力；若無，明確寫「無已知剩餘風險」。

除非有對應測試或可觀察證據，不得宣稱「完全解決」、「完美支援」或「全覆蓋」。
````

## 使用方式

可直接貼上完整提示詞做交付前總檢，也可以指定範圍，例如：「只執行 D、E、F，並修正所有 FAIL」。若要 AI 實際修改，請一併提供目標 repository、可執行的測試方式與必要的測試憑證；不要把真實金鑰貼進提示詞或提交到 Git。
