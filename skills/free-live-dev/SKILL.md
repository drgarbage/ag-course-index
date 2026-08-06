---
name: free-live-dev
description: Orchestrator skill for automated preview-first web development. Provisions backend infrastructure (GitHub repo, Vercel project, Firebase/Firestore) and collects credentials via a friendly local form, enforces Git Flow, runs auto-healing local tests, and delivers Vercel Preview links — the user only authorizes, states requirements, and supplies credentials.
---

# Free Live Dev Orchestrator Skill

**Shell assumption**: the `bash` snippets in this skill (plain CLI invocations and pipes) assume a POSIX-compatible shell is what your Bash tool actually runs — true for Claude Code, whose Bash tool requires Git Bash on Windows. Anywhere the logic was more than a single command or pipe (retry loops, file parsing, credential handling), it was deliberately written as a small Node script under `resources/` instead of raw shell control-flow, specifically so it behaves the same regardless of which shell your Bash tool maps to — see `resources/read-env-value.js` and `resources/resolve-preview-url.js`. If you're running this skill under a harness where the Bash tool is native `cmd.exe`/PowerShell rather than a POSIX shell, verify that assumption before trusting any remaining raw shell snippet below.

## 1. Environment & Pre-definition Checks
Before generating an implementation plan, you must silently run checks and resolve environment statuses:
- **CLI Presence & Logins**:
  - `git` / `gh`: check with `command -v git`, `command -v gh`. If either is missing or `gh auth status` fails, do not improvise install steps — direct the user to run the course's own installer, which already handles per-OS quirks (macOS Gatekeeper quarantine, Xcode license, Windows execution policy/UAC, PATH refresh, `gh` scopes, credential helper setup): `scripts/install-git-gh-macos.command` (macOS) or `scripts/install-git-gh-windows.ps1` (Windows).
  - `node`: check with `node --version` (need >= the version pinned in `scripts/toolchain/catalog.json`'s `node_lts_major`). If missing or outdated, direct the user to run `scripts/course-toolchain-macos.command base` (macOS) or `scripts/course-toolchain-windows.ps1 -Profile base` (Windows), which installs both `git_gh` and `node_lts` via winget/brew with version checks.
  - `vercel` / `firebase` CLI: these are plain npm packages, not covered by the catalog above. Prefer adding them as `devDependencies` (`npm install -D vercel firebase-tools`) and invoking via `npx vercel` / `npx firebase` — a global `npm install -g` can fail with `EACCES` depending on how Node was installed. If installed but unauthorized, run `npx vercel whoami` / `npx firebase login:list` and provide the login link or interactive command. These logins must succeed before Section 2's Resource Provisioning can run.
  - `gitleaks`: check with `command -v gitleaks`. This is required for Section 4's Secret Scan Gate — treat it as mandatory infrastructure, not optional.
    - **macOS**: try `brew install gitleaks` first, but **do not assume Homebrew exists** — this course's own installer (`scripts/install-git-gh-macos.command`) sets up git/gh via Xcode Command Line Tools and a direct `curl` download, not Homebrew, so a fresh student machine may genuinely have no `brew`. If `command -v brew` fails, download the matching `_darwin_<arch>.tar.gz` release from `https://github.com/gitleaks/gitleaks/releases/latest` (arch from `uname -m`), extract it, and place the binary in a directory already on `PATH` (e.g. `~/.local/bin`, creating it and adding it to the shell profile if it isn't there yet) rather than requiring `sudo` for `/usr/local/bin`.
    - **Windows**: try `winget install gitleaks.gitleaks` first. If `winget` is unavailable, this is a genuinely different download+install shape than macOS, not "the same approach" — download the `_windows_x64.zip` release asset from the same releases page, extract `gitleaks.exe`, and place it in a user-writable directory that's actually on `PATH` (e.g. `%USERPROFILE%\bin`, adding it via `setx PATH "%PATH%;%USERPROFILE%\bin"` if it isn't already there — `~/.local/bin` and editing a POSIX shell profile don't apply here).
    - Re-check `command -v gitleaks` before proceeding either way. Do not silently skip the scan gate because the binary is missing — halt and install first.
