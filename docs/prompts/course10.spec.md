# Universal Screen Collaborative Copilot — Functional Specification (Class 10)

本文件定義「即時協作助理」與「宿主外殼 Chat View」整合之功能規格書，以使用者體驗與功能服務為主軸，排除了框架依賴，並採用精確、單一字義的專業關鍵字描述技術細節。

---

## 1. 核心服務與使用者流程 (User Experience & Core Services)

### 1.1 啟動與授權流程 (Onboarding & Activation Flow)
- **BYOK Setup**: 使用者於宿主系統填入 `GEMINI_API_KEY`。未提供金鑰時，阻斷所有 AI 主動與被動請求並顯示錯誤提示。
- **Screen Sharing Permission**: 使用者手動開啟 `getDisplayMedia` 授權。系統接收螢幕視訊串流以供後續擷取與觀察。
- **Document PiP Initialization**: 使用者必須手動點擊按鈕，以觸發瀏覽器開窗手勢，開啟 **Always on Top** 的懸浮視窗。
- **Google API Authorization Flow**: 整合 Google Contacts (People API), Calendar API, 及 Gmail API。若工具回傳 `UNAUTHORIZED` 或 `TOKEN_EXPIRED`，自動在宿主設定分頁提供 OAuth 授權連結，並在完成授權後發送系統通知至對話通道。

### 1.2 六大核心工作服務 (Core Workflow Scenarios)
1. **即時問答 (Context-Aware Q&A)**：接收語音或文字提問，綜合畫面脈絡、記憶、與 Google 搜尋，將 HTML 答案呈現至懸浮小窗，並用語音作簡短重點回覆。
2. **主動提示服務 (Proactive Notification)**：背景觀察通道分析使用者卡關或畫面有價值資訊時，推送通知至懸浮窗，並視設定撥放語音提示。
3. **網頁/事實搜尋 (Grounding Search)**：當提問涉及變動事實（如套件版本、新聞、規格），**禁止** AI 憑記憶作答，強制作 Google 搜尋查證，並將「結論 + 來源 URL」呈現在懸浮窗。
4. **即時畫面翻譯 (Instant Focus Translation)**：語音呼叫「翻譯這段」，擷取畫面指定區域高解析像素圖，翻譯並以 HTML 呈現在懸浮窗，同時以語音朗讀。
5. **主動卡關協助 (Struggling Intervention)**：偵測到錯誤訊息停滯、反覆開關同頁面或重複搜尋同關鍵字時，跳出「建議與預設行動按鈕」的問答版面，使用者確認後執行。
6. **Markdown 工作報告匯出 (Markdown Report Export)**：語音或手動點擊「整理成摘要報告」，自動將指定的 Memo 筆記，整理成帶有未完成待辦事項與參考連結的 Markdown 全文。

### 1.3 對話結束與記憶昇華 (Session Cleanup)
- 語音收到「今天到這」或「結束對話」時，觸發記憶昇華（Consolidate），將本次對話的短程記憶提煉儲存為長程記憶，並清空當次短程記憶。

---

## 2. UI 狀態與版面 (UI States & Layouts)

### 2.1 宿主主畫面 (Host Main View - Full Page)
- **Status Dashboard**: 包含三個即時狀態燈號：
  - `Screen Share`: 綠燈（`getDisplayMedia` 運作中）/ 灰燈（未啟動）
  - `Active Observation`: 綠燈（背景觀察迴圈執行中，顯示最近更新時間）/ 灰燈（未啟動）
  - `Voice Chat`: 綠燈（Live Session 連線中）/ 灰燈（未連線）
- **Host Chat View**: 位於右下角可收闔面板。接收鍵盤文字輸入作為語音備援，並即時渲染對話文字紀錄。
- **Tabs Layout**:
  - `Memo`: 左側為關鍵字、標籤篩選器及 Memo 清單；右側為 Markdown 編輯器與 HTML 預覽面板。
  - `Memory`: 唯讀的長程與短程記憶檢視面板（長程記憶支援單筆刪除，短程支援一鍵清空）。
  - `Settings`: 個性預設集切換（積極/穩重/專業/慎重），以及聲音模型切換（男聲/女聲）。
  - `Report`: Markdown 報告純文字預覽、一鍵複製至剪貼簿與下載 `.md` 檔案按鈕。

### 2.2 懸浮畫中畫視窗 (Document PiP Window)
- **Window Specs**: **Always on Top**, 內嵌沙盒化 `iframe`：`<iframe sandbox="allow-scripts allow-same-origin" />`，固定寬度約 360px。一律採用 **Light Mode Only**（白色/極淺色背景，高對比深色字，避開深色模式）。
- **PiP Layouts**:
  - `Content Layout`: 顯示唯讀的精簡 HTML 卡片資訊、圖示、Emoji 與外部媒體嵌入（YouTube / Maps）。底部提供一鍵儲存為 HTML 類別 Memo 之按鈕。
  - `Prompt Layout`: 提供文字詢問訊息、自由文字輸入框、以及最多 3 個預設選項按鈕。使用者點擊後透過 `postMessage` 傳送回應回 AI 通道。
- **PiP Queue States**:
  - `Closed`: PiP 未開啟。Agent 送出內容轉為 `pending` 暫存，宿主開啟浮動視窗按鈕亮琥珀色外框並改字為「助理有話要說」。
  - `Idle`: 待命中。
  - `Showing`: 顯示當前 HTML 卡片。
  - `Badged`: 顯示狀態下，收到非覆蓋式更新（`replace: false`）。**保留現有畫面**，小窗右上角亮起紅點通知，新內容排隊，等使用者按 Dismiss 後才遞補顯示。

---

## 3. 資料儲存與格式 (Data Models & Storage)

