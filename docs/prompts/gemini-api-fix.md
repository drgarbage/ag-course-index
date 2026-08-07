# Gemini Agent 體檢

## Use SDK in real world
1. **No memory, check docs**：必須呼叫 `gemini-api-docs` MCP 的 `search_docs` 工具，或使用 `gemini-api-dev`, `gemini-live-api-dev` skill。
2. 遵守 SDK 規範：一律使用 `@google/genai`，嚴禁混用或引入舊版 `@google/generative-ai`。
3. 金鑰與運行環境：API 呼叫與長效金鑰必須置於 server-side/backend proxy。專案必須在 HTTP(S) 開發伺服器上啟動運行（如執行 `npm run dev` 啟動 `localhost`），網址協議必須為 `http://` 或 `https://`，完全排除 `file://` 直開。
4. 交付範圍：僅限修改任務所需的檔案範圍，保留無關程式。

---

## A. IME & Send Event

### 1. IME 防選字送出
```javascript
input.addEventListener('keydown', (e) => {
  if (e.key === 'Enter') {
    if (e.isComposing || e.keyCode === 229) {
      return; 
    }
    if (!e.shiftKey) {
      e.preventDefault(); 
      handleSend(); 
    }
  }
});
```

### 2. 輸入狀態流轉
- 送出事件觸發後，立即將 `input.value` 設為 `""`。
- 當處於 `loading === true` 時，必須將發送按鈕與輸入框設定 `disabled = true`。
- 送出前必須呼叫 `input.value.trim() === ""` 檢查，若為空則中斷送出。

### 3. Voice Input Fallback
- Never use microphone icon as a visual placeholder. Must implement mic permission request, state indicators (listening, error, retry), and text input fallback.

---

## B. Model Selection

### 1. No static model list, retrieve from SDK
```javascript
new GoogleGenAI({}).models.list();
```

### 2. Time Awareness
```javascript
const systemInstruction = `Current local time: ${new Date().toLocaleString()}`;
```

### 3. API Key validation (verify by listing models via SDK)
```javascript
async function validateApiKey(apiKey) {
  try {
    const ai = new GoogleGenAI({ apiKey });
    await ai.models.list();
    return true;
  } catch {
    return false;
  }
}
```

---

## C. Tool Combination (Gemini 2.x vs Gemini 3.x 通用處理)

### 1. Fix Gemini 2.x/3.x sdk tool bug
- 2.x no official tools + custom tools
- 3.x allow official tools + custom tools

```javascript
import { GoogleGenAI } from '@google/genai';
const ai = new GoogleGenAI({});

function adaptGenerateContent(options) {
  // call tools seperately
  // call official tools seperately
}

function withOfficial(options) {
  // append official tools
}

async function callGemini(
    modelName, userInput, 
    tools = [], enableSearch = false
  ) {

  const options = {
    model: modelName,
    contents: userInput,
    config: { tools }
  }

  return checkAllowToolCombine(modelName) ?
    await adaptGenerateContent(options) :
    await ai.model.generateContent(options);
}

### 2. System Instruction Tool Grounding
```javascript
const instruction = isSearchEnabled ? "" : "Tool google_search is disabled. Do not attempt to call it.";
```
```

---

## D. Tool Error Handling

### 1. 錯誤 `functionResponse` 格式
```json
{
  "functionResponse": {
    "name": "unknown_or_failed_tool",
    "response": {
      "error": "該工具不存在，或傳入參數不符合 schema 定義。請自我修正或改用其他方式。"
    }
  }
}
```

---

## E. History Schema

### 1. 對話歷史格式
- **欄位限制**：Gemini API 不存在 `functionCalls`（複數）欄位。每個 `functionCall` 必須是單數，且對應有 `functionResponse`。
- **歷史完整度**：優先將 SDK 的完整 model response 直接存入歷史。若手動序列化，必須保留正確角色（`user`/`model`）、順序、`toolCall`/`toolResponse`、`thought`（若有）與 server-side tool context。

---

## F. MCP & Skills Setup

### 1. 設定自檢
- 確認存在 `.agents/skills/gemini-api-dev/SKILL.md`，且 frontmatter 有正確的 `name` 與 `description`。
- 確認 `.agents/mcp_config.json` 包含 Docs MCP 設定：
  ```json
  {
    "mcpServers": {
      "gemini-api-docs": {
        "serverUrl": "https://gemini-api-docs-mcp.dev"
      }
    }
  }
  ```
- **MCP 斷線降級**：當 MCP 無法連線時，必須讀取本地的 `llms.txt` 或官方文件 fallback，並在結果中揭露降級，不得靜默依賴模型記憶。

---

## G. Error Handling & Rendering

### 1. 去敏錯誤 JSON 結構
```json
{
  "error": {
    "code": "API_LIMIT_EXCEEDED",
    "message": "API 呼叫次數已達上限",
    "suggested_action": "請稍後再試，或檢查您的帳單設定",
    "details": {
      "status": 429,
      "reason": "rate_limit_exceeded",
      "debug_info": "Token limit reached for current minute."
    }
  }
}
```

### 2. Markdown 與 XSS 防護渲染
```javascript
import { marked } from 'marked';
import DOMPurify from 'dompurify';

function renderSafetyMarkdown(rawMarkdown) {
  const rawHtml = marked.parse(rawMarkdown);
  return DOMPurify.sanitize(rawHtml, {
    ALLOWED_TAGS: ['p', 'br', 'strong', 'em', 'h1', 'h2', 'h3', 'code', 'pre', 'ul', 'ol', 'li', 'blockquote', 'a'],
    ALLOWED_ATTR: ['href', 'target']
  });
}
```

---

## H. UI & API Consistency

### 1. 排除 Mock/Stub 實作
- 交付代碼中禁止出現硬編碼的靜態回覆、模擬延時的 `setTimeout`、或在 `catch` 區塊中回傳預設成功資料。
- 未完成的功能必須在 UI 元素上設定 `disabled` 與 `style="display:none"`。
- 測試替身僅能存於 `tests/`，禁止進入 production 執行路徑。

---

## Output Format

### Verification Log
- Docs MCP / Skill Query Link: [e.g. search_docs query]
- Models: [e.g. gemini-2.5-flash]

### Checklist
| ID | Item | Result | Evidence |
| --- | --- | --- | --- |
| G1 | SDK / Tooling | PASS / FAIL / N/A | [code line or test screenshot link] |

### Code Changes
- `[file path]`: [description of change]

### Smoke Test Output
```text
[test execution logs]
```

### Remaining Risks
- [untested features, proxies, or "None"]

### Recurrence Protection
- [Describe protection mechanism: Rule / Hook / Test / Skill / "Not Needed" with reason]