- **Node Version Pin (`.nvmrc`)**: Ensure the project root has an `.nvmrc` containing the `node_lts_major` value from `scripts/toolchain/catalog.json` (create it if missing, update it if it has drifted). This is the single source of truth both for local Node selection and for the CI workflow (`resources/vercel-preview.yml` reads `node-version-file: '.nvmrc'`) — never hardcode a Node major version directly into the CI yml, since that silently diverges from the local toolchain whenever the catalog is bumped.
- **Git State**: Check current branch. If `develop` branch does not exist, propose creating it from `main`. All new requests must branch out as `feature/branch-name` from `develop`.
- **`.gitignore` Check**: Before any commit is ever made, verify `.gitignore` exists and excludes `.env`, `.env.local`, `.env*.local`, and any service-account JSON filename pattern the project uses. Create or extend `.gitignore` if it's missing or incomplete — do this before the Secret Vault Policy below can be trusted, since that policy assumes gitignored `.env.local` files are actually being ignored.
- **Firestore Check**: Only verify Firestore configuration and connection if the request requires database persistence.
- **Secret Vault Policy (hard rule, no override)**: All API keys, service account JSON, and other credentials MUST live only in a secret vault (Vercel Environment Variables, GitHub Actions Secrets, or `.env.local` files that are gitignored). Never hardcode a key in client or server code, never commit an `.env` file with real values, and never print a real secret value into chat, logs, or commit messages. This rule is **not** part of the Section 6 "insist on this risk" override — no confirmation phrase from the user can waive it, because there is no human reviewing the diff before it reaches GitHub.

---

## 2. Backend & Credential Bootstrap
Run this once per project, right after Section 1's CLI/login checks pass, whenever the required cloud resources don't exist yet. The goal of this section: the user never opens a cloud console, never types a raw credential into chat or a visible shell command, and never has to understand `gh`/`vercel`/`firebase` — they authorize, state requirements, and fill in a form.

### 2.1 Resource Provisioning (agent-automated)
- **GitHub repo**: if the working directory isn't a git repo yet, `git init` and create an initial commit first — `gh repo create --source=. --push` needs at least one commit to push. If there's no remote configured, run `gh repo create <name> --private --source=. --push`. Ask the user only for the repo name (default to the project folder name) — private by default unless they say otherwise.
- **Vercel project**: check for `.vercel/project.json`. If absent, run `vercel link --yes` from inside the git-connected project — linking this way also wires the Vercel↔GitHub integration automatically, so there's no separate "install the Vercel GitHub App" step to walk the user through.
- **Firebase project + Firestore**: check for `.firebaserc`. If absent:
  - `firebase projects:create <project-id>` — generate the id from the repo name plus a short random suffix (Firebase project ids are globally unique; don't ask a non-developer to invent one).
  - `firebase firestore:databases:create '(default)' --location=<region>` — default to a sensible region (e.g. `us-central1`) unless the user has stated a data-residency need.
  - Run `firebase init firestore --project <project-id>` non-interactively (or hand-write `firebase.json` / `.firebaserc` if the CLI insists on a prompt) so the project actually has a `firebase.json` declaring the rules file and emulator ports — `firebase deploy` and the emulator setup in `references/react-firestore-rules.md` both fail without one, and a brand-new project never has it yet.
  - Author `firestore.rules` with a locked-down default (`allow read, write: if false;` plus the per-collection auth rules from `references/react-firestore-rules.md`) and deploy it immediately via `firebase deploy --only firestore:rules` — never leave a freshly created database on open test-mode rules, even for the seconds before the real app rules land.
  - **Known limitation — billing**: some Firebase features (Cloud Functions, outbound network calls from Firestore triggers, etc.) require the project to be on the Blaze (pay-as-you-go) plan, and attaching a billing account needs a credit card entered through the Firebase Console — the CLI cannot do this on the user's behalf, and it is not something to ask the user to hand over as a "credential". If a provisioning command fails with a billing/plan error, stop, tell the user plainly which one Console step is needed (link to `https://console.firebase.google.com/project/<id>/usage/details`) and why, then resume once they confirm it's done. This is the one legitimate exception to "the user never opens a console."
- Note what was created (repo URL, Vercel project name, Firebase project id) in the Verification Log's Recurrence Protection line, so the user has a record of what now exists under their account.

### 2.2 Credential Collection (non-developer friendly)
Never ask the user to paste a secret into chat, and never type a secret value into a visible shell command — both leave it sitting in a transcript or shell history, which Section 1's Secret Vault Policy forbids.
- **Primary path — local credential form**: build a field list (`name`, `label`, one-line `help`, and a direct `link` to where the user finds that credential — see the schema comment at the top of `resources/credential-form.js`) for whatever the current step actually needs (e.g. the Firebase service-account key right after `2.1` creates the project). Write it to a temp `.credential-fields.json` and run:
  ```bash
  node resources/credential-form.js .credential-fields.json
  ```
  using your tool's own background-execution mode (e.g. a Bash tool's `run_in_background` option), **not** a trailing shell `&`. A shell `&` only backgrounds the process within that one shell invocation and gives you no reliable signal for when it finishes — if your tool call returns immediately either way, you need the tool-level mechanism that notifies you on process exit, not the shell-level one. The script serves a small 127.0.0.1-only HTML form, best-effort opens it in the user's default browser, prints the form URL to stdout (relay this URL to the user in chat as a fallback in case auto-open doesn't work, e.g. in a headless/remote session), writes submitted values straight into the gitignored `.env.local`, and exits on its own once the form is submitted (or after a 15-minute idle timeout) — that exit is what your background-task notification fires on. The values are never echoed back to you — confirm success from the `SAVED_KEYS=...` line the script prints (names only), not from re-reading the file's contents into chat.
