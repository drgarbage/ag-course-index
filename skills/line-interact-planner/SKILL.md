---
name: line-interact-planner
description: 當要評估整個 LINE 機器人的對話架構、或某個功能該不該做成固定指令而不是每次都丟給 Gemini 理解時使用這個 skill，目標是把重複、固定流程的需求收斂成指令，減少不必要的 AI 呼叫與 token 消耗。使用者沒有明確指定做法時，也要主動判斷並提出建議。
---

# LINE 互動流程規劃師

你的任務是幫整個機器人「省 token、省呼叫次數」：把可以用固定邏輯處理的流程，從「每次都靠 Gemini 理解 + Function Calling」搬到「程式直接判斷、不經過 AI」。

## 為什麼要這樣做

`lib/gemini.js` 的 `chat()` 每次呼叫都要：
1. 帶入該使用者累積的對話歷史（`sessions` Map）
2. 送整段 system instruction
3. 等 Gemini 生成回覆

這對「開放式問答」是必要的，但對「使用者說 A 就一定要做 B」這種固定流程來說是浪費——同樣的意圖每次都重新用 LLM 理解一次，既慢又貴。

## 判斷一個流程該不該「升級」成指令

符合以下大多數條件，就該從對話式改成明確指令：
- **高頻**：使用者常做的操作
- **決定性**：同樣的輸入，永遠對應同樣的處理邏輯，沒有語意模糊空間
- **參數少且固定**：不需要 AI 從自然語言裡「抽取」很多變動欄位（如果需要抽取變動欄位，可以只用 Gemini 做「一次性的意圖分類/抽取」，而不是走完整多輪對話+工具呼叫）
- **原本每次都要吃一輪完整的 Gemini 呼叫（甚至 Function Calling 多輪）才能完成**

反之，開放式、需要推理、每次輸入差異很大的需求（例如自由問答、需要結合上下文脈絡才能理解的請求），維持交給 Gemini 處理，不要硬做成指令。

## 實作模式

參考 [`server.js`](../../../server.js) 目前的 `handleTextMessage`：

```js
async function handleTextMessage(event, userId) {
  const userMessage = event.message.text.trim();
  if (!userMessage) return;

  if (userMessage === '/說明' || userMessage === '/help') {
    return reply(event.replyToken, [msg.textMessage(helpText())], userId);
  }

  const answer = await chat(userId, userMessage); // 其餘一律交給 Gemini
  await reply(event.replyToken, [msg.textMessage(answer)], userId);
}
```

新增指令的做法：
1. 在文字訊息一開始先做**指令分流**（比對固定字串，或用簡單的 `startsWith('/')` + 白名單），命中就直接呼叫對應的處理函式，**完全不經過 `chat()`**。
2. 指令的處理邏輯直接讀寫資料、組回覆訊息，不需要 Gemini 介入。
3. 只有真的需要從自由文字裡抽取結構化欄位時，才呼叫 Gemini（可以是輕量的單輪 `generateContent` 呼叫，而不是完整帶歷史的對話），並盡量把抽取結果快取/複用。
4. 隨著指令變多，把分流邏輯整理成一個 `parseCommand()` / `handleCommand()` 的 dispatch 表（可以參考同系列進階範例專案 `ag-course-line-chatbot-assistant` 的 `server.js` 寫法），方便未來擴充。

## 引導使用者用指令

光是「做出指令」還不夠，還要讓使用者「習慣用指令」，才能真的省到 token：
- 在 Gemini 的自然語言回覆之後，適時附上相關指令的 Quick Reply（讓使用者下次直接點，而不是重新打一長串話讓 AI 重新理解）。
- 常用指令務必也出現在圖文選單裡（見 `line-command-designer`），降低使用者要「記住指令」的門檻。
- system instruction／說明文字裡可以提示 Gemini：當偵測到使用者的意圖其實對應到某個既有指令時，直接在回覆裡建議對方之後可以用該指令。

## 主動建議原則

使用者描述一個新功能、但沒說「要不要做成指令」時：
1. 依上面的判斷準則自行評估這個流程屬於「固定流程」還是「開放式對話」。
2. 若判斷該做成指令，直接照上面的實作模式加進 `server.js`（或抽出的 dispatch 模組），並在完成後跟使用者說明「這個我做成 `/xxx` 指令了，這樣以後不用每次都重新問 AI，比較省」。
3. 若判斷該保留給 Gemini 處理，也简短說明原因（例如「這個需要理解上下文語意，交給 AI 比較合適」），不用另外詢問使用者。
