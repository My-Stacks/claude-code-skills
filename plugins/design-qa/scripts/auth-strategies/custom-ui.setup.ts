// playwright/auth.setup.ts
// Auth strategy: Custom UI flow
//
// Use ONLY when API-based auth isn't possible (e.g. SAML, magic links, MFA).
// Customize the selectors below to match your app's login form.
//
// Prerequisites:
// 1. The app must allow username+password sign-in for at least the test user.
// 2. Set env vars:
//    - DESIGN_QA_BASE_URL
//    - DESIGN_QA_LOGIN_PATH (e.g. /login)
//    - DESIGN_QA_TEST_EMAIL
//    - DESIGN_QA_TEST_PASSWORD

import { test as setup, expect } from '@playwright/test';
import path from 'node:path';

const authFile = path.join(__dirname, '.auth/user.json');

setup('authenticate via UI', async ({ page }) => {
  const baseUrl = process.env.DESIGN_QA_BASE_URL;
  const loginPath = process.env.DESIGN_QA_LOGIN_PATH ?? '/login';
  if (!baseUrl) throw new Error('DESIGN_QA_BASE_URL must be set');

  await page.goto(`${baseUrl}${loginPath}`);

  // ⚠️ CUSTOMIZE: replace with your actual selectors
  await page.fill('input[type="email"], input[name="email"]', process.env.DESIGN_QA_TEST_EMAIL!);
  await page.fill('input[type="password"], input[name="password"]', process.env.DESIGN_QA_TEST_PASSWORD!);
  await page.click('button[type="submit"]');

  // Wait for some signal that login succeeded — customize this
  // Examples:
  //   await page.waitForURL(`${baseUrl}/dashboard`);
  //   await expect(page.locator('[data-testid="user-menu"]')).toBeVisible();
  await page.waitForURL(url => !url.pathname.startsWith(loginPath), { timeout: 10000 });

  await page.context().storageState({ path: authFile });
});
