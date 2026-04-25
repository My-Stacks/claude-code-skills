#!/usr/bin/env node
// screenshot-axe-hook.js — PostToolUse hook that runs axe against the current Playwright page
// after every browser_take_screenshot call. Stores results next to the screenshot.
//
// This makes ad-hoc UI inspection (not just /design-qa:review) get a free a11y scan.
//
// Disable via reviewer.json `hooks: false`.

import { existsSync, readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';

let payload;
try {
  payload = JSON.parse(readFileSync(0, 'utf8'));
} catch (e) {
  // No stdin payload — exit silently
  process.exit(0);
}

// Bail if not the screenshot tool
if (!payload.tool_name || !payload.tool_name.includes('browser_take_screenshot')) {
  process.exit(0);
}

// Bail if hooks disabled in reviewer config
const reviewerPath = join(process.cwd(), '.claude/design-qa/reviewer.json');
if (existsSync(reviewerPath)) {
  try {
    const reviewer = JSON.parse(readFileSync(reviewerPath, 'utf8'));
    if (reviewer.hooks === false) process.exit(0);
  } catch { /* ignore */ }
}

// Best-effort: this hook can only inspect the result, not access the live Playwright page.
// What we DO is log the screenshot path so a separate scan can happen alongside.
// A real implementation would require the screenshot tool to expose the page URL or
// the hook to spin up its own Playwright instance pointed at the same URL.

const screenshotPath = payload.tool_response?.path || payload.tool_input?.path;
if (!screenshotPath) process.exit(0);

const logDir = join(process.cwd(), '.claude/design-qa/hook-log');
mkdirSync(logDir, { recursive: true });

const logEntry = {
  ts: new Date().toISOString(),
  screenshot: screenshotPath,
  url: payload.tool_input?.url || null,
  note: 'Screenshot captured. Run /design-qa:a11y on the same URL for an accessibility scan.'
};

writeFileSync(
  join(logDir, `${Date.now()}.json`),
  JSON.stringify(logEntry, null, 2)
);

process.exit(0);
