#!/usr/bin/env node
// reporters/json.mjs — combine all sub-reports into a single report.json for CI gates.

import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';

const REPORT_DIR = process.argv[2];
if (!REPORT_DIR) { console.error('usage: json.mjs <reportDir>'); process.exit(1); }

// tryRead returns one of three states so the gate can tell "scan was not run"
// (null) apart from "scan ran but produced no readable output" (corrupt).
// A corrupt artifact must NOT be silently treated as a clean pass.
function tryRead(p) {
  if (!existsSync(p)) return { status: 'missing', data: null };
  try { return { status: 'ok', data: JSON.parse(readFileSync(p, 'utf8')) }; }
  catch (e) { return { status: 'corrupt', data: null, error: e.message }; }
}

const sweep = tryRead(join(REPORT_DIR, 'manifest.json'));
const lh = tryRead(join(REPORT_DIR, 'lighthouse', 'summary.json'));
const axe = tryRead(join(REPORT_DIR, 'axe', 'summary.json'));
const seo = tryRead(join(REPORT_DIR, 'seo', 'report.json'));

const combined = {
  reportDir: REPORT_DIR,
  generatedAt: new Date().toISOString(),
  responsiveSweep: sweep.data,
  lighthouse: lh.data,
  axe: axe.data,
  seo: seo.data,
  argosBuildUrl: existsSync(join(REPORT_DIR, 'argos-build-url.txt'))
    ? readFileSync(join(REPORT_DIR, 'argos-build-url.txt'), 'utf8').trim()
    : null,
  artifactStatus: {
    responsiveSweep: sweep.status,
    lighthouse: lh.status,
    axe: axe.status,
    seo: seo.status
  }
};

const gates = {
  noBlockers: true,
  lcpUnder4s: true,
  perfScoreOver50: true,
  noOverflowAtStandardWidths: true,
  noCorruptArtifacts: true
};

// Corrupt artifacts fail the gate so a broken run can't pass CI silently.
const corrupt = Object.entries(combined.artifactStatus).filter(([, s]) => s === 'corrupt');
if (corrupt.length > 0) {
  gates.noCorruptArtifacts = false;
}

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
if (corrupt.length > 0) {
  console.error(`[json] corrupt artifacts: ${corrupt.map(([k]) => k).join(', ')}`);
}

if (!combined.passed) process.exit(1);
