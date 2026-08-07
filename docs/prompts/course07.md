# Course 07－課堂用提示詞整理

來源：`class07/slides/slide.md`。

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

## 採購比價助手 RFP

```text
# 開發「AI 採購比價助手」
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
提供公司採購人員便利的詢價、比價工具，完成以下目標:
0. 使用者一開始需求一律在 Chat View 直接提出，用對話的方式說明比價目標。
1. 確定採購商品規格，可為單項或多項同時評估。
2. 協助制訂採購策略及方案。
3. 提供至少20個候選方案供比較評估。

## 使用環境
用於採購人員初起選商、比價、提案階段，協助採購完成遴選及提案，以供權責主管做最終決策。

## Agent Tool: googleSearch source priority
* Google Search
* B2B: Alibaba, 1688.com
* B2C: Amazon, Taoboo, Shopee, PCHome, Momo, etc...
* 其他大宗採購貨源，Agent 根據目的評估蒐尋對象

## Agent Tool: identifySpec, collectData, 
以下流程由 Agent 利用 Tooling 進行不同階段處理，最終彙整成 html5 格式報告。
1. 廣泛至多平台蒐集相關資訊。
2. 整理商品及廠商清單、價格、規格，規劃統一標準。
3. 分析與評估供應渠道可靠性、供貨風險評估。
4. 建立遴選標準，逐一比對廠商，並做出遴選通過與不通過評估。
5. 彙整情報，優先整理通過廠商排行，不通過廠商分為資格不符與超過預算兩類，至少尋找 20 ~ 50 件商品。
6. 從通過商品中提出三套為推薦方案，並提供綜合比較建議，剩餘非推薦方案也需要列出，並說明理由。
7. 評估超過預算廠商是否有遺珠廠商，可另提備選方案。
8. 將分析結果製作成互動式報告，產出報告應包含：
	1. 規格對齊檢查
	2. 價格與總成本估算
	3. 供應商可信度評分
	4. 前三名推薦與不推薦理由
	5. 資料來源、查詢時間與限制聲明

> Agent Tooling 應將每個階段的搜尋結果暫存本地端記憶體，並嘗試分多次搜尋，當商品有多頁面時，應至少深入調查五個頁面，並在最後合併成單一數據包做整合。
> 避免嘗試用一次的 token window 或 contenxt window 完成所有工作，而是定義完整專案結構，在調查過程持續補充資料，直到調查結束才彙整成最終報告。
> 
> 如果資料不足，請列出需要人工確認的問題，
> 不要自行假裝已取得報價。

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
4. 連結提供
* 涉及商品資訊時，應盡可能取得商品專屬頁面連結，確保報告上能連到原始商品資訊。
* 涉及廠商資訊時，應提供廠商連結，確保報告上可連到正確的廠商資訊。
* 不可以平台的首頁當作連結

## Agent 服務準則
1. 盡可能先問清楚需求、預算、時程、預期效果，待確定方向後，才開始搜尋資料。
2. 執行工具過程，若無法一次完成資料彙整，仍須利用已取得之資料，整理成階段性報告。
3. 應提供讓使用者得以合併各階段資料之機制，因此每次檢索結果，至少應在同一個 Session 中保存，以便 Agent 隨時調閱彙整。

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

## 問題範例

```text
公司預計在中秋節活動提供員工贈品，預計製作兩千份，預算 20 萬元。
目前預計製作客製化滑鼠墊，上面印製公司指定的圖案，滑鼠墊質感要好，並具備無線充電功能。
最晚必須在中秋節前兩週到貨，並且完成包裝。

請幫我尋找合適的供應商，並提供價格、規格、供貨能力、生產排程建議與運送方案等相關評估。
至少幫我找 20 家廠商，符合或不符合標準都要提出，從符合標準的廠商中挑出三家作為主要建議廠商。
另外從不符合標準當中，屬於超出預算者，若屬於高品質，或有特殊功能者，可以訂做備選方案。

請以國際級專業視覺平面設計師的標準來設計視覺，注重資訊溝通脈絡，視覺動線設計，將訊息重點加強，次要資訊弱化，方便舒服及高效地閱讀。
報告請以一頁式雜誌風格排版，白底黑及亮橘配色，利用黑體字標示重點，盡可能引用商品圖片，每個產品都要提供正確的商品頁面連結。
利用 script 功能，將資訊摘要，並把詳細資訊跟解說，利用收合或展開浮動視窗的方式呈現。
盡可能用豐富的圖表來輔助說明，利用 IconFont / emoji 等圖示來標示重點，讓資訊容易閱讀。
圖示以單色為主，避免過於卡通，因符合專業、穩重、高質感，剪紙疊合風格設計，用陰影來襯托卡片。
視覺框架應留較寬闊的邊界，讓訊息周邊有足夠的呼吸空間。
針對需要突出的重點，可做跳色、摺紙、陰影、不規則配置、旋轉等技巧來作點綴。
```