- **Fallback path — guided `.env.local` template**: if a browser genuinely can't be opened, write `.env.local.template` with each required key as `KEY_NAME=   # what this is + where to get it (link)`, ask the user to copy it to `.env.local`, fill it in, save, and reply once done — their reply is the wait signal, nothing to poll.
- **One-off platform logins** (`gh auth login`, `vercel login`, `firebase login`): just run the CLI's own interactive/device-code flow — these already have a link-and-code UX built for non-developers, no need to reinvent it.
- **Sync to the real vault**: once `.env.local` has the values, push them into Vercel Env Vars / GitHub Secrets without ever printing them. **Never `source` or `eval` this file, and never interpolate a credential into a bash double-quoted string or here-string** — a value can legitimately contain `$(...)`, backticks, or `$VAR`, and bash expands those even inside `"..."`/`<<<`, which is a command-injection hole (a password like `p@ss$(whoami)` will actually execute `whoami`). Use `resources/read-env-value.js` instead, which extracts the value via `JSON.parse` with no shell involved, and pipe it straight into the target CLI's stdin:
  ```bash
  node resources/read-env-value.js .env.local FIREBASE_SERVICE_ACCOUNT | vercel env add FIREBASE_SERVICE_ACCOUNT production
  node resources/read-env-value.js .env.local FIREBASE_SERVICE_ACCOUNT | gh secret set FIREBASE_SERVICE_ACCOUNT
  ```
  Confirm success by key name only — "✅ FIREBASE_SERVICE_ACCOUNT set in Vercel/production" — never by echoing the value.

---

## 3. Git Flow & Release Lifecycle
You are responsible for branch transitioning and deployment routing:
- **Development**: Implement features on `feature/branch-name`, following `references/react-firestore-rules.md` for React/Tailwind/Firestore conventions. Do not merge to `develop` without local tests passing.
- **Merge to Develop**: Create a Pull Request for `feature/branch-name` into `develop` once verified (Section 4's QA loop + secret scan both PASS locally). Before merging, wait for the CI workflow (`resources/vercel-preview.yml`) to finish on that PR — poll with `gh pr checks <PR#> --watch` (or equivalent) rather than merging the instant local checks pass. Local checks and CI are not the same gate: CI additionally runs `lint` and `build`, which the local QA loop does not (see Section 4's Build/Lint Parity). Only merge once CI reports success; if CI fails after local checks passed, treat it like any other failed test — go back into the Self-Healing Loop, push a fix, and wait for CI again. Never merge with a red or pending CI check.
  - If `gh pr merge` fails because of branch protection (required review, required status check not yet satisfied, etc.), do not force-merge or bypass protection settings — report the specific blocking reason to the user and ask how they want to proceed.
  - If the merge reports a conflict, do not auto-resolve it by guessing — stop, show the conflicting files to the user, and ask for guidance (or resolve only if the conflict is trivial and mechanical, e.g. a lockfile).
