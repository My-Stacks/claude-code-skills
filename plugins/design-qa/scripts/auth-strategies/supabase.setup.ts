// playwright/auth.setup.ts
// Auth strategy: Supabase Auth
//
// Prerequisites:
// 1. Create a test user in Supabase Auth (Dashboard → Authentication → Users → Add user).
// 2. Install: npm i -D @supabase/supabase-js
// 3. Set env vars:
//    - DESIGN_QA_SUPABASE_URL (your project URL)
//    - DESIGN_QA_SUPABASE_ANON_KEY
//    - DESIGN_QA_TEST_EMAIL
//    - DESIGN_QA_TEST_PASSWORD
//    - DESIGN_QA_BASE_URL (the app URL, where Supabase cookies should land)

import { test as setup } from '@playwright/test';
import { createClient } from '@supabase/supabase-js';
import path from 'node:path';

const authFile = path.join(__dirname, '.auth/user.json');

setup('authenticate via Supabase Auth', async ({ page }) => {
  const supabaseUrl = process.env.DESIGN_QA_SUPABASE_URL;
  const anonKey = process.env.DESIGN_QA_SUPABASE_ANON_KEY;
  const email = process.env.DESIGN_QA_TEST_EMAIL;
  const password = process.env.DESIGN_QA_TEST_PASSWORD;
  const baseUrl = process.env.DESIGN_QA_BASE_URL;

  if (!supabaseUrl || !anonKey || !email || !password || !baseUrl) {
    throw new Error('Missing required env vars. See file header for the list.');
  }

  // Sign in via the Supabase JS client
  const supabase = createClient(supabaseUrl, anonKey);
  const { data, error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) throw error;
  if (!data.session) throw new Error('Supabase sign-in succeeded but session is null');

  // Visit the app to establish origin, then inject the session into localStorage
  // (Supabase JS client stores session under a key derived from the project URL)
  await page.goto(baseUrl);
  await page.evaluate(({ session, url }) => {
    const projectId = new URL(url).hostname.split('.')[0];
    const key = `sb-${projectId}-auth-token`;
    localStorage.setItem(key, JSON.stringify(session));
  }, { session: data.session, url: supabaseUrl });

  // Reload to let the app pick up the session
  await page.reload();

  await page.context().storageState({ path: authFile });
});
