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

import { test as setup } from '@playwright/test';
import { mkdirSync } from 'node:fs';
import path from 'node:path';

// Resolve the auth file relative to the project root (cwd) — keeps the
// template ESM/CJS-agnostic and aligned with playwright.config.template.ts.
const authFile = path.resolve(process.cwd(), 'playwright', '.auth', 'user.json');

// Normalise loginPath to a clean leading-slash form with no query/fragment so
// the success check compares like-for-like against `url.pathname`.
const normalizeLoginPath = (raw: string): string => {
  const withSlash = raw.startsWith('/') ? raw : `/${raw}`;
  const withoutQuery = withSlash.split('?')[0].split('#')[0];
  return withoutQuery.length > 1 ? withoutQuery.replace(/\/+$/, '') : withoutQuery;
};

setup('authenticate via UI', async ({ page }) => {
  const baseUrl = process.env.DESIGN_QA_BASE_URL;
  const loginPath = normalizeLoginPath(process.env.DESIGN_QA_LOGIN_PATH ?? '/login');
  const email = process.env.DESIGN_QA_TEST_EMAIL;
  const password = process.env.DESIGN_QA_TEST_PASSWORD;
  if (!baseUrl) throw new Error('DESIGN_QA_BASE_URL must be set');
  if (!email || !password) {
    throw new Error('DESIGN_QA_TEST_EMAIL and DESIGN_QA_TEST_PASSWORD must be set');
  }

  mkdirSync(path.dirname(authFile), { recursive: true });

  await page.goto(`${baseUrl}${loginPath}`);

  // ⚠️ CUSTOMIZE: replace with your actual selectors
  await page.fill('input[type="email"], input[name="email"]', email);
  await page.fill('input[type="password"], input[name="password"]', password);
  await page.click('button[type="submit"]');

  // Wait for some signal that login succeeded — customize this
  // Examples:
  //   await page.waitForURL(`${baseUrl}/dashboard`);
  //   await expect(page.locator('[data-testid="user-menu"]')).toBeVisible();
  await page.waitForURL(url => url.pathname !== loginPath, { timeout: 10000 });

  await page.context().storageState({ path: authFile });
});