- **Release to Production**: When the user confirms preview is correct, ask: `"Would you like to release this to the production environment?"` Upon approval, create a PR from `develop` -> `main`, wait for its CI to pass the same way as above, then merge and tag the release.
  - **Version bump**: Read the current `version` field from `package.json` (default to `0.0.0` if absent). Unless the user specifies otherwise, bump the **patch** version for this release. Tag as `v<major>.<minor>.<patch>` and update `package.json`'s `version` field to match in the same release PR, so the tag and the manifest never drift apart.
  - **Back-merge**: The version bump commit lives only on `main` after this merge — `develop` doesn't get it automatically. Immediately after the release PR merges, merge `main` back into `develop` (fast-forward or a trivial merge commit) so the next `feature/*` branch is cut from a `develop` that already has the new version number. Skipping this step is how `develop` and `main` silently diverge on `package.json`'s `version` field and collide on the next release.
- **No CLI bypass**: Always deploy via Vercel GitHub integration. Do not use `vercel deploy` directly from local CLI unless explicitly requested.
- **Rollback**: If the user reports the production deployment is broken, revert by `git revert` on the merge commit in `main`, push, and let Vercel redeploy automatically — never force-push history. Report the rollback in the Verification Log.

---

## 4. Local Verification & Auto-Healing (QA Loop)
Before pushing any code, you must verify the UI on localhost, following `references/playwright-qa-rules.md`:
- **Server Startup**: Spin up the localhost development server on the project's configured port (read from `package.json` / `.env` `PORT`; default `3000` if unset). Use this same port everywhere — dev server, Playwright `baseURL`, and any hardcoded test URLs must agree.
- **Automated Validation**: Run local Playwright tests against localhost to verify UI layouts, state flow, and business logic.
- **Build/Lint Parity**: Also run `npm run lint` and `npm run build` locally before pushing — the CI workflow (`resources/vercel-preview.yml`) runs both, and a push that passes Playwright but fails lint/build in CI blocks the merge (see Section 3). Catch that locally instead of finding out after a PR is open.
- **Self-Healing Loop**: If testing, lint, or build fails, parse the error output/snapshots, modify the **implementation code** (never the test assertions, fixtures, or lint config) to fix the underlying bug, and rerun until everything PASSes. Weakening, deleting, or skipping a failing assertion to force a PASS is prohibited — if a test's expectation itself looks wrong, stop and report it to the user instead of editing it unilaterally. If a failure looks flaky (passes on an immediate re-run with no code change), rerun once to confirm before spending a self-healing attempt on it. Hard limit: 3 self-healing attempts, then halt and report logs.
- **Secret Scan Gate (hard rule, no override)**: Before every commit, scan the staged diff for likely credentials using `gitleaks protect --staged` (same tool as the CI gate in `resources/vercel-preview.yml`, so local and CI agree on what counts as a leak) — don't improvise a custom regex. Any match blocks the commit — move the value into the vault (Vercel Env Var / GitHub Secret) and reference it via `process.env` instead. This check cannot be bypassed by user confirmation, since no human reviews the diff before it reaches GitHub.
- **Firestore Test Isolation**: If the feature touches Firestore, run the QA loop against the Firebase Local Emulator Suite, not the real project — see `references/react-firestore-rules.md`.
- **Commit Boundary**: Never commit or push code that fails local test validation or the secret scan gate.
- **Physical Enforcement (defense-in-depth)**: The Secret Scan Gate and Self-Healing rule above only hold if the Agent actually runs them every time. If the project has no commit hooks yet, set one up with a hook manager that gets committed to the repo and auto-installs on `npm install` (e.g. Husky or Lefthook) — not a hand-written `.git/hooks/pre-commit`, since that directory is untracked by git and disappears on a fresh clone. The hook should rerun lint + secret scan before every commit. This supplements, not replaces, the CI `gitleaks` step in `resources/vercel-preview.yml`: a local hook can be bypassed with `--no-verify`, CI cannot.

---

