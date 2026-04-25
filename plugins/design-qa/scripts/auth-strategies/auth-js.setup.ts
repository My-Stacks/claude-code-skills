// playwright/auth.setup.ts
// Auth strategy: Auth.js / NextAuth
//
// Prerequisites:
// 1. Have a credentials provider configured (or use a dev-only API endpoint).
// 2. Set env vars:
//    - DESIGN_QA_BASE_URL (e.g. https://my-app-preview.vercel.app)
//    - DESIGN_QA_TEST_EMAIL
//    - DESIGN_QA_TEST_PASSWORD
//
// This template uses the credentials flow. For OAuth (Google/GitHub), authenticate
// once interactively then save the storage state — but be aware OAuth providers may
// IP-ban your CI runner.

import { test as setup, expect } from '@playwright/test';
import path from 'node:path';

const authFile = path.join(__dirname, '.auth/user.json');

setup('authenticate via Auth.js credentials', async ({ page }) => {
  const baseUrl = process.env.DESIGN_QA_BASE_URL;
  if (!baseUrl) throw new Error('DESIGN_QA_BASE_URL must be set');
  if (!process.env.DESIGN_QA_TEST_EMAIL || !process.env.DESIGN_QA_TEST_PASSWORD) {
    throw new Error('DESIGN_QA_TEST_EMAIL and DESIGN_QA_TEST_PASSWORD must be set');
  }

  // Adjust selectors to match your sign-in form
  await page.goto(`${baseUrl}/api/auth/signin`);
  await page.fill('input[name="email"]', process.env.DESIGN_QA_TEST_EMAIL);
  await page.fill('input[name="password"]', process.env.DESIGN_QA_TEST_PASSWORD);
  await page.click('button[type="submit"]');

  // Wait for redirect away from the signin page
  await page.waitForURL(/^(?!.*\/api\/auth\/signin).*/, { timeout: 10000 });

  // Verify session cookie was set
  const cookies = await page.context().cookies();
  const sessionCookie = cookies.find(c =>
    c.name.includes('next-auth.session-token') ||
    c.name.includes('authjs.session-token') ||
    c.name.includes('__Secure-next-auth.session-token')
  );
  if (!sessionCookie) {
    throw new Error('No Auth.js session cookie found after login. Check selectors and credentials.');
  }

  await page.context().storageState({ path: authFile });
});