### 3.1 Memo 筆記資料格式 (Memo Schema)
```typescript
interface Memo {
  id: string;                     // 唯一識別碼
  title: string;                  // 標題，無標題時預設「未命名 Memo」
  summary: string;                // 1-2句列表摘要
  content: string;                // Markdown 正文
  translation?: string;           // 翻譯結果
  type: 'text' | 'html';          // 筆記類型 (html 為互動式卡片小工具)
  htmlContent?: string;           // 互動式 HTML5 + Script 原始碼
  tags: string[];                 // 標籤陣列
  todos: Array<{                  // 待辦清單
    text: string; 
    done: boolean 
  }>;
  userNote?: string;              // 使用者備註 (AI 唯讀，禁止覆寫)
  screenshotIds: string[];        // 對應至儲存資料庫的截圖 ID 陣列
  sourceUrls?: Array<{            // Google Grounding 查證來源
    url: string; 
    title: string 
  }>;
  createdAt: number;              // 建立時間戳記
  updatedAt: number;              // 更新時間戳記
}
```
- **Storage Strategy**:
  - `Memo metadata`: 序列化儲存於 `localStorage['class10_memos']`。
  - `Screenshots`: base64 影像資料儲存於 **IndexedDB** 獨立物件倉庫，避免塞爆 `localStorage` 配額。刪除 Memo 時必須刪除對應的 IndexedDB 資料。

### 3.2 記憶儲存格式 (Memory Schema)
- **長程記憶 (Long-Term)**：儲存於 `localStorage`。欄位包含 `category` (identity / goal / solved / domain 等)、`key`、`value` 及 `confidence` (把握度 0–1)。**規則**：低把握度事實不得覆寫既有高把握度事實。
- **短程記憶 (Short-Term)**：暫存於對話 Session 記憶體。以 `topic` 作為 key，新進內容直接取代同 topic 舊內容，不進行堆疊。
- **運行注入 (Runtime Injection)**：每回合將長短期記憶格式化為 `buildMemoryContext()`，隨 `setRuntimeContext` 注入 AI 模型。

---

## 4. AI 能力與通訊架構 (AI Modalities & Architecture)

### 4.1 雙通道通訊管道 (Dual-Channel Communication)
- **語音對話通道 (Real-time Audio Channel)**:
  - `@google/genai`
  - `gemini-3.1-flash-live-preview`
  - `ai.live.connect({ responseModalities: ['audio'], speechConfig: ... })`
  - 提供低延遲、雙向語音互動。語音聲音與個性設定參數由宿主透過 `setLiveOverrides` 機制動態覆寫。當使用者用語音要求「看螢幕」時，傳送單張畫面影像至 Session。
- **背景觀察通道 (Background Vision Observer)**:
  - 獨立計時迴圈，定期擷取螢幕畫面，調用 Unary `generateContent` 傳入影像及 System Instruction，由 AI 判定當前活動（activity）、目標意圖（intent）以及是否卡關（strugglingSignal）。

### 4.2 螢幕擷取與視覺定位 (Screen Capture & Crop Pipeline)
- **`captureScreen` Tool**:
  - `full` 模式: 全螢幕縮小至長邊 ~1024px，提供整體視覺脈絡。
  - `focus` 模式: 根據 X, Y 座標與寬高（預設 1024x1024），在瀏覽器端使用 canvas 進行**原始像素裁剪**（確保文字/代碼清晰）。
  - **二段式定位 (Two-Step Cropping)**: 由於瀏覽器取不到 OS 游標座標，AI 需先擷取 `full` 全螢幕，分析 screenSize，推算目標座標後，再次呼叫 `focus` 擷取高解析度局部畫面進行辨識與處理。

### 4.3 個性與介入度參數化 (Persona Parameterization)
個性由標準化參數定義，直接寫入系統提示詞中以影響 AI 行為與觀察間隔：
- `attitude`: 處理態度（主動程度）。
- `proactiveness` (1–5 級)：主動介入積極度，決定背景觀察迴圈的輪詢間隔（25秒至120秒不等）。
- `verbosity` (terse / balanced / detailed)：規範語音與文字答覆長度。
- `emotionMarkup` (none / light / expressive)：規範訊息的表情符號與語氣詞使用頻率。

---

## 5. 系統功能介面 (Agent Tools Schema)

AI 可調用的工具清單，定義應精確對應以下功能：

- **Memo 管理工具**：
  - `createMemo(title, summary, content, translation, type, htmlContent, tags, todos, sourceUrls, attachLastScreenshot)`
  - `updateMemo(id, title, summary, content, translation, tags, todos, sourceUrls, attachLastScreenshot)`
  - `queryMemos(query, tags, limit)`：搜尋與過濾筆記，僅回傳 metadata digest 避免 Bloat Context。
  - `getMemoById(id)`：讀取完整筆記詳情。
  - `deleteMemo(id)`：刪除筆記（執行前須語音或文字向使用者確認）。
  - `loadMemoToPip(id, query)`：將 HTML 卡片重新載入至懸浮小窗中互動。
  - `exportMarkdownReport(title, memoIds)`：產生 Markdown 摘要報告。
- **螢幕視覺工具**：
  - `captureScreen(mode: 'full' | 'focus', purpose, x, y, width, height)`
- **畫中畫小窗工具**：
  - `showPipWindow(layout, html, message, options, showInput, inputPlaceholder, width, height, replace)`
  - `updatePipContent(html, replace)`
  - `hidePipWindow()`
- **記憶管理工具**：
  - `saveLongTermMemory(category, key, value, confidence)`
  - `saveShortTermMemory(topic, detail)`
  - `consolidateMemory()`
- **搜尋與自動附加工具**：
  - `googleSearch`
  - `postChatMessage`
  - `queryCourseMaterials`
