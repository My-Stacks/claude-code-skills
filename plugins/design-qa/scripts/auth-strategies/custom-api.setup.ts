// playwright/auth.setup.ts
// Auth strategy: Custom API
//
// Use when your app exposes a programmatic auth endpoint (e.g. POST /api/login → cookie).
// This is 10× faster than UI-based login and far less brittle.
//
// Prerequisites:
// 1. The app must accept email/password at a known endpoint and return cookies.
//    (If you authenticate via token instead, fork this template — the v0.1
//    shipped flow only handles credential-based login.)
// 2. Set env vars:
//    - DESIGN_QA_BASE_URL
//    - DESIGN_QA_TEST_EMAIL
//    - DESIGN_QA_TEST_PASSWORD

import { test as setup } from '@playwright/test';
import { mkdirSync } from 'node:fs';
import path from 'node:path';

const authFile = path.join(__dirname, '.auth/user.json');

setup('authenticate via custom API', async ({ playwright }) => {
  const baseUrl = process.env.DESIGN_QA_BASE_URL;
  const email = process.env.DESIGN_QA_TEST_EMAIL;
  const password = process.env.DESIGN_QA_TEST_PASSWORD;
  if (!baseUrl) throw new Error('DESIGN_QA_BASE_URL must be set');
  if (!email || !password) {
    throw new Error('DESIGN_QA_TEST_EMAIL and DESIGN_QA_TEST_PASSWORD must be set');
  }

  mkdirSync(path.dirname(authFile), { recursive: true });

  const ctx = await playwright.request.newContext({ baseURL: baseUrl });
  try {
    // ⚠️ CUSTOMIZE: replace with your actual login endpoint and payload shape
    const response = await ctx.post('/api/login', {
      data: { email, password }
    });

    if (!response.ok()) {
      // Don't include response.text() — login endpoints often echo the
      // submitted credentials, set-cookie material, or internal stack traces
      // back in the error body. Status alone is enough to debug.
      throw new Error(`Login failed: ${response.status()}`);
    }

    await ctx.storageState({ path: authFile });
  } finally {
    await ctx.dispose();
  }
});
