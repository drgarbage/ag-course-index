# live-dev-deploy

Modular skill for local verification, auto-healing testing, preview URL polling, and Git Flow release deployment.

## Installation
```bash
npx skills add drgarbage/ag-course-index --skill live-dev-deploy
```

## Features
- Runs a local verification loop using Playwright, linter, build, and Gitleaks pre-commit.
- Includes an auto-healing loop to fix code issues automatically based on rules in `references/playwright-qa-rules.md`.
- Polls for the Vercel Preview URL using `resources/resolve-preview-url.js`.
- Implements Git Flow branch transitions, release tags, and checks for public deployment access.
