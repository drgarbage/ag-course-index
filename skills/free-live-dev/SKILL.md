---
name: free-live-dev
description: Orchestrator skill for automated preview-first web development. Provisions backend infrastructure (GitHub repo, Vercel project, Firebase/Firestore) and collects credentials via a friendly local form, enforces Git Flow, runs auto-healing local tests, and delivers Vercel Preview links — the user only authorizes, states requirements, and supplies credentials.
---

# free-live-dev

`preflight → provision → credentials → feature/* → local QA loop → PR → CI → preview URL → release`

`bash` blocks are POSIX (Git Bash on Windows). Any logic beyond one command/pipe lives in `resources/*.js`, never in shell control flow. If your Bash tool is cmd.exe or PowerShell, translate each snippet before running it.

## 1. Preflight (run silently, before planning)

| Check | Probe | On fail |
| --- | --- | --- |
| git, gh | `command -v git`, `command -v gh`, `gh auth status` | run `scripts/install-git-gh-macos.command` \| `scripts/install-git-gh-windows.ps1`. Never improvise install steps. |
| node | `node --version` ≥ `scripts/toolchain/catalog.json:node_lts_major` | `scripts/course-toolchain-macos.command base` \| `scripts/course-toolchain-windows.ps1 -Profile base` |
| vercel, firebase | `npx vercel whoami`, `npx firebase login:list` | `npm install -D vercel firebase-tools` (never `-g`: EACCES). Login must pass before §2. |
| gitleaks | `command -v gitleaks` | install per table below, re-probe, never skip the §4 scan gate |

| OS | Install | Fallback |
| --- | --- | --- |
| macOS | `brew install gitleaks` — brew may NOT exist (course installer uses Xcode CLT + curl, not brew) | curl latest release `gitleaks_*_darwin_$(uname -m).tar.gz` → extract to `~/.local/bin` (mkdir + append to shell profile if absent). No sudo, no `/usr/local/bin`. |
| Windows | `winget install gitleaks.gitleaks` | download `gitleaks_*_windows_x64.zip` → extract `gitleaks.exe` → `%USERPROFILE%\bin` → `setx PATH "%PATH%;%USERPROFILE%\bin"`. `~/.local/bin` and shell profiles do not apply here. |

Then repair project state:

| File / state | Required value | Note |
| --- | --- | --- |
| `.nvmrc` | `catalog.json:node_lts_major` | Sole source of truth. `resources/vercel-preview.yml` reads `node-version-file: '.nvmrc'` — never hardcode a Node major in the yml. |
| `.gitignore` | `.env`, `.env.local`, `.env*.local`, service-account JSON glob | Repair before the first commit ever exists — the vault policy assumes these are ignored. |
| branch | `develop` exists (else propose from `main`); work on `feature/<name>` off `develop` | |
| Firestore | verified only if the request needs persistence | |

**Secret Vault Policy (hard rule, no override).** Credentials live only in Vercel Env Vars / GitHub Secrets / gitignored `.env.local`. Never hardcode in code, never commit real `.env` values, never print a real secret to chat, logs, or commit messages. Carve-out from the §6 override phrase: §6.

---

## 2. Backend & Credential Bootstrap

Once per project, after §1 passes, when the cloud resources don't exist. Invariant: the user never opens a cloud console, never types a raw credential into chat or a visible command, never touches `gh`/`vercel`/`firebase`.

### 2.1 Provisioning (agent-automated)

Create only what is missing, in this order:

| Resource | Skip if | Constraints |
| --- | --- | --- |
| GitHub repo | a remote exists | `gh repo create --private --source=. --push`, from a repo with ≥1 commit. `<name>` defaults to the folder name — ask the user for nothing else. Public only on request. |
| Vercel project | `.vercel/project.json` | `vercel link --yes` — non-interactive. Linking also wires the Vercel↔GitHub integration; there is no separate App-install step. |
| Firebase project | `.firebaserc` | Project ids are globally unique → generate `<repo-name>-<rand4>`, never ask the user to invent one. |
| Firestore database | it already exists | id is the literal `'(default)'` — quote it, bash eats the parens. Location `us-central1` unless data-residency is stated. |
| `firebase.json` | file exists | `firebase init firestore` must run non-interactively; hand-write the file if it prompts. Without it, both deploy and the emulator fail. |
| `firestore.rules` | never skip | author before deploying: `allow read, write: if false;` + per-collection auth rules from `references/react-firestore-rules.md`. Deploy immediately — never leave test-mode rules live. |

