---
name: live-dev
description: "(Legacy Orchestrator) This skill has been split into four modular skills. Please install and use them instead: live-dev-init, live-dev-storage-init, live-dev-config, and live-dev-deploy."
---

# live-dev (Deprecated)

This skill is deprecated and has been split into four modular skills:

1. `live-dev-init`: Tooling preflight and Git Flow environment initialization.
2. `live-dev-storage-init`: Firebase & Firestore database provisioning and rules setup.
3. `live-dev-config`: GitHub/Vercel project linking and local credential form collection.
4. `live-dev-deploy`: Local QA loop (Playwright + linter + secret scans), auto-healing, Vercel preview URL polling, and Git Flow releases.

For new projects, please install the modular skills instead of this monolithic orchestrator. You can install all four at once using:

```bash
npx skills add drgarbage/ag-course-index --skill live-dev-init live-dev-storage-init live-dev-config live-dev-deploy
```
