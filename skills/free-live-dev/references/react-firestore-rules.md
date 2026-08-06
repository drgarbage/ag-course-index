# React & Firestore Development Guidelines

## 1. React & TailwindCSS Specifications
- **React Context API**: Use context for global state sharing. Absolutely no prop drilling beyond 2 levels. Always pair a context with a custom hook that throws if used outside its provider — consuming `useContext` directly risks a silent `undefined` instead of a clear error:
```javascript
const AppContext = React.createContext(null);
function AppProvider({ children }) {
  const [state, setState] = React.useState({});
  return <AppContext.Provider value={{ state, setState }}>{children}</AppContext.Provider>;
}
function useApp() {
  const context = React.useContext(AppContext);
  if (!context) throw new Error('useApp must be used within an AppProvider');
  return context;
}
```
- **Component Structuring**: Separate view components from business hooks. Create modular hooks (e.g. `useAuth`, `useDatabase`) for reuse.
- **Tailwind CSS styling**: Use modern typography and flex/grid systems. Avoid vanilla CSS inline styles:
```jsx
<div className="flex flex-col md:grid md:grid-cols-3 gap-6 p-6 bg-slate-900 text-white rounded-xl shadow-2xl">
```

---

## 2. Firestore Access & Security
- **Credentials Policy**: Never hardcode Firebase service accounts or admin credentials, and never commit them to the repo — even in a gitignored-looking path, since automation is unattended and there is no human review before push. Store the service account JSON as a Vercel Environment Variable / GitHub Actions Secret and load it via `process.env` only. Fail with a clear, actionable message instead of letting a missing variable crash the whole server on a cryptic `JSON.parse` syntax error (`Unexpected token u in JSON at position 0` gives a non-developer nothing to act on):
```javascript
import { initializeApp, cert, getApps } from 'firebase-admin/app';
if (!getApps().length) {
  if (!process.env.FIREBASE_SERVICE_ACCOUNT) {
    throw new Error(
      'FIREBASE_SERVICE_ACCOUNT is not set. Run the credential bootstrap ' +
      '(free-live-dev Section 2.2) to fill it in via the local form.'
    );
  }
  initializeApp({ credential: cert(JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT)) });
}
```
- **Client SDK Restriction**: When using Client-side Firestore SDK, all requests must be evaluated against Firebase Security Rules. Avoid writing client-side mutations for sensitive tables.
- **Test Isolation**: Playwright runs (`references/playwright-qa-rules.md`) must never write to the real Firestore project — point the app at the Firebase Local Emulator Suite during the QA loop instead, so a failed self-healing attempt can't dirty real data.
  - **Setup**: This project must have a `firebase.json` before any emulator or `firebase deploy` command works — if it's missing (typically only on a brand-new project, since Section 2.1's bootstrap should have created it alongside the Firestore database), run `firebase init firestore` non-interactively (`--project <id>`) or hand-write one declaring `emulators.firestore.port` (pick a port that doesn't collide with the dev server, e.g. `8080`) and `firestore.rules` as the rules file path. On the client, connect to that emulator only when a QA/test env flag is set — and guard against connecting twice, since React Strict Mode / Next.js Fast Refresh can re-run this module-level code and `connectFirestoreEmulator` throws on a second call:
    ```javascript
    import { getFirestore, connectFirestoreEmulator } from 'firebase/firestore';
    const db = getFirestore(app);
    if (process.env.NEXT_PUBLIC_USE_FIRESTORE_EMULATOR === 'true' && !globalThis.__firestoreEmulatorConnected) {
      connectFirestoreEmulator(db, '127.0.0.1', 8080);
      globalThis.__firestoreEmulatorConnected = true;
    }
    ```
  - **Startup order**: Start the emulator before the dev server, and let Playwright's `webServer` wait on the dev server port only — the emulator isn't Playwright's concern, so start/stop it as a wrapping step around `npx playwright test`. **Set `NEXT_PUBLIC_USE_FIRESTORE_EMULATOR=true` on the outermost command**, not just inside the emulator process — `firebase emulators:exec` only injects `FIRESTORE_EMULATOR_HOST` for the Admin SDK into its child process, it does not know about this project's own client-side flag, so the dev server (itself a grandchild, spawned by Playwright's `webServer`, spawned by `playwright test`, spawned by `emulators:exec`) only sees it if it's set at the top and inherited down every layer:
    ```bash
    NEXT_PUBLIC_USE_FIRESTORE_EMULATOR=true npx firebase emulators:exec --only firestore "npx playwright test"
    ```
    Skipping this is how the self-healing QA loop ends up silently testing against — and potentially writing to — the real production Firestore project instead of the emulator.
  - **Seeding**: If tests need existing documents, seed them via the Admin SDK against the emulator (`FIRESTORE_EMULATOR_HOST=127.0.0.1:8080`) in a `globalSetup` script rather than relying on whatever state a previous run left behind — the emulator is in-memory and resets when it stops, so tests must not assume prior data survives.
- **Safe Queries & Fallbacks**: Implement try-catch blocks and return clean, desensitized data arrays:
```javascript
async function getCollectionData(collectionName) {
  try {
    const snapshot = await db.collection(collectionName).get();
    return snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
  } catch (error) {
    console.error(error);
    return [];
  }
}
```
