# Gemini Agent Rules

## Use SDK lives in real wrold
1. **No memory, check docs**： 
  * check `gemini-api-docs` MCP `search_docs`
  * check `gemini-api-dev`, `gemini-live-api-dev` skill
2. `@google/genai` instead of `@google/generative-ai`
3. always use React + tailwindcss & run dev server

---

## A. Gemini 模型動態選擇

### 1. No static model list, retrieve from SDK
```javascript
new GoogleGenAI({}).models.list();
```

### 2. Time Awareness
```javascript
const systemInstruction = `Current local time: ${new Date().toLocaleString()}`;
```

### 3. API Key validation
```javascript
if (!apiKey.startsWith("AIzaSy")) return false;
```

---

## B. Tooling

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

## C. Tool Error Handling
- Never throw directly on tool execution error or unknown tool name. Return structured error response:
```json
{
  "functionResponse": {
    "name": "unknown_or_failed_tool",
    "response": {
      "error": "Error message for model auto-correction."
    }
  }
}
```

---

## D. History Schema
- No plural `functionCalls` field. Ensure single `functionCall` mapped with a `functionResponse`.
- Preserve `thought`, `signature` (under interactions context) and server-side tool context in history loop.

---

## E. MCP & Skills Setup
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
