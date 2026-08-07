# live-dev-config

Modular skill for linking GitHub repositories, linking Vercel projects, and safely collecting credentials.

## Installation
```bash
npx skills add drgarbage/ag-course-index --skill live-dev-config
```

## Features
- Safely links local workspace to private GitHub repositories and Vercel hosting.
- Launches a local browser form (`resources/credential-form.js`) to collect credentials into `.env.local`.
- Securely extracts credentials via `resources/read-env-value.js` and pipes them to CLI variables without shell leakage.
