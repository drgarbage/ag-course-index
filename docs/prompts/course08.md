# Course 08－課堂用提示詞整理

來源：`class08/slides/slide.md`。

## 🛠️ 開發環境 Skill 安裝指引

本單元實作建議安裝以下 Agent Skills，以協助 AI 自動化開發與防止常見 SDK 錯誤：

* **gemini-agent-dev-support**: 防止常見 Gemini API 調用與金鑰洩漏錯誤
* **ai-agent-ui-support**: 規範 Agent 聊天介面
* **live-dev-init**: 預檢與環境初始化
* **live-dev-storage-init**: Firebase與Firestore資料庫配置 (若需要Firestore)
* **live-dev-config**: GitHub與Vercel專案配置與憑證安全收集
* **live-dev-deploy**: 本機自動測試、自癒與 Git Flow 部署發行

在你的專案根目錄下，開啟終端機並執行以下指令完成安裝：

```bash
# 專案本地安裝 (推薦)
npx skills add drgarbage/ag-course-index --skill gemini-agent-dev-support
npx skills add drgarbage/ag-course-index --skill ai-agent-ui-support
npx skills add drgarbage/ag-course-index --skill live-dev-init
npx skills add drgarbage/ag-course-index --skill live-dev-storage-init
npx skills add drgarbage/ag-course-index --skill live-dev-config
npx skills add drgarbage/ag-course-index --skill live-dev-deploy
npx skills add affaan-m/ECC --skill frontend-design-direction
```

---

## 數據分析與比較報表小幫手 RFP

```text
# 開發「數據分析與比較報表小幫手」
這是一個透過 AI 協助，在 iframe 沙盒動態繪製 html5 任意報告的工具

## 軟體介面
整體採用 RWD 設計，包括 Navigation Bar, Side Menu, Main View, Chat View (right)。
當使用手機檢視時，以 Main View 為主，其他介面透過選單或FAB做切換開關。
使用白色介面設計，舒適乾淨，紙張陰影風格。在報告呈現區域，模擬紙張效果，紙張背後採用深灰色背景區分。
支援全螢幕檢視，採用全螢幕檢視時，以報告內容為主體滿版呈現，在桌面呈現時，仍以占滿完整寬度的形式呈現報告，以利作簡報報告之用。

### Dashboard View
顯示近期報告列表，以文件卡片的形式呈現，並提供建立新報告的按鈕。

### Report Manager View
列表所有已經儲存的報告，可以搜尋、列表、更名、刪除、開啟報告。

### Report View / Editor
報告檢視畫面，提供不同版本的顯示切換介面，報告預覽模式，全螢幕預覽，以及編輯模式，在編輯模式下，使用者可以選取框選區塊，輸入提示詞要求AI局部修改。

### Chat View
與Agent對話介面，放置於右下角，可收闔。

## 需求與目標對象
提供公司資料分析或管理人員進行資料調查、分析、比對、判讀並生成相應報告
0. 使用者一開始需求一律在 Chat View 直接提出，用對話的方式說明比價目標
1. 從使用者提供的文件數據，或指定的資料庫中查詢資料。
2. 根據使用者的目的將數據彙整成報告。
3. 利用 D3.js 等圖表工具來視覺化呈現數據資料。

## 使用環境
用於任何同時具備多樣數據，需引入不同專業知識進行分析的情況。

## Agent Tool: googleSearch
使用者可以要求 Agent 自行蒐集公開資訊，或 Agent 可以根據情況需要，透過網路尋找補充數據來完成所需報告

## Agent Tool: db related tools

串接已經預先部署好、內含真實銷售數據的公開 PostgREST API：

- 公開 API 網址：`https://gemini.printii.com/northwind/api`
- pgAdmin 4 網址：`https://gemini.printii.com/northwind/pgadmin/` (帳號：admin@example.com / 密碼：admin)

為了讓你了解這個資料庫的表結構與欄位，請你在開始編寫代碼前，**先使用你自備的程式碼執行環境（如 Python 沙盒）、HTTP 請求工具或搜尋工具**，連線並發送 GET 請求到以下端點以萃取並分析資料庫的架構與關聯資訊：

* `https://gemini.printii.com/northwind/api/analysis_tables?order=table_name.asc` (獲取所有資料表與分析 View 清單)
* `https://gemini.printii.com/northwind/api/analysis_relationships` (獲取表與表之間的 JOIN 關聯鍵定義)

## Agent Tool: generateHtmlReport
報告內容不預先制定介面，而是以 html 沙盒形式呈現，讓 AI Agent 可以自由撰寫網頁內容，以達成以下目標:
1. 應符合 RWD 訊息呈現格式
2. 採用世界頂尖 UI/UX 設計標準，做排版設計
* 利用 Material Design，Card View 以及商業雜誌排版等技術規劃視覺
* 利用 emoji、IconFont、插圖、顏色區別、字體大小等方式標示重點
* 將資訊內容分為主要與次要內容，讓閱讀者一眼看到主要重點，次要內容降低視覺比重
* 將資訊分為摘要跟詳細內容，詳細的訊息利用 script 機制，透過摺疊、跳出提示、視窗、或連結到後方補充資料等方式來補充呈現。
3. Script 應用
* 針對可調整數值，預算金額，等動態資訊可提供調整介面，讓使用者及時調整比對結果
* 提供用戶手動選擇比較對象，並動態呈現於比較表中
4. 佐證連結提供
* 涉及佐證資訊時，應盡可能取得資料來源頁面連結，確保報告上能連到原始資訊。
* 不可以平台的首頁當作佐證連結

