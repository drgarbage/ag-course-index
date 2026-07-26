# 露營租賃小編與商品 CSV 資料來源實作計畫

本計畫目標為建置一個露營裝備租賃服務 `http://gears.tw` 的客服小編 Agent。該 Agent 具備即時商品資料查詢能力，支援由使用者在設定面板填入 Google Sheet CSV 連結並快取，且當客人需要預約時，能提示 Line 預約（ID: `@gears.tw`）並提供好複製的預約清單。

## 使用者 review 偏好確認
依據先前的對談，我們已對齊以下設計：
1. **同步機制**：在 Sidebar 提供「同步商品資料」按鈕。點擊後從 CSV 網址下載並快取在 localStorage 中。此外，每次開啟網頁時，如果已經設定網址，將在背景自動嘗試同步一次。
2. **AI 資料查詢**：實作 Gemini 的 Function Calling (Tool) 機制，讓 Gemini 在需要商品資訊時才呼叫 Tool `queryProducts` 查詢庫存與價格，不盲目瞎編。
3. **預約格式與管道**：當預約時引導至 Line 官方帳號 `@gears.tw`，並提供包含「租借人姓名、聯絡電話、租借日期與天數、租借裝備清單、預估租金與押金」的好複製 Markdown 格式。

---

## 預計修改與新增內容

### 1. 資料結構與 CSV 解析器
- 定義商品資料介面 `Product`：
  ```typescript
  export interface Product {
    category: string;     // 商品類別
    id: string;           // 商品編號
    brand: string;        // 品牌
    name: string;         // 品名
    weight: string;       // 重量
    rent1: string;        // 兩天一夜租金
    rent2: string;        // 續租日租金
    deposit: string;      // 押金
    status: string;       // 上架狀態
    rentStatus: string;   // 出租中 / 歸還日
    reservation: string;  // 預約
    details: { [key: string]: string }; // 其他特規 (如帳篷容量、背包背長、睡袋極限溫度等)
  }
  ```
- 實作簡易的 CSV 解析器，支援雙引號括起來的欄位（如 `"$1,000"`，避免因為逗號造成解析錯位）。並過濾掉 Google Sheet CSV 匯出的第一行（商品資料彙總清單）。

### 2. Sidebar 設定面板修改
- **新增輸入欄位**：`商品資料 CSV 網址 (Google Sheet CSV)`。
- **新增同步按鈕**：點擊後觸發 `fetch` 並解析 CSV，更新 `localStorage` 與 React state。
- **顯示狀態**：若已同步，顯示 `🟢 已同步 XX 筆商品 (更新時間)`。
- **背景同步**：在網頁載入時（`useEffect`）自動在背景同步一次。

### 3. GeminiService 支援 Function Calling
- 定義 `queryProducts` 函數宣告：
  ```json
  {
    "name": "queryProducts",
    "description": "查詢露營裝備租賃商品的詳細規格、租金、押金與目前狀態（已上架、送洗、破損等）。",
    "parameters": {
      "type": "OBJECT",
      "properties": {
        "category": { "type": "STRING", "description": "商品類別，如：輕量化帳篷、輕量化背包、輕量化睡袋、其他裝備 (選填)" },
        "keyword": { "type": "STRING", "description": "品名或品牌的關鍵字 (選填)" }
      }
    }
  }
  ```
- 在 `streamGeminiChat` 中加入 Function Calling 處理迴圈。若收到模型傳來的 `functionCall`，在前端尋找快取的商品資料，執行篩選，並將 `functionResponse` 回傳給 API 再進行後續的 generateContent。這對對話框的呼叫是透明的。
- 更新預設的 `DEFAULT_SYSTEM_PROMPT` 以符合 gears.tw 貼心露營客服小編的角色。

---

## Proposed Changes

### [Web AI Agent Front-end]

#### [MODIFY] [types/index.ts](file:///Users/ckny/Documents/02.Projects/ai-class-examples/ag-course-web-agent-base/src/types/index.ts)
- 新增 `Product` 介面定義。
- 在 `Settings` 介面中新增 `csvUrl` 和 `productsJson`（或在 App state 中獨立處理）。

#### [MODIFY] [services/GeminiService.ts](file:///Users/ckny/Documents/02.Projects/ai-class-examples/ag-course-web-agent-base/src/services/GeminiService.ts)
- 實作 `queryProducts` 的 Tool 定義。
- 在 `streamGeminiChat` 中，使用迴圈（例如 `while (true)`）處理 `functionCalls`。
- 如果模型傳回 `functionCall`，在 local 執行資料庫檢索（讀取當前的商品資料 JSON），然後回傳 `functionResponse` role 的訊息並繼續 stream 生成。

#### [MODIFY] [App.tsx](file:///Users/ckny/Documents/02.Projects/ai-class-examples/ag-course-web-agent-base/src/App.tsx)
- 更新 `DEFAULT_SYSTEM_PROMPT` 為露營裝備客服小編。
- 管理 `csvUrl` 和快取的 `products` 的 state 與 localStorage 同步。
- 傳遞這些屬性給 `Sidebar`。
- 在 `streamGeminiChat` 呼叫中，除了原有的 arguments，還需要傳入目前的商品快取資料，供 Function Call 調用。
- 在 `useEffect` 加入載入時自動背景同步的邏輯。

#### [MODIFY] [components/Sidebar.tsx](file:///Users/ckny/Documents/02.Projects/ai-class-examples/ag-course-web-agent-base/src/components/Sidebar.tsx)
- 在介面上增加商品資料來源輸入框與「同步商品資料」按鈕。
- 顯示同步狀態（幾筆商品，什麼時候更新的）。
- 實作 fetch CSV 與 parser 邏輯。

---

## Verification Plan

### Manual Verification
1. 啟動本機開發伺服器 `npm run dev`。
2. 開啟 `http://localhost:5173`。
3. 在設定面板填入 Google Sheet CSV URL: `https://docs.google.com/spreadsheets/d/e/2PACX-1vRshojqbRnT4QAMdMg-JlyaG969mUcNtP9Q_iV2nXETyIca8Sek0UhfunjM_BSR9Q/pub?output=csv`。
4. 點擊「同步商品資料」，確認是否成功顯示「🟢 已同步 34 筆商品」。
5. 與 AI 進行對話測試：
   - 問：「請問你們有什麼輕量化帳篷可以租？租金是多少？」 -> 確認 AI 是否呼叫 Tool `queryProducts` 並正確列出藍山PRO2、The Two 等帳篷及其價格。
   - 問：「Durston X-Mid 2 輕量雙人帳現在可以租嗎？」 -> 確認 AI 能回答其目前狀態為「破損」（非「已上架」）而不能租借。
   - 問：「我想預約 UT001 藍山雙人帳和 UB005 背包，預計 8/1~8/2 兩天一夜。」 -> 確認 AI 是否提示使用 Line 官方帳號（ID: @gears.tw），並整理好格式化的複製區塊。
