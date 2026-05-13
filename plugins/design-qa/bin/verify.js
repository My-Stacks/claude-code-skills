#!/usr/bin/env node
// verify.js — sanity check that design-qa dependencies are installed and importable.
//
// Honors DESIGN_QA_INSTALL_TIER (default: full):
//   - minimum: Playwright + axe required; Lighthouse + Pa11y NOT required.
//   - full:    everything required.

const TIER = process.env.DESIGN_QA_INSTALL_TIER || 'full';

// Mirror install.sh's tier validation. Without this, a typo like `minimum_`
// silently falls through to the full-tier check list and marks a clean
// minimum install as broken.
if (TIER !== 'minimum' && TIER !== 'full') {
  console.error(`DESIGN_QA_INSTALL_TIER must be 'minimum' or 'full'; got '${TIER}'`);
  process.exit(1);
}

const minimumChecks = [
  { name: '@playwright/test', test: () => require.resolve('@playwright/test') },
  { name: '@axe-core/playwright', test: () => require.resolve('@axe-core/playwright') },
  { name: 'axe-core', test: () => require.resolve('axe-core') }
];

const fullExtraChecks = [
  { name: 'lighthouse', test: () => require.resolve('lighthouse') },
  { name: 'chrome-launcher', test: () => require.resolve('chrome-launcher') },
  { name: 'pa11y', test: () => require.resolve('pa11y') }
];

const checks = TIER === 'minimum'
  ? minimumChecks
  : [...minimumChecks, ...fullExtraChecks];

const optional = [
  { name: '@argos-ci/playwright', test: () => require.resolve('@argos-ci/playwright') },
  { name: '@argos-ci/cli', test: () => require.resolve('@argos-ci/cli') }
];

let failures = 0;
console.log(`design-qa: verifying installed packages (tier: ${TIER})\n`);

for (const { name, test } of checks) {
  try {
    test();
    console.log(`  ✅ ${name}`);
  } catch (e) {
    console.log(`  ❌ ${name} — ${e.message.split('\n')[0]}`);
    failures++;
  }
}

if (TIER === 'minimum') {
  console.log('\nNot required at this tier (DESIGN_QA_INSTALL_TIER=minimum):');
  for (const { name } of fullExtraChecks) {
    console.log(`  · ${name} (skipped)`);
  }
}

console.log('\nOptional:');
for (const { name, test } of optional) {
  try {
    test();
    console.log(`  ✅ ${name}`);
  } catch {
    console.log(`  · ${name} (not installed)`);
  }
}

// Surface an outdated playwright-lighthouse install only when it's actually
// present — the plugin drives Lighthouse via chrome-launcher directly.
try {
  require.resolve('playwright-lighthouse');
  console.log('\n  ℹ️  playwright-lighthouse is installed but the plugin no longer uses it; safe to remove.');
} catch { /* not installed, nothing to say */ }

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
  console.log(`\n✅ design-qa is ready (tier: ${TIER}).`);
}