Blaze-plan features (Cloud Functions, outbound calls from triggers) need a card entered in the Console — the CLI cannot do it, and it is not a "credential" to collect. This is the only legitimate console visit. On any billing/plan error: stop → name the single step → link `https://console.firebase.google.com/project/<id>/usage/details` → resume on confirmation.

Log every resource created here under Recurrence Protection.

### 2.2 Credential collection

Emit `.credential-fields.json` holding only what this step needs (e.g. the service-account key right after 2.1):

```json
[{ "name": "FIREBASE_SERVICE_ACCOUNT", "label": "Firebase 服務帳戶金鑰",
   "help": "Project settings → Service accounts → Generate new private key",
   "link": "https://console.firebase.google.com/project/<id>/settings/serviceaccounts/adminsdk" }]
```

```bash
node resources/credential-form.js .credential-fields.json   # launch via the TOOL's background mode, NOT a shell `&`
```

- `&` yields no exit signal — you need the tool-level mechanism that notifies on process exit.
- Script: 127.0.0.1-only form → best-effort browser open → prints its URL → writes gitignored `.env.local` → exits on submit or 15-min idle. Relay the URL to the user (auto-open fails headless); the exit is your wake signal.
- Success = the printed `SAVED_KEYS=<names>` line. Never read values back into chat.
- No browser can open → write `.env.local.template` as `KEY_NAME=   # what it is + where to get it (link)`; the user copies it to `.env.local`, fills it, and replies. Their reply is the wait signal.
- `gh auth login` / `vercel login` / `firebase login`: use each CLI's own device-code flow as-is.

Never `source`/`eval` `.env.local`, never interpolate a credential into `"..."` or `<<<` — bash expands `$(...)`/backticks/`$VAR` inside double quotes, so `p@ss$(whoami)` executes. Extract via `JSON.parse` and pipe to stdin:

```bash
node resources/read-env-value.js .env.local FIREBASE_SERVICE_ACCOUNT | vercel env add FIREBASE_SERVICE_ACCOUNT production
# same shape for the GitHub side: ... | gh secret set <KEY>
```

Report by key name only: `✅ FIREBASE_SERVICE_ACCOUNT set in Vercel/production`.

---

## 3. Git Flow & Release Lifecycle

| Transition | Trigger | Gate |
| --- | --- | --- |
| `develop` → `feature/*` | new request | — |
| `feature/*` → `develop` | §4 QA loop + secret scan PASS locally | `gh pr checks <PR#> --watch` green. Local ≠ CI: CI also runs `lint` + `build`. |
| `develop` → `main` | user approves the verbatim prompt below | same CI wait → merge → tag → bump |
| `main` → `develop` | immediately after the release PR merges | back-merge, no PR needed. The bump commit exists only on `main`; skip this and the two branches collide on `version` at the next release. |

Code on `feature/*` follows `references/react-firestore-rules.md`.

Release prompt, verbatim: `"Would you like to release this to the production environment?"`

- The release PR carries both the tag `v<major>.<minor>.<patch>` and the matching `package.json:version` (read it, default `0.0.0`, bump patch unless told otherwise). Split across two PRs and they drift.
- Never merge on red or pending CI. CI red after green local → back into the §4 healing loop → push → wait again.
- Branch protection blocks the merge → report the specific blocking reason and ask. Never force-merge, never edit protection settings.
- Merge conflict → stop and show the files. Self-resolve only generated artifacts (`package-lock.json`, build output); any hand-written source conflict goes to the user.
- Deploy only via the Vercel GitHub integration. No local `vercel deploy` unless explicitly requested.
- Broken production → `git revert` the merge commit on `main` → push → Vercel redeploys. Never force-push history. Log it.

