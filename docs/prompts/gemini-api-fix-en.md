# Gemini / AI Agent Course Example Self-Audit Prompt

This prompt consolidates issues previously found in the course examples. Paste the complete prompt into an AI agent before adding features, modifying Gemini API integrations, migrating examples, or delivering a project. It is an audit framework, not a source of permanent API facts. SDKs, models, and API schemas must always be verified against current official documentation.

## AI Agent Self-Audit Prompt

````markdown
# Gemini / AI Agent Course Example Pre-Delivery Audit

Act as the senior maintainer of this project. Perform a four-stage audit of the current changes: **verify, inspect, fix, and validate**. Do not merely read the code and provide verbal assurances. Do not treat historical fixes in this checklist as current API specifications.

## Working Principles

1. Read the target project's `AGENTS.md` or platform rules, relevant source files, package manifests and lockfiles, configuration, and existing tests. Determine the actual SDK and version in use. If no rules file exists, record the gap but continue the audit.
2. Gemini models, SDKs, APIs, tool fields, and limitations change over time. Consult the latest official Google Gemini API documentation before deciding on an implementation. Report the official links and verification date. Never guess model names or fields from model memory.
3. Preserve unrelated user changes. Modify only what is required for this task. Record additional findings as risks instead of expanding scope indefinitely.
4. Report the findings and intended fixes first, implement the smallest complete correction, and then run all available lint, type-check, build, unit, integration, and E2E checks.

## A. SDK, Models, and Request Sources

- [ ] Does the JavaScript or TypeScript project use the current `@google/genai` SDK? New and updated features must not install, import, or load the legacy `@google/generative-ai` package through a CDN. Inspect `package.json`, lockfiles, static and dynamic imports, import maps, CDN URLs, and documentation examples.
- [ ] If the target intentionally preserves an isolated, unmigrated legacy course example, is `@google/generative-ai` used only with the Gemini 2.x model explicitly verified for that lesson? It must not be connected to Gemini 3.x or newer models or receive new features. Mark it as legacy, pin the package and model versions, isolate it from current examples, and provide a migration plan to `@google/genai`. Otherwise mark this item FAIL.
- [ ] Does every Web App using `@google/genai` run through an HTTP(S) server? Development and classroom examples must provide a reproducible dev-server command, such as the project's existing `npm run dev`. A page opened by double-clicking `index.html` under `file://` must not be a supported launch mode, and the project must not maintain a separate CDN or inline implementation for it. Validate SDK requests, ES modules, CORS, Secure Context, routing, and asset loading under a real HTTP(S) origin.
- [ ] In production, are Gemini calls and long-lived API keys kept in server-side code or a backend proxy? Browser initialization being technically possible does not permit compiling or hard-coding production keys into the frontend. A browser-only classroom example must be labeled local learning only, explain the risk, use restricted or short-lived credentials when applicable, and still run through a localhost dev server.
- [ ] Is the model selector populated through the SDK or Models API and filtered by capability instead of using a hard-coded list presented as current? If a lesson intentionally pins one model, is it clearly labeled as a course compatibility setting?
- [ ] Do model IDs, endpoints, HTTP methods, request casing, and types match the current SDK or REST schema? Do not paste `snake_case` fields from REST errors into a `camelCase` SDK configuration.
- [ ] Are API keys and virtual keys obtained only through approved secret configuration, with no exposure in source code, logs, error UI, or test snapshots?

## B. Input and Chat UI

- [ ] Is the input cleared after a successful send? Are blank input, duplicate sends, loading state, and `Shift+Enter` handled correctly?
- [ ] Does IME handling guard `event.isComposing`, application composition state, and `keyCode === 229`? Test normal Enter and Chinese or Japanese candidate-confirmation Enter in macOS Chrome and Safari when available. Do not rely only on `setTimeout(..., 0)`.
- [ ] If voice input is required, is permission and recognition or recording genuinely implemented? Are listening, stop, error, and retry states visible? Are HTTPS/localhost restrictions documented, with text input retained as the unsupported-browser fallback? A microphone icon alone is not an implementation.

## C. Error Handling and Content Rendering

- [ ] Do overload/503, API-key/400, 401/403, quota/429, network, and unknown errors provide a friendly Traditional Chinese summary and an actionable next step?
- [ ] Can users expand a redacted raw error? Is content escaped or sanitized before insertion into HTML to prevent XSS and secret disclosure? Prefer structured status, code, and error details over fragile English keyword matching.
- [ ] Is Markdown genuinely parsed and visibly styled for headings, lists, quotes, links, inline code, and code blocks? If Tailwind `prose` is used, is the Typography plugin or CSS actually loaded? Is generated HTML sanitized?

## D. UI and API Behavior Consistency

