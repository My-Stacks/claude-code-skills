#!/usr/bin/env node
// breakpoint-sweep.mjs — the responsive breakpoint sweep.
// Drives Playwright directly (more efficient than calling MCP one width at a time).

import { chromium, devices } from '@playwright/test';
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const URL = process.env.DESIGN_QA_URL;
const PRESET = process.env.DESIGN_QA_PRESET || 'agency-default';
const REPORT_DIR = process.env.DESIGN_QA_REPORT_DIR || '.claude/design-qa/reports/latest';
const BYPASS = process.env.DESIGN_QA_BYPASS || '';

if (!URL) {
  console.error('DESIGN_QA_URL is required');
  process.exit(1);
}

const PRESETS = {
  fast: [375, 768, 1024, 1440, 1920],
  'agency-default': [
    280, 320, 360, 375, 390, 414, 480, 600, 700, 768,
    834, 900, 1024, 1180, 1280, 1440, 1920, 2560
  ],
  thorough: [
    280, 320, 360, 375, 384, 390, 414, 480, 600, 700, 768,
    834, 900, 1024, 1180, 1280, 1440, 1920, 2560, 3840
  ]
};

// Map widths to Playwright device descriptors when there's a meaningful match
const DEVICE_HINTS = {
  280: { name: 'Galaxy Fold (folded)', viewport: { width: 280, height: 653 }, dpr: 3, mobile: true, touch: true, ua: devices['Galaxy Note 3']?.userAgent },
  320: { name: 'iPhone SE 1st gen', viewport: { width: 320, height: 568 }, dpr: 2, mobile: true, touch: true },
  360: { name: 'Android baseline', viewport: { width: 360, height: 640 }, dpr: 3, mobile: true, touch: true },
  375: { ...devices['iPhone SE'], name: 'iPhone SE / iPhone 8' },
  390: { ...devices['iPhone 14 Pro'], name: 'iPhone 14 Pro' },
  414: { ...devices['iPhone 11 Pro Max'], name: 'iPhone 11 Pro Max' },
  768: { ...devices['iPad (gen 7)'], name: 'iPad portrait' },
  834: { ...devices['iPad Pro 11'], name: 'iPad Pro 11" portrait' },
  1024: { name: 'iPad landscape / small laptop', viewport: { width: 1024, height: 768 }, dpr: 2, mobile: false, touch: false },
  1280: { name: 'Laptop', viewport: { width: 1280, height: 800 }, dpr: 2, mobile: false, touch: false },
  1440: { name: 'Desktop', viewport: { width: 1440, height: 900 }, dpr: 2, mobile: false, touch: false },
  1920: { name: '1080p desktop', viewport: { width: 1920, height: 1080 }, dpr: 1, mobile: false, touch: false },
  2560: { name: '1440p / 5K-scaled', viewport: { width: 2560, height: 1440 }, dpr: 1, mobile: false, touch: false }
};

const widths = PRESETS[PRESET] || PRESETS['agency-default'];
const themes = PRESET === 'fast'
  ? [{ name: 'light', colorScheme: 'light', reducedMotion: 'no-preference' }]
  : [
      { name: 'light', colorScheme: 'light', reducedMotion: 'no-preference' },
      { name: 'dark', colorScheme: 'dark', reducedMotion: 'no-preference' },
      { name: 'reduced-motion', colorScheme: 'light', reducedMotion: 'reduce' }
    ];

mkdirSync(join(REPORT_DIR, 'screenshots'), { recursive: true });

console.log(`[sweep] ${widths.length} widths × ${themes.length} themes = ${widths.length * themes.length} screenshots`);

const browser = await chromium.launch({ headless: true });
const manifest = { url: URL, preset: PRESET, startedAt: new Date().toISOString(), entries: [] };

let count = 0;
const total = widths.length * themes.length;

for (const w of widths) {
  const hint = DEVICE_HINTS[w] || {
    name: `${w}px`,
    viewport: { width: w, height: Math.round(w * 1.4) },
    dpr: w <= 600 ? 3 : w <= 1024 ? 2 : 1,
    mobile: w <= 600,
    touch: w <= 768
  };

  for (const theme of themes) {
    count++;
    const label = `${w}-${theme.name}`;
    const fileName = `${label}.png`;
    const filePath = join(REPORT_DIR, 'screenshots', fileName);

    process.stdout.write(`[${count}/${total}] ${label}... `);

    const context = await browser.newContext({
      viewport: hint.viewport,
      deviceScaleFactor: hint.dpr,
      isMobile: hint.mobile,
      hasTouch: hint.touch,
      userAgent: hint.userAgent,
      colorScheme: theme.colorScheme,
      reducedMotion: theme.reducedMotion,
      extraHTTPHeaders: BYPASS ? {
        'x-vercel-protection-bypass': BYPASS,
        'x-vercel-set-bypass-cookie': 'true'
      } : {}
    });
    const page = await context.newPage();

    let overflow = null;
    let consoleErrors = [];
    let error = null;

    page.on('console', msg => {
      if (msg.type() === 'error') consoleErrors.push(msg.text());
    });

    try {
      await page.goto(URL, { waitUntil: 'networkidle', timeout: 30000 });
      await page.evaluate(() => document.fonts.ready);

      // Disable animations for stability
      await page.addStyleTag({
        content: `*, *::before, *::after {
          animation-duration: 0s !important;
          animation-delay: 0s !important;
          transition-duration: 0s !important;
          transition-delay: 0s !important;
        }`
      });
      await page.waitForTimeout(200);

      // Horizontal overflow check
      overflow = await page.evaluate(() => ({
        scrollWidth: document.documentElement.scrollWidth,
        clientWidth: document.documentElement.clientWidth,
        overflows: document.documentElement.scrollWidth > document.documentElement.clientWidth
      }));

      await page.screenshot({ path: filePath, fullPage: true });
      console.log('ok' + (overflow.overflows ? ' [OVERFLOW]' : ''));
    } catch (e) {
      error = e.message;
      console.log(`FAIL: ${e.message.split('\n')[0]}`);
    } finally {
      manifest.entries.push({
        width: w,
        deviceLabel: hint.name,
        theme: theme.name,
        dpr: hint.dpr,
        isMobile: hint.mobile,
        hasTouch: hint.touch,
        file: fileName,
        horizontalOverflow: overflow?.overflows ?? null,
        scrollWidth: overflow?.scrollWidth ?? null,
        consoleErrors: consoleErrors.length > 0 ? consoleErrors : undefined,
        error
      });
      await context.close();
    }
  }
}

await browser.close();

manifest.completedAt = new Date().toISOString();
writeFileSync(join(REPORT_DIR, 'manifest.json'), JSON.stringify(manifest, null, 2));

const overflows = manifest.entries.filter(e => e.horizontalOverflow);
const errors = manifest.entries.filter(e => e.error);

console.log(`\n[sweep] complete.`);
console.log(`  total: ${manifest.entries.length}`);
console.log(`  with overflow: ${overflows.length}`);
console.log(`  errors: ${errors.length}`);

if (overflows.length > 0) {
  console.log(`  affected widths: ${[...new Set(overflows.map(e => e.width))].join(', ')}`);
}