## Agent 服務準則
1. 執行工具過程，若無法一次完成資料彙整，仍須利用已取得之資料，整理成階段性報告。
2. 應提供讓使用者得以合併各階段資料之機制，因此每次檢索結果，至少應在同一個 Session 中保存，以便 Agent 隨時調閱彙整。
3. **多輪歷史與工具上下文**：在維護對話歷史時，必須保留完整的 model response 序列與 tool-call/response 關聯（包含 correct role, sequencing, tool call parameters, call IDs, and thought signatures），不得自行把工具調用過程簡化或壓縮成自訂文字，且不得使用不存在的 plural `functionCalls` parts。
4. **系統提示詞 (System Instruction)**：
  - 告知內置 AI 助理它是一位頂尖的資料數據分析專家，具有處理資料庫 SQL、使用者上傳的自訂檔案（文字資料、CSV/Excel 數據）以及圖片的多維度整合分析能力。
  - 當用戶詢問數據問題時，AI 必須靈活調用你實作的 Tools 來查詢資料庫，並將資料庫的查詢結果與使用者提供的自訂數據檔案進行交叉比對與深入分析。
  - 告知 AI 助理它具有網路搜尋的能力，當它需要尋找外部實時市場數據、行業背景資訊、或是尋找論點與分析佐證時，應主動呼叫 Google Search 工具上網檢索數據。
  - AI 必須在最終回覆中產生一個格式完整的 HTML 程式碼區塊（包在 ``html ... `` 中）。該 HTML 必須包含漂亮的現代化 CSS 樣式，並引入 Chart.js 畫出直觀的視覺化圖表，並將此區塊提取出來更新至右側的沙盒。
  - 憑證安全與主動引導：程式碼與系統提示詞中嚴禁寫死任何真實的 API Key。當 AI 助理檢測到系統中尚未設定 API Key，或是因為缺乏憑證而無法順利執行時，應在對話中主動且友善地提示或詢問用戶，並引導其點擊頂部的「API 設定按鈕」進行憑證與 API Endpoint 的配置。

## 列印格式
報告應提供便於列印之格式，並可利用列印成PDF文件功能，下載為PDF文件

### MSUT apply following Skills
本案應利用以下 skill 協助用戶以正確的 gemini sdk 版本，搭配 Vercel 服務開發。
開發過程由 Agent 全自動處理 git flow 版控、preview / production 佈署，直接透過公開網路驗證成果。
/gemini-agent-dev-support
/ai-agent-ui-support
/live-dev-init
/live-dev-storage-init
/live-dev-config
/live-dev-deploy
/frontend-design-direction
```

---

## 固定月報表（魚）

```text
製作一個整理月報表的網頁。
```

## 通用數據分析 Agent（釣竿）

```text
製作一個協助分析資料的 Agent，提供他搜尋、讀取、彙整資料庫的能力，
根據需求從 ERP 資料中調取數據並製作分析報表。
```

## 探索 ERP 分析案例

```text
如果對 ERP 內的數據作分析，有甚麼類型的分析可以做?
請舉出十個案例。

[可以的話提供 Schema 讓 AI 參考...]
```

## 規劃 Tool Functions

```text
根據這十個案例，我希望設計必要的查詢工具給 Agent 使用，
其中包括通用的查詢功能，能以唯讀的方式執行複雜的 SQL 指令，
另外也提供常用的彙整、分群、統計的函式，方便 Agent 組合運用，
請你提供建議的 Tool Function 規劃。
```

## 數據分析 Agent System Prompt

```text
你是一位營運數據分析助理。
你可以先探索資料表與欄位，再依照使用者的問題選擇 shortcut 工具或唯讀 SQL。
分析完成後，請生成 HTML + Chart.js 或 D3.js 報告。
報告需要包含資料來源、generatedAt、關鍵洞察與圖表。
```

## 建立數據分析 Agent App

```text
請幫我建立一個數據分析 Agent App。

需求：
1. 左側保留報告清單，可以切換不同版本的報告。
2. 右側用 iframe 顯示 Agent 生成的 HTML 報告。
3. Agent 需要有資料庫探索工具：listTables、describeTable、listRelationships、previewTable。
4. Agent 需要有唯讀 SQL 工具：runReadOnlySql，只允許 SELECT 或 WITH ... SELECT。
5. Agent 需要有常用分析工具：商品貢獻、客戶價值、地理銷售、業務績效、物流履約。
6. 報告輸出工具要能把 HTML 顯示在右側面板，並支援重新載入、全螢幕、列印或 PDF。

請先提出實作計畫，再開始修改程式。
```

## 案例問題

```text
請提供顧客貢獻度分析報表
```

```text
資料庫中最新的數據年份 19xx 實際上是 2026 年的數據。你是一位全球貿易專家，也是一家國際貿易公司經驗豐富的總經理，請分析 Northwind（北風貿易）的年度業績與庫存狀況，並提出你的洞察，以指出目前的瓶頸與弱點，並評估即將到來的 2027 年的機會。此外，請提供 SWOT 分析以及市場成長預估。

作為我們的新任 CEO，請提供一份詳細的 10 頁報告，以說明你對過去狀況的檢視，以及下一季的新策略。
```

```text
請以世界頂尖的網路行銷專家的標準，針對 heartlink.com.tw 的 SEO 數據報告，提供以下分析報告:
1. 透過 meta data 取得業者相關資運
2. 評估過去 SEO 規劃狀況優劣
3. 指出規劃缺陷或問題
目標是增加自然瀏覽量及轉換率，請提供短中長期改進，以及如何做關鍵字或社群廣告配套行銷等建議
```