- [ ] Enumerate Web Search, model selection, voice, and tool controls. Trace each control to the request payload or real handler and prove it is not a UI-only switch.
- [ ] Are mock, placeholder, and demo-only implementations completely absent from product and course deliverables? Search for hard-coded responses, fake data, random results, `setTimeout`-based fake loading, always-successful stubs, handlers that never call the real API or tool, TODO buttons, and fallbacks that turn failures into fake successes. Disable and label incomplete features instead of presenting them as working.
- [ ] Test mocks, fakes, and stubs may exist only in tests or explicitly labeled development fixtures. They must not enter production builds, production routes, or default course output. At least one integration or E2E path must validate real SDK, API, and tool wiring. Mock-only tests do not prove completion.
- [ ] Validate behavior using observable evidence such as request payloads, mock assertions in tests, API response metadata, or E2E results. If browser cache could hide a fix, use the normal development server and build cache invalidation, and confirm that the browser loaded the new asset.
- [ ] Do README and course instructions provide only a server-based launch flow that works from a fresh clone? Search for instructions to double-click `index.html`, open HTML directly, support `file://`, or load a CDN SDK specifically for direct-open mode. Remove or revise them unless this is an explicitly verified special runtime such as Electron.

## E. Google Search and Custom Tools

- [ ] If the course requires Search and Custom Tools to be always available, does every request declare both capabilities and let the model decide which to use instead of guessing from frontend keywords? Are retained legacy UI fields labeled compatibility-only?
- [ ] When Generate Content combines a server-side built-in tool with client-side function calling, does the request enable server-side tool invocation according to current official documentation? Confirm `camelCase` through `@google/genai` types and use the REST JSON schema for REST. Do not mix them.
- [ ] Does the tool flow form a complete loop: receive function call, validate name and arguments, execute handler, return the matching function response, and obtain the final model answer? Handle unknown tools, execution failures, parallel and sequential calls, and a maximum loop count.

## F. Multi-Turn History and Tool Context

- [ ] Do not use a nonexistent plural `functionCalls` part or compress the tool process into display text. Verify that every `functionCall` has a name and arguments and a matching `functionResponse` or call ID.
- [ ] Prefer adding the SDK's complete model response to history or using official server-side continuation. Manual reconstruction must preserve the current API's roles, order, tool calls and responses, thought signatures, and server-side tool context. UI messages alone are insufficient.
- [ ] Add a multi-turn tool test: call a tool and answer in turn one, reference that result in turn two, then reload or restore the history and ask again. Confirm the behavior is not accidental success on one model and one happy path.
- [ ] If a legacy SDK `startChat` session is used, test memory across models. Do not treat an old observation that only one model worked as a permanent specification. Use an officially supported full-history or continuation mechanism when stable model switching is required.

## G. Proxy, Virtual Keys, and Model Mapping

- [ ] If the project uses BFF, Caddy, LiteLLM, or another proxy, trace the SDK's actual method, path, query, headers, body, and streaming behavior. Verify the virtual key before safely replacing it with upstream credentials.
- [ ] Are GET endpoints such as Models, Files, and Caches forwarded correctly instead of reaching a route that only supports POST `generateContent`? Preserve upstream status, required headers, and response body.
- [ ] Does proxy model mapping cover the text, image, video, and embedding models actually used by the course? Verify names and provider capabilities against current configuration and official data.
- [ ] Test model-list GET, standard and streaming generation, Custom Tools, Search, and embeddings. Test image and video paths when the project uses them. These tests must detect future routing and mapping regressions.

## H. Gemini API Skill and Docs MCP Configuration

All requirements are contained in this prompt. Do not depend on guides or templates from the source repository. Validate file presence, configuration correctness, and runtime activation separately. A file existing does not prove that its feature is active.

### Static Configuration

- [ ] Does `.agents/skills/gemini-api-dev/SKILL.md` exist with valid frontmatter containing at least `name` and `description`? Does it require current official documentation lookup, current SDK usage, no guessing of models or fields, and API-key protection?
- [ ] Is `.agents/mcp_config.json` valid JSON, and is `mcpServers.gemini-api-docs.serverUrl` set to `https://gemini-api-docs-mcp.dev`? Merge this server without replacing existing servers. Minimum configuration:

  ```json
  {
    "mcpServers": {
      "gemini-api-docs": {
        "serverUrl": "https://gemini-api-docs-mcp.dev"
      }
    }
  }
  ```

- [ ] Do the skill path, filename, name, and MCP server name match the user's actual agent platform? Is there a conflicting project and global skill with the same name but different content?
- [ ] Could `.gitignore`, download packaging, or the course starter omit the hidden `.agents` directory? Confirm it survives clone and archive extraction.
- [ ] Are skill and MCP configuration free of API keys, passwords, customer data, and other secrets? Do they prohibit sensitive content in remote MCP queries?

