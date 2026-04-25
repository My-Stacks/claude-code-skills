#!/usr/bin/env node
// run-axe.mjs — axe-core scan at 3 widths × 2 themes × default+hover+focus states.

import { chromium } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import { mkdirSync, writeFileSync, existsSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';

const URL = process.env.DESIGN_QA_URL;
const REPORT_DIR = process.env.DESIGN_QA_REPORT_DIR;
const BYPASS = process.env.DESIGN_QA_BYPASS || '';

if (!URL || !REPORT_DIR) {
  console.error('DESIGN_QA_URL and DESIGN_QA_REPORT_DIR are required');
  process.exit(1);
}

const cwd = process.cwd();
const resolvedReportDir = resolve(cwd, REPORT_DIR);
if (!resolvedReportDir.startsWith(cwd + '/') && resolvedReportDir !== cwd) {
  console.error(`DESIGN_QA_REPORT_DIR must stay inside the workspace; got ${resolvedReportDir}`);
  process.exit(1);
}

mkdirSync(join(REPORT_DIR, 'axe'), { recursive: true });

const REVIEWER_PATH = join(cwd, '.claude/design-qa/reviewer.json');
let excludeRules = [];
if (existsSync(REVIEWER_PATH)) {
  try {
    const reviewer = JSON.parse(readFileSync(REVIEWER_PATH, 'utf8'));
    excludeRules = reviewer.excludeRules || [];
  } catch (e) {
    console.warn(`[axe] could not parse reviewer.json: ${e.message}`);
  }
}

// Apply the same WCAG tag set on every pass — hover/focus regressions in 2.1/2.2
// rules were silently dropped before because their tags weren't requested.
const WCAG_TAGS = ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa', 'best-practice'];

const widths = [
  { w: 375, h: 812, label: 'mobile' },
  { w: 768, h: 1024, label: 'tablet' },
  { w: 1440, h: 900, label: 'desktop' }
];

const themes = [
  { name: 'light', colorScheme: 'light' },
  { name: 'dark', colorScheme: 'dark' }
];

// Stable, collision-proof key for a (rule, node-target) pair. The previous
// `target.join(',')` collapsed when CSS selectors themselves contained commas
// (e.g. `:is(a, button)`), silently merging unrelated findings.
const findingKey = (ruleId, target) => `${ruleId}|${JSON.stringify(target)}`;

const allFindings = [];
const browser = await chromium.launch({ headless: true });

for (const { w, h, label } of widths) {
  for (const theme of themes) {
    console.log(`[axe] ${label} (${w}x${h}) ${theme.name}...`);

    const context = await browser.newContext({
      viewport: { width: w, height: h },
      colorScheme: theme.colorScheme,
      extraHTTPHeaders: BYPASS ? {
        'x-vercel-protection-bypass': BYPASS,
        'x-vercel-set-bypass-cookie': 'true'
      } : {}
    });
    const page = await context.newPage();

    try {
      await page.goto(URL, { waitUntil: 'networkidle', timeout: 30000 });
      await page.evaluate(() => (document.fonts?.ready ?? Promise.resolve()));

      // 1. Default-state scan
      const defaultBuilder = new AxeBuilder({ page }).withTags(WCAG_TAGS);
      if (excludeRules.length > 0) defaultBuilder.disableRules(excludeRules);
      const defaultResult = await defaultBuilder.analyze();

      writeFileSync(
        join(REPORT_DIR, 'axe', `${label}-${theme.name}-default.json`),
        JSON.stringify(defaultResult, null, 2)
      );

      const defaultKeys = new Set();
      for (const v of defaultResult.violations) {
        for (const node of v.nodes) {
          defaultKeys.add(findingKey(v.id, node.target));
        }
        allFindings.push({ ...v, viewport: label, theme: theme.name, state: 'default' });
      }

      // 2. Hover state — sample first 10 interactive elements
      const interactives = await page.$$('a, button, [role=button], input, select, textarea');
      const sampled = interactives.slice(0, 10);

      for (let i = 0; i < sampled.length; i++) {
        try {
          await sampled[i].hover({ timeout: 1000 });
          await page.waitForTimeout(50);
        } catch { /* element may have disappeared; ignore */ }
      }

      const hoverBuilder = new AxeBuilder({ page }).withTags(WCAG_TAGS);
      if (excludeRules.length > 0) hoverBuilder.disableRules(excludeRules);
      const hoverResult = await hoverBuilder.analyze();

      writeFileSync(
        join(REPORT_DIR, 'axe', `${label}-${theme.name}-hover.json`),
        JSON.stringify(hoverResult, null, 2)
      );

      // Hover-only = violations not seen in the default-state scan.
      const hoverKeys = new Set();
      for (const v of hoverResult.violations) {
        for (const node of v.nodes) {
          const key = findingKey(v.id, node.target);
          hoverKeys.add(key);
          if (!defaultKeys.has(key)) {
            allFindings.push({ id: v.id, impact: v.impact, description: v.description, helpUrl: v.helpUrl, nodes: [node], viewport: label, theme: theme.name, state: 'hover' });
          }
        }
      }

      // 3. Focus state — keyboard-tab through 10 elements
      for (let i = 0; i < 10; i++) {
        await page.keyboard.press('Tab');
        await page.waitForTimeout(30);
      }

      const focusBuilder = new AxeBuilder({ page }).withTags(WCAG_TAGS);
      if (excludeRules.length > 0) focusBuilder.disableRules(excludeRules);
      const focusResult = await focusBuilder.analyze();

      writeFileSync(
        join(REPORT_DIR, 'axe', `${label}-${theme.name}-focus.json`),
        JSON.stringify(focusResult, null, 2)
      );

      // Focus-only = not in default AND not in hover. Without comparing to
      // hover, "focus-only" findings labelled as such included things that
      // were really hover regressions visible during the focus pass too.
      for (const v of focusResult.violations) {
        for (const node of v.nodes) {
          const key = findingKey(v.id, node.target);
          if (!defaultKeys.has(key) && !hoverKeys.has(key)) {
            allFindings.push({ id: v.id, impact: v.impact, description: v.description, helpUrl: v.helpUrl, nodes: [node], viewport: label, theme: theme.name, state: 'focus' });
          }
        }
      }
    } catch (e) {
      console.error(`[axe] ${label}/${theme.name} failed: ${e.message}`);
    } finally {
      await context.close();
    }
  }
}

await browser.close();

const summary = {
  url: URL,
  totalFindings: allFindings.length,
  byImpact: {
    critical: allFindings.filter(f => f.impact === 'critical').length,
    serious: allFindings.filter(f => f.impact === 'serious').length,
    moderate: allFindings.filter(f => f.impact === 'moderate').length,
    minor: allFindings.filter(f => f.impact === 'minor').length
  },
  byState: {
    default: allFindings.filter(f => f.state === 'default').length,
    hover: allFindings.filter(f => f.state === 'hover').length,
    focus: allFindings.filter(f => f.state === 'focus').length
  },
  excludedRules: excludeRules,
  findings: allFindings
};

writeFileSync(join(REPORT_DIR, 'axe', 'summary.json'), JSON.stringify(summary, null, 2));

console.log(`\n[axe] total findings: ${summary.totalFindings}`);
console.log(`  critical: ${summary.byImpact.critical}`);
console.log(`  serious: ${summary.byImpact.serious}`);
console.log(`  moderate: ${summary.byImpact.moderate}`);
console.log(`  minor: ${summary.byImpact.minor}`);
console.log(`  hover-only: ${summary.byState.hover}`);
console.log(`  focus-only: ${summary.byState.focus}`);
