# Course 02－課堂用提示詞整理

來源：`class02/slides/slide.md`，並保留本檔原有的課堂提示詞。

## 新聞報導小幫手

```markdown
幫我開發一個輔助撰寫新聞報導的 AI Agent
- AI Chat View: 跟用戶討論文章主題, 風格
- Article View: 顯示文章，包含大標題，副標題，內文
```

## Web AI Agent

```markdown
請根據以下規格開發 Web AI Agent

# Web AI Agent
整合 Gemini API 開發一個對話式 AI Agent 介面，包含以下功能:

1. App Layout
  - 介面包含 Main View 跟 Chat View 兩個部分
  - Main View 用來呈現使用者跟AI互動得成果，由Agent決定要放甚麼內容到Main View當中。
  - Agent 可以利用 html 的機制來即時繪製跟修改 Main View 的內容。
  - Chat View 採浮動式，可開關的方式設計，關閉時已浮動按鈕的形式常駐在畫面右下角。
  - 介面應支援 RWD 顯示，在畫面寬度充裕時，應盡量利用完整的視窗顯示範圍。當寬度不足時，應確保資訊能可正確呈現，避免因為寬度不足而導致排版錯位等問題。
2. Agent 能力
  - 提供文字對話詢問服務
  - 顯示使用者與AI的對話訊息內容
  - 訊息 Bubble 顯示應支援 markdown 呈現
  - 啟用 Google Search 能力
3. Setting View
  - 提供API KEY設定介面
  - 在API KEY設定時，透過API取得可用模型清單
  - 提供 System Prompt 設定介面，讓使用者可以隨時更換系統提示詞

這個 Agent 是用來作為後續加入其他功能的基礎，因此在設計上應保留能力擴充的彈性。
```
