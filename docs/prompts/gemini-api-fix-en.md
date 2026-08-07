# Gemini Agent Pre-Delivery Audit

## Use SDK in real world
1. **No memory, check docs**：Must call `gemini-api-docs` MCP `search_docs` or use `gemini-api-dev`, `gemini-live-api-dev` skill.
2. **SDK Rule**: Always use `@google/genai`, never import or mix with legacy `@google/generative-ai`.
3. **Environment & Origin**: API calls & credentials must live on server-side/backend proxy. Web app must run on local dev server (e.g. `npm run dev` starting `localhost`). No `file://` protocol.
4. **Scope Check**: Modify only file scope relevant to current task. Keep unrelated code intact.

---

## A. IME & Send Event

### 1. Prevent Enter send on IME composing
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

### 2. Input element state transition
- Clear `input.value` immediately after sending.
- Disable input element and send button during `loading === true`.
- Prevent sending if `input.value.trim() === ""`.

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

## C. Tool Combination (Gemini 2.x vs Gemini 3.x)

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

### 1. Error `functionResponse` Schema
```json
{
  "functionResponse": {
    "name": "unknown_or_failed_tool",
    "response": {
      "error": "Tool unknown or parameter validation failed. Please auto-correct."
    }
  }
}
```

---

## E. History Schema
- No plural `functionCalls` field. Ensure single `functionCall` mapped with a `functionResponse`.
- Preserve `thought`, `signature` (under interactions context) and server-side tool context in history loop.

---

## F. MCP & Skills Setup
- Ensure `.agents/skills/gemini-api-dev/SKILL.md` exists.
- Ensure `.agents/mcp_config.json` includes Docs MCP:
  ```json
  {
    "mcpServers": {
      "gemini-api-docs": {
        "serverUrl": "https://gemini-api-docs-mcp.dev"
      }
    }
  }
  ```
- Fallback to `llms.txt` or docs when MCP disconnected.

---

## G. Error Handling & Rendering

### 1. Desensitized Error Schema
```json
{
  "error": {
    "code": "API_LIMIT_EXCEEDED",
    "message": "Friendly error summary in Traditional Chinese.",
    "details": {
      "status": 429,
      "reason": "rate_limit_exceeded",
      "debug_info": "Debug trace without credentials."
    }
  }
}
```

### 2. Purify HTML from Markdown parser (prevent XSS)
```javascript
import { marked } from 'marked';
import DOMPurify from 'dompurify';

const safetyHtml = DOMPurify.sanitize(marked.parse(markdown));
```

---

## H. UI & API Consistency
- No mock responses, placeholder static data, simulated loading time (`setTimeout`), or fake catch block success fallbacks in production path.
- Non-functional UI features must be explicitly `disabled` or set to `display: none`.
- Mocks/Stubs are restricted to `tests/` directory.

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
