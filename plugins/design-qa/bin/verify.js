#!/usr/bin/env node
// verify.js — sanity check that all design-qa dependencies are installed and importable.

const checks = [
  { name: '@playwright/test', test: () => require.resolve('@playwright/test') },
  { name: '@axe-core/playwright', test: () => require.resolve('@axe-core/playwright') },
  { name: 'axe-core', test: () => require.resolve('axe-core') },
  { name: 'playwright-lighthouse', test: () => require.resolve('playwright-lighthouse') },
  { name: 'lighthouse', test: () => require.resolve('lighthouse') },
  { name: 'pa11y', test: () => require.resolve('pa11y') }
];

const optional = [
  { name: '@argos-ci/playwright', test: () => require.resolve('@argos-ci/playwright') },
  { name: '@argos-ci/cli', test: () => require.resolve('@argos-ci/cli') }
];

let failures = 0;
console.log('design-qa: verifying installed packages\n');

for (const { name, test } of checks) {
  try {
    test();
    console.log(`  ✅ ${name}`);
  } catch (e) {
    console.log(`  ❌ ${name} — ${e.message.split('\n')[0]}`);
    failures++;
  }
}

console.log('\nOptional:');
for (const { name, test } of optional) {
  try {
    test();
    console.log(`  ✅ ${name}`);
  } catch {
    console.log(`  · ${name} (not installed; optional)`);
  }
}

// Check Playwright browsers
try {
  const { chromium } = require('@playwright/test');
  // Lazy: don't actually launch; just confirm executable path resolves
  const path = chromium.executablePath?.();
  if (path) {
    console.log(`\n  ✅ Chromium installed at ${path}`);
  } else {
    console.log('\n  ⚠️  chromium.executablePath() returned empty; run: npx playwright install chromium');
  }
} catch (e) {
  console.log(`\n  ❌ Playwright Chromium check failed: ${e.message}`);
  failures++;
}

if (failures > 0) {
  console.error(`\n${failures} required package(s) missing. Run: bash ${process.env.CLAUDE_PLUGIN_ROOT || '<plugin>'}/bin/install.sh`);
  process.exit(1);
} else {
  console.log('\n✅ design-qa is ready.');
}
