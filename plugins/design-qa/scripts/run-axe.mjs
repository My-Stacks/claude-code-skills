#!/usr/bin/env node
// run-axe.mjs — axe-core scan at 3 widths × 2 themes × default+hover+focus states.

import { chromium } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import { mkdirSync, writeFileSync, existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

const URL = process.env.DESIGN_QA_URL;
const REPORT_DIR = process.env.DESIGN_QA_REPORT_DIR;
const BYPASS = process.env.DESIGN_QA_BYPASS || '';

if (!URL || !REPORT_DIR) {
  console.error('DESIGN_QA_URL and DESIGN_QA_REPORT_DIR are required');
  process.exit(1);
}

const REVIEWER_PATH = join(process.cwd(), '.claude/design-qa/reviewer.json');
let excludeRules = [];
if (existsSync(REVIEWER_PATH)) {
  try {
    const reviewer = JSON.parse(readFileSync(REVIEWER_PATH, 'utf8'));
    excludeRules = reviewer.excludeRules || [];
  } catch (e) {
    console.warn(`[axe] could not parse reviewer.json: ${e.message}`);
  }
}

const widths = [
  { w: 375, h: 812, label: 'mobile' },
  { w: 768, h: 1024, label: 'tablet' },
  { w: 1440, h: 900, label: 'desktop' }
];

const themes = [
  { name: 'light', colorScheme: 'light' },
  { name: 'dark', colorScheme: 'dark' }
];

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
      await page.evaluate(() => document.fonts.ready);

      // 1. Default-state scan
      const defaultBuilder = new AxeBuilder({ page })
        .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa', 'best-practice']);
      if (excludeRules.length > 0) defaultBuilder.disableRules(excludeRules);
      const defaultResult = await defaultBuilder.analyze();

      writeFileSync(
        join(REPORT_DIR, 'axe', `${label}-${theme.name}-default.json`),
        JSON.stringify(defaultResult, null, 2)
      );

      for (const v of defaultResult.violations) {
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

      const hoverBuilder = new AxeBuilder({ page })
        .withTags(['wcag2a', 'wcag2aa', 'wcag22aa']);
      if (excludeRules.length > 0) hoverBuilder.disableRules(excludeRules);
      const hoverResult = await hoverBuilder.analyze();

      writeFileSync(
        join(REPORT_DIR, 'axe', `${label}-${theme.name}-hover.json`),
        JSON.stringify(hoverResult, null, 2)
      );

      // Only surface NEW violations introduced by hover state
      const defaultIds = new Set(defaultResult.violations.flatMap(v => v.nodes.map(n => v.id + '|' + n.target.join(','))));
      for (const v of hoverResult.violations) {
        for (const node of v.nodes) {
          const id = v.id + '|' + node.target.join(',');
          if (!defaultIds.has(id)) {
            allFindings.push({ id: v.id, impact: v.impact, description: v.description, helpUrl: v.helpUrl, nodes: [node], viewport: label, theme: theme.name, state: 'hover' });
          }
        }
      }

      // 3. Focus state — keyboard-tab through 10 elements
      for (let i = 0; i < 10; i++) {
        await page.keyboard.press('Tab');
        await page.waitForTimeout(30);
      }

      const focusBuilder = new AxeBuilder({ page })
        .withTags(['wcag2a', 'wcag2aa', 'wcag22aa']);
      if (excludeRules.length > 0) focusBuilder.disableRules(excludeRules);
      const focusResult = await focusBuilder.analyze();

      writeFileSync(
        join(REPORT_DIR, 'axe', `${label}-${theme.name}-focus.json`),
        JSON.stringify(focusResult, null, 2)
      );

      for (const v of focusResult.violations) {
        for (const node of v.nodes) {
          const id = v.id + '|' + node.target.join(',');
          if (!defaultIds.has(id)) {
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

// Aggregate
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
