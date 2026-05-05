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
  noCorruptArtifacts: true,
  // Whether the mobile Lighthouse run looks trustworthy. When a third-party
  // tracker stalls under simulated 4× CPU + Slow 4G, mobile metrics can be
  // wildly off vs desktop. The lighthouse runner sets instrumentationSuspect
  // when mobile metric / desktop metric > 8 — gates demote to advisory.
  mobileMetricsTrusted: true
};

// Corrupt artifacts fail the gate so a broken run can't pass CI silently.
const corrupt = Object.entries(combined.artifactStatus).filter(([, s]) => s === 'corrupt');
if (corrupt.length > 0) {
  gates.noCorruptArtifacts = false;
}

if (combined.lighthouse) {
  const mobileSuspect = combined.lighthouse.mobile?.instrumentationSuspect === true;
  gates.mobileMetricsTrusted = !mobileSuspect;

  // Pick the authoritative source for the metric gates:
  //   - If mobile is instrumentation-suspect, use desktop (a stalled tracker
  //     shouldn't block a PR).
  //   - If mobile is null (run failed but didn't fail hard), fall back to
  //     desktop so we still gate on something real instead of skipping.
  //   - Otherwise use mobile, which Google ranks against.
  const lhSource = (mobileSuspect || !combined.lighthouse.mobile) && combined.lighthouse.desktop
    ? combined.lighthouse.desktop
    : combined.lighthouse.mobile;

  if (lhSource?.metrics?.lcp != null && lhSource.metrics.lcp > 4000) gates.lcpUnder4s = false;
  if (lhSource?.scores?.performance != null && lhSource.scores.performance < 50) gates.perfScoreOver50 = false;
}

if (combined.axe?.byImpact?.critical > 0) gates.noBlockers = false;
if (combined.seo?.findings?.some(f => f.severity === 'blocker')) gates.noBlockers = false;

if (combined.responsiveSweep) {
  const standardOverflows = combined.responsiveSweep.entries
    .filter(e => e.horizontalOverflow && [375, 768, 1024, 1440].includes(e.width));
  if (standardOverflows.length > 0) gates.noOverflowAtStandardWidths = false;
}

// Section anomalies are surfaced but don't gate by default — heuristics with
// false-positive risk shouldn't block CI. Reporters render them prominently.
const sectionAnomalies = (combined.responsiveSweep?.entries || [])
  .flatMap(e => (e.sectionAnomalies || []).map(a => ({ ...a, width: e.width, theme: e.theme })));
const sectionAnomalyDeltas = combined.responsiveSweep?.sectionAnomalyDeltas || [];
combined.sectionAnomalies = {
  perBreakpoint: sectionAnomalies,
  crossBreakpointDeltas: sectionAnomalyDeltas,
  totalCount: sectionAnomalies.length + sectionAnomalyDeltas.length
};

combined.gates = gates;
// `passed` ignores `mobileMetricsTrusted` since that's an advisory flag, not a
// pass/fail criterion — a suspect mobile run shouldn't block when desktop is
// fine.
combined.passed = Object.entries(gates)
  .filter(([k]) => k !== 'mobileMetricsTrusted')
  .every(([, v]) => v);

writeFileSync(join(REPORT_DIR, 'report.json'), JSON.stringify(combined, null, 2));
console.log(`[json] wrote ${join(REPORT_DIR, 'report.json')}, gates passed: ${combined.passed}`);
if (corrupt.length > 0) {
  console.error(`[json] corrupt artifacts: ${corrupt.map(([k]) => k).join(', ')}`);
}

if (!combined.passed) process.exit(1);