### Runtime Validation

- [ ] After reloading the agent, does the skill list or Rules UI show `gemini-api-dev`? Provide command output or an observed UI result. If the environment cannot operate the UI, report **UNVERIFIED**, not PASS.
- [ ] Does the MCP UI or available tool list show `gemini-api-docs` as connected and expose `search_documentation` or `search_docs`? JSON configuration alone is not connection evidence.
- [ ] Run the following smoke prompt and use the tool execution trace to prove the agent called Docs MCP before answering. A plausible answer is not evidence of MCP activation.

  > Search the official Gemini documentation first. Then demonstrate Gemini API context caching with the current Python SDK and identify the MCP tool and skill you used.

- [ ] If MCP is unavailable, does the skill fall back to `https://ai.google.dev/gemini-api/docs/llms.txt` or relevant official Gemini documentation and explicitly report that fallback instead of silently relying on model memory?
- [ ] If configuration is incomplete, apply the smallest correction and rerun JSON parsing, skill discovery, MCP connection, and the smoke test. If global configuration is outside the granted scope, provide exact steps instead of writing to the user's home directory.

## I. Preventing Recurrence

After fixing each FAIL, select the appropriate long-term protection. Do not fix only the current code, and do not create a new skill for every issue without evaluating necessity.

- [ ] **Rule / AGENTS.md:** Add cross-task principles requiring semantic judgment to the nearest applicable rules file. If none exists, confirm a persistent need before choosing a location supported by the user's agent platform.
- [ ] **Hook / CI / automated test:** Add reproducible checks for deterministic conditions, such as JSON schema validation, legacy SDK or static-model-list detection, lint, type-check, build, tool-history tests, and proxy-routing integration tests.
- [ ] **Skill:** Determine whether an existing skill already covers work requiring specialist knowledge, official documentation lookup, a fixed workflow, or reusable scripts. Create or update one only when reusable capability is genuinely missing; check names and trigger descriptions for conflicts.
- [ ] **Documentation:** Update background, manual procedures, and troubleshooting. Do not leave an automatically testable condition as documentation only.
- [ ] After adding a rule, hook, CI workflow, or skill, prove that it loads or triggers at the expected time and demonstrate both failure and success behavior. Preserve existing hooks, MCP servers, skills, and configuration.

For every fix, report a **recurrence-prevention decision**: `Rule`, `Hook/CI/Test`, `Skill`, `Document`, or `No addition`, with the reason and whether it was implemented. If creating a mechanism exceeds user authorization, recommend it without expanding scope.

### Embedded Candidate Project Rules

If the decision requires a rule, use the following as candidate content. Remove items irrelevant to the target project and merge the remainder into the nearest rules file supported by that agent platform. Do not assume the file must be named `AGENTS.md`, copy the template blindly, or replace existing rules.

```markdown
## Gemini API Development Rules

### Before Implementation

1. Inspect relevant source, dependencies, lockfiles, configuration, and tests to identify the actual SDK, version, and API.
2. Verify time-sensitive Gemini models, SDKs, APIs, and tool schemas against current official documentation before implementation.
3. New or updated JavaScript/TypeScript features must use `@google/genai`. Do not use `@google/generative-ai` through dependencies, imports, import maps, or CDNs.
4. Only isolated legacy lessons may temporarily retain `@google/generative-ai`, and only with the Gemini 2.x model verified for that lesson. Do not use it for Gemini 3.x, newer models, or new features. Pin versions, mark the limitation, and provide a migration plan.
5. A Web App using `@google/genai` must run through an HTTP(S) dev, preview, or production server. Do not support double-clicked `index.html` or `file://`. Provide a reproducible command and validate SDK requests, ES modules, CORS, Secure Context, routing, and assets under a real origin.
6. Keep production Gemini calls and long-lived keys in server-side code or a backend proxy. A browser-only lesson must state its local-learning scope and risk and still use a localhost dev server.
7. Populate model choices through the SDK or Models API and filter by capability. Label pinned course models as compatibility settings rather than a complete current list.
8. Validate both static and runtime Gemini skill and Docs MCP setup. If MCP is unavailable, use official Gemini `llms.txt` or other official documentation and report the fallback.

### Implementation Requirements

