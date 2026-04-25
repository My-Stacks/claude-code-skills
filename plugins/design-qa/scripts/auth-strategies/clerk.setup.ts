// playwright/auth.setup.ts
// Auth strategy: Clerk (https://clerk.com)
//
// Prerequisites:
// 1. Use Clerk in development/preview mode (not production).
// 2. Create a test user in Clerk dashboard with username/password auth enabled.
//    Clerk OAuth flows cannot be automated; you need a credentials-based test user.
// 3. Install: npm i -D @clerk/testing
// 4. Set env vars:
//    - CLERK_PUBLISHABLE_KEY (from Clerk dashboard, dev instance)
//    - CLERK_SECRET_KEY (from Clerk dashboard, dev instance)
//    - DESIGN_QA_TEST_EMAIL
//    - DESIGN_QA_TEST_PASSWORD

import { test as setup, expect } from '@playwright/test';
import { clerk, clerkSetup } from '@clerk/testing/playwright';
import { mkdirSync } from 'node:fs';
import path from 'node:path';

const authFile = path.join(__dirname, '.auth/user.json');

setup('authenticate via Clerk', async ({ page }) => {
  await clerkSetup();

  if (!process.env.DESIGN_QA_TEST_EMAIL || !process.env.DESIGN_QA_TEST_PASSWORD) {
    throw new Error('DESIGN_QA_TEST_EMAIL and DESIGN_QA_TEST_PASSWORD must be set');
  }

  mkdirSync(path.dirname(authFile), { recursive: true });

  // Warn if email looks production-shaped
  const email = process.env.DESIGN_QA_TEST_EMAIL;
  if (!email.includes('+test') && !email.includes('+qa') && !email.match(/^test/i)) {
    console.warn(`[auth] WARNING: ${email} does not look like a test account. Use a test user.`);
  }

  await page.goto(process.env.DESIGN_QA_BASE_URL ?? 'http://localhost:3000');

  await clerk.signIn({
    page,
    signInParams: {
      strategy: 'password',
      identifier: email,
      password: process.env.DESIGN_QA_TEST_PASSWORD!
    }
  });

  // Verify signed in
  await expect(page.locator('body')).toBeVisible();

  await page.context().storageState({ path: authFile });
});
