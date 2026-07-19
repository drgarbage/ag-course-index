# Course 08－課堂用提示詞整理

來源：`class08/slides/slide.md`。

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
