#!/usr/bin/env node
// reporters/json.mjs — combine all sub-reports into a single report.json for CI gates.

import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';

const REPORT_DIR = process.argv[2];
if (!REPORT_DIR) { console.error('usage: json.mjs <reportDir>'); process.exit(1); }

function tryRead(p) {
  if (!existsSync(p)) return null;
  try { return JSON.parse(readFileSync(p, 'utf8')); } catch { return null; }
}

const combined = {
  reportDir: REPORT_DIR,
  generatedAt: new Date().toISOString(),
  responsiveSweep: tryRead(join(REPORT_DIR, 'manifest.json')),
  lighthouse: tryRead(join(REPORT_DIR, 'lighthouse', 'summary.json')),
  axe: tryRead(join(REPORT_DIR, 'axe', 'summary.json')),
  seo: tryRead(join(REPORT_DIR, 'seo', 'report.json')),
  argosBuildUrl: existsSync(join(REPORT_DIR, 'argos-build-url.txt'))
    ? readFileSync(join(REPORT_DIR, 'argos-build-url.txt'), 'utf8').trim()
    : null
};

// Compute pass/fail for CI gates
const gates = {
  noBlockers: true,
  lcpUnder4s: true,
  perfScoreOver50: true,
  noOverflowAtStandardWidths: true
};

if (combined.lighthouse) {
  if (combined.lighthouse.mobile.metrics.lcp > 4000) gates.lcpUnder4s = false;
  if (combined.lighthouse.mobile.scores.performance < 50) gates.perfScoreOver50 = false;
}

if (combined.axe?.byImpact?.critical > 0) gates.noBlockers = false;
if (combined.seo?.findings?.some(f => f.severity === 'blocker')) gates.noBlockers = false;

if (combined.responsiveSweep) {
  const standardOverflows = combined.responsiveSweep.entries
    .filter(e => e.horizontalOverflow && [375, 768, 1024, 1440].includes(e.width));
  if (standardOverflows.length > 0) gates.noOverflowAtStandardWidths = false;
}

combined.gates = gates;
combined.passed = Object.values(gates).every(v => v);

writeFileSync(join(REPORT_DIR, 'report.json'), JSON.stringify(combined, null, 2));
console.log(`[json] wrote ${join(REPORT_DIR, 'report.json')}, gates passed: ${combined.passed}`);

if (!combined.passed) process.exit(1);