## 5. Preview-First Delivery
- **Never Deliver Localhost Links**: Do not ask the user to open `localhost` for verification.
- **Vercel Preview Link Retrieval**: Do not parse the interactive `vercel list` table — it lists every historical deployment and can prompt interactively if the checkout isn't linked to the Vercel project. Prefer resolving the URL from GitHub's Deployments API, which Vercel's GitHub integration writes on every push regardless of whether a PR is open. Use `resources/resolve-preview-url.js` rather than a bash polling loop — `gh` already knows the current repo, so it resolves owner/repo automatically, and the retry/timing logic lives in Node instead of `for i in $(seq ...)`/`[ -n ]`/`sleep`, which only work in a POSIX shell and would silently fail under a Bash-tool mapped to native cmd.exe/PowerShell:
  ```bash
  node resources/resolve-preview-url.js
  ```
  On success it prints `PREVIEW_URL=<url>` to stdout and exits 0. If the GitHub integration isn't installed at all (as opposed to just being slow), it exits 1 immediately without retrying pointlessly — fall back to a non-interactive, JSON-based `vercel list` invocation filtered to the pushed commit (check `vercel list --help` for the current CLI's exact flag, since it varies by version) rather than the default table output.
  - **Polling Timeout**: the default (12 attempts × 5s = 60s) covers a webhook delay but not a slow build. If it exits 1, do not silently give up or fabricate a URL — extend the budget (e.g. `node resources/resolve-preview-url.js --attempts 12 --interval-ms 10000` for another 2 minutes) while telling the user a build is still in progress; if it still isn't found after ~5 minutes total, fall back to the `vercel list` JSON path, and if that also comes up empty, report plainly that the preview link isn't resolvable yet and give the user the Vercel dashboard project URL (`vercel project ls` / `vercel inspect`) as a manual fallback instead of leaving them with nothing.
  - **Common cause — GitHub App scoped to select repos**: an empty result after the full timeout isn't always "integration not installed" — the Vercel GitHub App is very often already installed on the user's account but configured for "Only select repositories," and a repo Section 2.1 just created won't be on that list yet. Distinguish this in what you tell the user: point them at `https://github.com/settings/installations` to add the new repo to the Vercel App's access list, rather than assuming the integration needs to be installed from scratch. **Do not silently work around this by running `vercel deploy` from the local CLI** — Section 3's "No CLI bypass" rule exists specifically so that production and preview always go through the same GitHub-triggered path; a permission gap should be surfaced and fixed at the source, not routed around.
- Retrieve the unique URL for the current preview deployment and report it directly to the user as the preview URL:
  ```text
  ⚡️ Features deployed successfully! Preview URL: https://project-git-develop-user.vercel.app
  ```

---

## 6. Security & Architecture Guardrails
If the user demands a bad pattern (e.g., prop drilling instead of Context, bypassing GitHub automation, or reusing preview infra for production data):
1. Stop execution.
2. Present a comparison matrix of pros and cons showing potential security/maintenance risks.
3. Propose a refactored alternative.
4. Only proceed with the requested bad pattern if the user explicitly types: `"I understand the risk and insist on this."`

**Exception — credentials are never overridable.** Hardcoding an API key, committing a real secret, or otherwise leaking a credential into the repo is not eligible for the override phrase above (see Section 1's Secret Vault Policy and Section 4's Secret Scan Gate). If the user insists, refuse and only proceed once the value is moved to the vault.

---

## Output Format

### Verification Log
- Vercel Deployment Link: [preview URL or production URL]
- Git Branch: [feature branch name, develop, or main]
- PLAYWRIGHT Test Status: [PASS / FAIL]

### Checklist
| ID | Item | Result | Evidence |
| --- | --- | --- | --- |
| F1 | Local QA Test | PASS / FAIL / N/A | [test log snippet] |
| F2 | Preview URL | PASS / FAIL / N/A | [live vercel preview URL] |
| F3 | Secret Scan | PASS / FAIL / N/A | [scan result summary] |

### Code Changes
- `[file path]`: [description of change]

### Smoke Test Output
```text
[Playwright execution output]
```

### Remaining Risks
- [untested features, credentials isolation, or "None"]

### Recurrence Protection
- [Describe protection mechanism: Rule / Hook / Test / Skill / "Not Needed" with reason]
