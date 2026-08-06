# AI Agent UI & Integration Support Skill (`ai-agent-ui-support`)

`ai-agent-ui-support` is a reusable agent skill designed to provide design and implementation guidance for embedding an AI Agent interface as a supporting assistant into any web application. 

It ensures that the AI Agent is non-intrusively integrated, aligns with the host application's design system and tech choices, manages inputs and composers cleanly, handles responsive screen formats, runs tool execution and confirmations securely, and maps complex requests into structured subtask plans.

## 🌟 Key Features Covered

- **Non-Intrusive Layout Adapters**:
  - **Closed State**: Floating Action Button (FAB) at bottom-right.
  - **Compact Desktop Width**: Floating chat window above the content.
  - **Wide Desktop Width**: Collapsible docked side panel that reflows the main application content (no overlapping).
  - **Mobile Layout**: Full-screen/drawer views respecting safe-area bottom insets and mobile keyboard behavior.
- **Smart Message Composer**:
  - IME Composition safety to prevent premature message sending (critical for Traditional Chinese, Japanese, and Korean keyboards).
  - Multi-attachment support (images, files) with validation, progress display, individual deletion, and previews.
  - Speech-to-Text flow using a microphone toggle that keeps recording until stopped, displaying elapsed time, and returning editable text to the draft box before sending.
- **Robust Session Management**: Adaptive persistence (local storage, IndexedDB, or server-side DB) following host patterns.
- **Long Task Management**: Divides heavy queries into a visual checklist with progress bars, statuses, and cancellation controls.
- **Tool Use & Execution Security**:
  - Dynamic capability detection (e.g., streaming, image input, tools) using a clean adapter pattern.
  - Real-time page state updates mirroring tool execution results.
  - Mandatory confirmation cards before executing destructive or expensive actions (e.g. deleting data, sending invoices).

---

## 📦 Installation

You can install this skill directly into your project's customization directory.

### ⚡️ Quick Installation (CLI)
Run the following command in your project's root folder:
```bash
npx skills add drgarbage/ag-course-index --skill ai-agent-ui-support
```
To install it globally (applying it to all projects handled by your agent):
```bash
npx skills add drgarbage/ag-course-index --skill ai-agent-ui-support -g
```

> Requires this skill to be pushed to the `drgarbage/ag-course-index` repo on GitHub first — it won't resolve from an uncommitted local checkout.

---

### 🛠️ Manual Installation (Fallback)
If CLI installation is not available, create the following directory in your project root:
```text
.agents/skills/ai-agent-ui-support/
```
And download and copy the [SKILL.md](SKILL.md) file directly into it.
