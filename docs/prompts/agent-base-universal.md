# Universal Agent Rules

## Use SDK in real world
1. **Scope Check**: Only modify file scope relevant to the task. Keep unrelated code intact.
2. **Local Server Only**: Web app must run on local dev server (e.g. `npm run dev` starting `localhost`). No `file://` protocol.
3. **Credentials Policy**: Keep API keys and credentials on server-side/backend proxy. Never expose credentials in client-side code.
4. **Validation Loop**: Always run lint, typecheck, build, and automated tests after modifications.

---

## A. IME & Send Event

### 1. Prevent Enter send on IME composing
```javascript
input.addEventListener('keydown', (e) => {
  if (e.key === 'Enter') {
    if (e.isComposing || e.keyCode === 229) return;
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
openaiClient.models.list();
```

### 2. API Key validation
```javascript
if (!apiKey || apiKey.trim() === "") return false;
```

---

## C. Error Handling & Rendering

### 1. Desensitized Error Schema
```json
{
  "error": {
    "code": "API_LIMIT_EXCEEDED",
    "message": "Friendly error summary in Traditional Chinese.",
    "details": {
      "status": 429,
      "reason": "rate_limit_exceeded",
      "debug_info": "Debug stack trace without API keys."
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

## D. UI & API Consistency
- No mock responses, placeholder static data, simulated loading time (`setTimeout`), or fake catch block success fallbacks in production path.
- Non-functional UI features must be explicitly `disabled` or set to `display: none`.
- Mocks/Stubs are restricted to `tests/` directory.

---

## E. Tooling & Loop Limit
- Never throw directly on tool execution error or unknown tool name. Return structured error response:
```json
{
  "tool_outputs": [
    {
      "tool_call_id": "call_abc123",
      "output": {
        "error": "Error message for model auto-correction."
      }
    }
  ]
}
```
- Multi-turn tool calling loops must have a hard limit (max 5-10 iterations).

---

## Output Format

### Verification Log
- Test environment: [e.g. Chrome, localhost]

### Checklist
| ID | Item | Result | Evidence |
| --- | --- | --- | --- |
| U1 | IME / Inputs | PASS / FAIL / N/A | [code line or test screenshot link] |

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
