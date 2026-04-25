#!/usr/bin/env node
// screenshot-axe-hook.js — PostToolUse hook that logs the screenshot path
// after every browser_take_screenshot call.
//
// This is a best-effort logger only: a hook can't reach back into the live
// Playwright session to run a real axe scan. The log is consumed by
// /design-qa:a11y when the user wants a follow-up pass.
//
// Disable via reviewer.json `hooks: false`.
//
// CommonJS so it runs under plain `node` regardless of the surrounding
// package.json `type` setting.

'use strict';

const { existsSync, readFileSync, mkdirSync, writeFileSync } = require('node:fs');
const { join } = require('node:path');

let payload;
try {
  payload = JSON.parse(readFileSync(0, 'utf8'));
} catch {
  // No stdin payload — exit silently
  process.exit(0);
}

if (!payload.tool_name || !payload.tool_name.includes('browser_take_screenshot')) {
  process.exit(0);
}

const reviewerPath = join(process.cwd(), '.claude/design-qa/reviewer.json');
if (existsSync(reviewerPath)) {
  try {
    const reviewer = JSON.parse(readFileSync(reviewerPath, 'utf8'));
    if (reviewer.hooks === false) process.exit(0);
  } catch { /* ignore */ }
}

const screenshotPath = payload.tool_response?.path || payload.tool_input?.path;
if (!screenshotPath) process.exit(0);

const logDir = join(process.cwd(), '.claude/design-qa/hook-log');
mkdirSync(logDir, { recursive: true });

// Strip query strings from logged URLs — they may carry bypass tokens.
const rawUrl = payload.tool_input?.url || null;
const safeUrl = rawUrl ? String(rawUrl).split('?')[0] : null;

const logEntry = {
  ts: new Date().toISOString(),
  screenshot: screenshotPath,
  url: safeUrl,
  note: 'Screenshot captured. Run /design-qa:a11y on the same URL for an accessibility scan.'
};

writeFileSync(
  join(logDir, `${Date.now()}.json`),
  JSON.stringify(logEntry, null, 2)
);

process.exit(0);
