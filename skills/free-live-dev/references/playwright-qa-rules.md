# Playwright QA Guidelines

## 1. Setup & Configuration

- **Trigger: Configure test runner** -> Edit `playwright.config.ts`:
```javascript
export default {
  use: { baseURL: 'http://localhost:3000', trace: 'retain-on-failure' },
  webServer: {
    command: 'npm run dev',
    url: 'http://localhost:3000',
    reuseExistingServer: !process.env.CI,
    timeout: 120000,
  },
};
```
- **Trigger: Local execution** -> Verify port (from `package.json` or `.env` `PORT`, default `3000`) is free before running:
  ```bash
  npx playwright test
  ```
  *(Constraint: Never run dev server manually or background it; let `webServer` manage lifecycle.)*

---

## 2. Self-Healing Loop

- **Trigger: Test fails (exit code !== 0)** -> Execute self-healing sequence (max 3 attempts):

| Phase | Action | Constraint / Tool |
|---|---|---|
| **1. Analyze** | Read stdout/stderr and HTML traces in `test-results/`. | Use `retain-on-failure` traces; do not rely on stdout alone. |
| **2. Inspect** | Verify DOM selectors, event handlers, and state transitions. | Inspect DOM/network snapshots. |
| **3. Fix** | Modify implementation code only. | **Hard Rule**: Never weaken, delete, or skip assertions to force PASS. |
| **4. Validate**| Re-run `npx playwright test`. | Halt and report to user if failures persist after 3 loops. |

- **Trigger: Test expectation itself is wrong** -> Halt and report to user. Do not edit test.

---

## 3. Smoke Test Template

- **Trigger: New project / Smoke test check** -> Create/verify:
```javascript
import { test, expect } from '@playwright/test';

test('Smoke Test - Critical Flow', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('input[type="text"]')).toBeVisible();
  await expect(page.locator('button[type="submit"]')).toBeEnabled();
  await page.fill('input[type="text"]', 'Hello Agent');
  await page.click('button[type="submit"]');
  await expect(page.locator('.chat-messages')).toContainText('Hello Agent');
});
```