---

## 4. Local Verification & Auto-Healing

Setup, port discovery, and test templates: `references/playwright-qa-rules.md`. One port for dev server + `baseURL` + any test URL.

Gates, all green before any commit or push — never commit or push past a red one: the Playwright suite, `lint`, `build`, and `gitleaks protect --staged` (staged diff, not `detect`) before every commit — same tool as CI, never improvise a regex.

- On failure: parse errors/traces → fix implementation code only → rerun, under the healing loop of `references/playwright-qa-rules.md` (hard limit 3 attempts, then halt and report logs). Its no-weakening rule extends to fixtures and lint rules; if an expectation itself looks wrong, stop and report. Flake (= passes on an immediate rerun with zero code change) costs one confirming rerun, not an attempt.
- **Secret Scan Gate (hard rule, no override — same class as §1).** Any match blocks the commit → move the value to the vault, reference via `process.env`.
- Feature touches Firestore → run the QA loop against the Local Emulator Suite (`references/react-firestore-rules.md`), never the real project.
- No commit hooks in the project → install a committed, `npm install`-auto-installing hook manager (Husky/Lefthook) running lint + secret scan pre-commit. Not a hand-written `.git/hooks/pre-commit` — untracked, dies on fresh clone. Supplements the CI `gitleaks` step in `resources/vercel-preview.yml`; a local hook can be `--no-verify`'d, CI cannot.

---

## 5. Preview-First Delivery

Never hand the user a `localhost` link for verification.

```bash
node resources/resolve-preview-url.js   # exit 0 -> prints PREVIEW_URL=<url>
                                        # exit 1 immediately (no retry) -> integration absent
                                        # exit 1 after the full 12x5s=60s budget -> see escalation below
node resources/resolve-preview-url.js --attempts 12 --interval-ms 10000
```

Source is the GitHub Deployments API, which the Vercel integration writes on every push, PR or not; `gh` supplies owner/repo. Do not parse the interactive `vercel list` table — it lists all history and can prompt when unlinked.

Escalation while empty:

| Elapsed | Action |
| --- | --- |
| 60s (default) | covers a webhook delay, not a build → extend attempts, tell the user a build is in progress |
| ~5 min | non-interactive JSON `vercel list` filtered to the pushed commit (`vercel list --help`; flags vary by version) |
| after that | report plainly that it isn't resolvable yet + dashboard URL from `vercel project ls` / `vercel inspect` |

Never fabricate a URL, never silently give up.

Empty ≠ integration missing. The usual cause: the Vercel GitHub App is installed but scoped to *Only select repositories*, and the repo §2.1 just created isn't listed → send the user to `https://github.com/settings/installations`. Never route around it with local `vercel deploy` (§3); fix the permission gap at source.

```text
⚡️ Features deployed successfully! Preview URL: https://project-git-develop-user.vercel.app
```

---

## 6. Guardrails

Bad pattern requested (prop drilling over Context, bypassing GitHub automation, reusing preview infra for production data, …) → halt and emit:

| | Requested | Proposed alternative |
| --- | --- | --- |
| Security risk | | |
| Maintenance cost | | |

Resume only on the verbatim string `"I understand the risk and insist on this."`

That phrase never covers hardcoding a key, committing a real secret, or any credential leak (§1 Vault Policy, §4 Scan Gate) — no human reviews the diff before it reaches GitHub. Refuse until the value moves to the vault.

---

## Output Format

### Verification Log

- Vercel Deployment Link: [preview or production URL]
- Git Branch: [feature branch / develop / main]
- PLAYWRIGHT Test Status: [PASS / FAIL]

### Checklist

| ID | Item | Result | Evidence |
| -- | --- | --- | --- |
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

- [Rule / Hook / Test / Skill / "Not Needed" + reason; plus the repo URL, Vercel project, and Firebase project id from §2.1]