- Handle IME, Enter, Shift+Enter, duplicate sends, and post-send input clearing.
- Provide Traditional Chinese user-facing error summaries, next steps, and redacted details. Render HTML and Markdown safely with real typography styles.
- Connect every UI control to a real request, permission, or handler and prove it with observable evidence.
- Do not ship mock, placeholder, or demo-only features: no hard-coded responses, fake data or loading, always-successful stubs, disconnected handlers, or fallbacks that disguise errors as success. Disable and label unfinished features.
- Keep test doubles in tests or explicit development fixtures and out of production paths. Validate at least one real SDK/API/tool path with integration or E2E coverage.
- README and course instructions must use a server-based launch flow. Do not maintain a separate CDN or inline implementation for direct-open HTML. Special runtimes such as Electron require separate protocol and Secure Context validation.
- Configure combined Search and Custom Tools from the current SDK or REST schema without guessing field casing.
- Complete and validate the full Custom Tool loop, including argument validation, failures, parallel or sequential calls, and loop limits.
- Preserve complete SDK responses in history when possible. Manual serialization must retain required roles, tool calls and responses, call IDs, thought signatures, and server-side tool context.
- Do not generalize one model or legacy SDK observation into a permanent limitation. Test cross-model and multi-turn tool history.
- When voice input is required, implement permission, recording or recognition state, stop, error, retry, HTTPS/localhost constraints, and text fallback.
- For proxies and virtual keys, validate methods, paths, queries, headers, streaming, GET endpoints, and mappings for all text, media, and embedding models in use.
- Never expose API keys, tokens, customer data, or other secrets in source, logs, error UI, snapshots, or remote MCP queries.

### Before Delivery

1. Run applicable lint, type-check, build, unit, and integration tests. Explain anything not run.
2. From a fresh clone, follow README commands to start dev or preview server. Confirm an HTTP(S), localhost, or loopback origin rather than `file://`, then validate refresh, assets, API/proxy, and CORS.
3. Test Enter, Shift+Enter, Chinese/Japanese IME, input clearing, Markdown, friendly errors, expanded details, and redaction.
4. Test no tool, Search only, Custom Tool only, combined tools, tool failure, and a follow-up after a tool call.
5. With a proxy, test model-list GET, standard generation, streaming, Custom Tools, Search, embeddings, and any image or video features used by the project.
6. Report changed files, validation evidence, and unverified risks. Never claim complete coverage without evidence.
```

## Minimum Validation Matrix

| Area | Required cases |
| --- | --- |
| UI | Enter, Shift+Enter, Chinese/Japanese IME, input clearing, duplicate-send prevention |
| Web launch | Fresh clone, documented dev/preview command, HTTP(S) origin, refresh, assets, API/proxy, CORS, and no direct-open HTML instructions or branches |
| SDK/models | No `@google/generative-ai` in dependencies, lockfiles, imports, CDNs, or docs; isolated legacy lessons use only verified 2.x models with pinned versions and migration notes |
| Real functionality | Search for hard-coded responses, fake data/loading, stubs, and mock fallbacks; confirm no test doubles in production and use integration/E2E evidence for real SDK/API/tool wiring |
| Rendering | Markdown headings/lists/code, malicious HTML, friendly errors, expanded details, and redaction |
| Tools | No tool, Search only, Custom Tool only, combined tools, tool failure, and tool-result follow-up |
| API | Model listing and capability filtering, generation with the selected model, and proxy GET/streaming/media/embedding paths when applicable |
| Agent setup | Skill file, MCP JSON, skill discovery, MCP connection, Docs MCP smoke prompt, and official-documentation fallback |
| Recurrence protection | Rule loading, failing and passing hook/CI/test cases, skill triggering, and conflict checks |

## Required Output Format

Use this exact Markdown structure:

### Official Documentation Verification

| Item | Selected implementation | Official source | Verification date |
| --- | --- | --- | --- |
| SDK/version |  |  |  |
| API/model strategy |  |  |  |

### Audit Results

| ID | Check | Result | Evidence or reason |
| --- | --- | --- | --- |
| A1 |  | PASS / FAIL / N/A |  |

> `N/A` requires a reason. `PASS` requires a source location, test, or other observable evidence.

### Fixes Applied

- `path/to/file`: key change and reason

### Recurrence-Prevention Decisions

| Issue | Protection layer | Implemented now? | File/mechanism | Reason and trigger evidence |
| --- | --- | --- | --- | --- |
|  | Rule / Hook/CI/Test / Skill / Document / No addition | Yes / No |  |  |

### Validation Evidence

```text
Commands executed and result summary
```

### Remaining Risks

- List untested browsers, real APIs, proxies, or paid media capabilities. If none are known, state: "No known remaining risks."

Never claim that an issue is completely solved, perfectly supported, or fully covered without corresponding tests or observable evidence.
````

## Usage

Paste the complete prompt for a pre-delivery audit, or limit the scope—for example: “Run only sections D, E, and F, and fix every FAIL.” To authorize code changes, also provide the target repository, available test commands, and any required test credentials through an approved secret mechanism. Never paste real keys into the prompt or commit them to Git.
