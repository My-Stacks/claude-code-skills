// playwright.config.ts — design-qa template
//
// Drop this in the project root if no playwright.config exists.
// If one exists, merge the `projects` array.

import { defineConfig, devices } from '@playwright/test';
import path from 'node:path';

export default defineConfig({
  testDir: '.claude/design-qa/playwright-tests',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  reporter: [['list'], ['html', { open: 'never', outputFolder: '.claude/design-qa/playwright-report' }]],

  use: {
    baseURL: process.env.DESIGN_QA_BASE_URL,
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    extraHTTPHeaders: process.env.VERCEL_AUTOMATION_BYPASS_SECRET
      ? {
          'x-vercel-protection-bypass': process.env.VERCEL_AUTOMATION_BYPASS_SECRET,
          'x-vercel-set-bypass-cookie': 'true'
        }
      : undefined
  },

  projects: [
    // Auth setup runs first when DESIGN_QA_AUTH is set
    ...(process.env.DESIGN_QA_AUTH
      ? [{
          name: 'setup',
          testMatch: /auth\.setup\.ts/
        }]
      : []),

    {
      name: 'chromium-desktop',
      use: {
        ...devices['Desktop Chrome'],
        viewport: { width: 1440, height: 900 },
        ...(process.env.DESIGN_QA_AUTH
          ? { storageState: path.join(__dirname, 'playwright/.auth/user.json') }
          : {})
      },
      dependencies: process.env.DESIGN_QA_AUTH ? ['setup'] : []
    },

    {
      name: 'chromium-mobile',
      use: {
        ...devices['iPhone 14 Pro'],
        ...(process.env.DESIGN_QA_AUTH
          ? { storageState: path.join(__dirname, 'playwright/.auth/user.json') }
          : {})
      },
      dependencies: process.env.DESIGN_QA_AUTH ? ['setup'] : []
    }
  ],

  expect: {
    toHaveScreenshot: {
      maxDiffPixelRatio: 0.01,
      threshold: 0.2
    }
  }
});
