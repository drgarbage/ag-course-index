# 📄 API KEY 額度不足問題

## 一、 問題原因分析

明明沒什麼用過，但 API KEY 設定後，程式卻回傳**額度不足**的錯誤時，主因是：

> **新版 SDK (`@google/genai`) 對於「免費版 (Free Tier) API Key」的權限驗證與底層路由機制存在相容性問題**，導致系統在發送請求時，將免費金鑰的可用配額誤判為 0。

---

## 二、 免費版 vs. 付費版 建議配置對照表

請依學員使用的 **API Key 層級**，採用對應的套件與模型設定：

| 項目 | 🆓 免費版 (Free Tier) | 💳 付費版 (Paid Tier 1+) |
| --- | --- | --- |
| **建議 SDK 套件** | **舊版** `@google/generative-ai` | **新版** `@google/genai` |
| **建議模型** | `gemini-2.5-flash` | `gemini-3.5-flash` |
| **穩定度** | 修正新套件誤判問題，可穩定運作 | 支援完整新功能與高頻率呼叫 |
| **適用場景** | 學員免費課堂練習、個人小專案 | 正式上線專案、高頻率自動化與 AI Agent 串接 |

---

## 三、 學員設定提示詞 (可直接複製使用)

請學員將對應的提示詞複製貼給 AI 助手（如 Cursor、ChatGPT 或 Gemini）即可自動產生正確程式碼：

### 1. 🆓 免費版設定提示詞

```markdown
請幫我在專案中設定 Google Gemini API (免費版)。

需求規格如下：
1. 使用舊版官方套件：`npm install @google/generative-ai`
2. 採用免費層級 (Free Tier) 最相容的模型：`gemini-2.5-flash`
3. 語法要求：
   - 使用舊版 `GoogleGenerativeAI` 的初始化方式帶入 API Key (`process.env.GEMINI_API_KEY`)。
   - 透過 `getGenerativeModel({ model: "gemini-2.5-flash" })` 取得模型實例。
   - 撰寫非同步函式，接收使用者輸入的 Prompt 並回傳生成內容。
   - 包含完整的錯誤處理 (try/catch)。
```

---

### 2. 💳 付費版設定提示詞

```markdown
請幫我在專案中設定 Google Gemini API (付費版)。

需求規格如下：
1. 使用最新版官方套件：`npm install @google/genai`
2. 採用付費層級 (Tier 1+) 最佳化的模型：`gemini-3.5-flash`
3. 語法要求：
   - 使用新版 `GoogleGenAI` 物件初始化方式帶入 API Key (`process.env.GEMINI_API_KEY`)。
   - 呼叫 `ai.models.generateContent` 傳入 `model: "gemini-3.5-flash"`。
   - 撰寫非同步函式，接收使用者輸入的 Prompt 並回傳生成內容。
   - 包含完整的錯誤處理 (try/catch)。
```
