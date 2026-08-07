# live-dev-storage-init

Modular skill for Firebase & Firestore database provisioning and rules setup.

## Installation
```bash
npx skills add drgarbage/ag-course-index --skill live-dev-storage-init
```

## Features
- Provisions Firebase projects with globally unique IDs (`<repo-name>-<rand4>`).
- Provisions default Firestore databases and writes `firebase.json` non-interactively.
- Establishes initial locked/safe rules referencing `references/react-firestore-rules.md`.
- Integrates local emulator suite setup instructions.
