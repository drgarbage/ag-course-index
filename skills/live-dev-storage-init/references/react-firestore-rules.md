# React & Firestore Development Guidelines

## 1. React & Styling

- **Trigger: Sharing global state** -> Use Context API.
  - *Constraint: Max 2 levels of prop drilling.*
  - *Constraint: Always throw if context is consumed outside its provider.*
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
- **Trigger: Component structure** -> Separate views from business logic into modular hooks (e.g. `useAuth`, `useDatabase`).
- **Trigger: Component styling** -> Use Tailwind CSS flex/grid system.
  - *Constraint: No inline/vanilla CSS styles.*
  ```jsx
  <div className="flex flex-col md:grid md:grid-cols-3 gap-6 p-6 bg-slate-900 text-white rounded-xl shadow-2xl">
  ```

---

## 2. Firestore Access & Security

- **Trigger: Admin / Service Account Init** -> Load from `process.env.FIREBASE_SERVICE_ACCOUNT` (set via Vercel Env Var / GitHub Actions Secret).
  - *Constraint: Never hardcode or commit credentials.*
  - *Constraint: Throw a clear, actionable error if missing.*
```javascript
import { initializeApp, cert, getApps } from 'firebase-admin/app';
if (!getApps().length) {
  if (!process.env.FIREBASE_SERVICE_ACCOUNT) {
    throw new Error('FIREBASE_SERVICE_ACCOUNT is not set. Run local bootstrap form (live-dev-config Sec 2.2).');
  }
  initializeApp({ credential: cert(JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT)) });
}
```
- **Trigger: Client SDK usage** -> Validate all requests against Firebase Security Rules. Avoid client-side mutations on sensitive tables.

---

## 3. Test Isolation & Firestore Emulator

- **Trigger: Playwright QA Runs** -> Isolate from real project using Firebase Local Emulator Suite.

| Area | Requirement / Code | Constraint |
| --- | --- | --- |
| **Setup** | Run `firebase init firestore --project <id>` or declare `emulators.firestore.port` (8080) and `firestore.rules` in `firebase.json`. | Must exist before deploy or emulator run. |
| **Client Connection** | Connect to emulator if `NEXT_PUBLIC_USE_FIRESTORE_EMULATOR` is true: <br>```javascript const db = getFirestore(app); if (process.env.NEXT_PUBLIC_USE_FIRESTORE_EMULATOR === 'true' && !globalThis.__firestoreEmulatorConnected) { connectFirestoreEmulator(db, '127.0.0.1', 8080); globalThis.__firestoreEmulatorConnected = true; } ``` | Guard connection to prevent Strict Mode / Fast Refresh crashes. |
| **Startup & Env** | Run: <br>`NEXT_PUBLIC_USE_FIRESTORE_EMULATOR=true npx firebase emulators:exec --only firestore "npx playwright test"` | Env flag must be set outermost so grandchild processes inherit it. |
| **Seeding** | Seed via Admin SDK using `FIRESTORE_EMULATOR_HOST=127.0.0.1:8080` in `globalSetup`. | Emulator state resets on stop; do not assume prior data survives. |

- **Trigger: Data fetching** -> Return clean, desensitized data arrays:
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
