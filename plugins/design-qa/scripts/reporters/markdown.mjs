#!/usr/bin/env node
// reporters/markdown.mjs — generate summary.md from the report directory.

import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';

const REPORT_DIR = process.argv[2];
if (!REPORT_DIR) {
  console.error('usage: markdown.mjs <reportDir>');
  process.exit(1);
}

const sections = [];

// Header
const url = tryRead(join(REPORT_DIR, 'manifest.json'))?.url || 'unknown';
sections.push(`# Design QA: ${url}`);
sections.push(`*Reviewed ${new Date().toISOString()} · report: ${REPORT_DIR}*\n`);

// Lighthouse — guard each profile so a mobile-only or desktop-only run still renders
const lh = tryRead(join(REPORT_DIR, 'lighthouse', 'summary.json'));
if (lh) {
  const m = lh.mobile ?? { metrics: {}, scores: {}, opportunities: [] };
  const d = lh.desktop ?? { metrics: {}, scores: {}, opportunities: [] };
  const mobileSuspect = lh.mobile?.instrumentationSuspect === true;
  const suspectMetrics = new Set(lh.mobile?.suspectMetrics || []);
  const suspectMark = (metric) => suspectMetrics.has(metric) ? ' ⚠️' : '';
  // For suspect metrics, omit the threshold flag — keeping ❌ next to ⚠️
  // reads as "still failing the gate" when in fact we've demoted the metric.
  const mobileFlag = (metric, value, good, bad) =>
    suspectMetrics.has(metric) ? '' : flag(value, good, bad);

  sections.push('## Core Web Vitals\n');
  if (mobileSuspect) {
    sections.push(`> ⚠️ **Mobile metrics flagged instrumentation-suspect** (${escapeMd((lh.mobile.suspectMetrics || []).join(', '))} > 8× desktop). ${escapeMd(lh.mobile.suspectNote || 'Consider re-running with Lighthouse blockedUrlPatterns for known-flaky third-parties before treating mobile as authoritative.')}`);
    sections.push('');
  }
  sections.push('| Metric | Mobile | Desktop |');
  sections.push('|---|---|---|');
  sections.push(`| LCP | ${ms(m.metrics.lcp)}${suspectMark('lcp')} ${mobileFlag('lcp', m.metrics.lcp, 2500, 4000)} | ${ms(d.metrics.lcp)} ${flag(d.metrics.lcp, 2500, 4000)} |`);
  sections.push(`| INP | ${ms(m.metrics.inp)} | ${ms(d.metrics.inp)} |`);
  sections.push(`| CLS | ${num(m.metrics.cls, 3)} ${mobileFlag('cls', m.metrics.cls, 0.1, 0.25)} | ${num(d.metrics.cls, 3)} ${flag(d.metrics.cls, 0.1, 0.25)} |`);
  sections.push(`| TBT | ${ms(m.metrics.tbt)}${suspectMark('tbt')} ${mobileFlag('tbt', m.metrics.tbt, 200, 600)} | ${ms(d.metrics.tbt)} ${flag(d.metrics.tbt, 200, 600)} |`);
  sections.push(`| Perf | ${m.scores.performance ?? '—'} ${m.scores.performance == null || mobileSuspect ? '' : scoreFlag(m.scores.performance)} | ${d.scores.performance ?? '—'} ${d.scores.performance == null ? '' : scoreFlag(d.scores.performance)} |`);
  sections.push(`| A11y | ${m.scores.accessibility ?? '—'} ${m.scores.accessibility == null ? '' : scoreFlag(m.scores.accessibility)} | ${d.scores.accessibility ?? '—'} ${d.scores.accessibility == null ? '' : scoreFlag(d.scores.accessibility)} |`);
  sections.push(`| BP | ${m.scores.bestPractices ?? '—'} | ${d.scores.bestPractices ?? '—'} |`);
  sections.push(`| SEO | ${m.scores.seo ?? '—'} | ${d.scores.seo ?? '—'} |`);

  if (m.opportunities?.length > 0) {
    sections.push('\n### Top mobile opportunities');
    m.opportunities.slice(0, 5).forEach(o => {
      sections.push(`- **${escapeMd(o.title)}** — ${ms(o.savingsMs)} savings${o.savingsBytes ? ` (${kb(o.savingsBytes)})` : ''}`);
    });
  }
}

// Responsive sweep
const sweep = tryRead(join(REPORT_DIR, 'manifest.json'));
if (sweep) {
  const overflows = sweep.entries.filter(e => e.horizontalOverflow);
  const errors = sweep.entries.filter(e => e.error);
  const perBreakpointAnomalies = sweep.entries.flatMap(e =>
    (e.sectionAnomalies || []).map(a => ({ ...a, width: e.width, theme: e.theme }))
  );
  const deltaAnomalies = sweep.sectionAnomalyDeltas || [];

  sections.push('\n## Responsive sweep\n');
  sections.push(`- Screenshots captured: ${sweep.entries.length}`);
  sections.push(`- Widths with horizontal overflow: ${overflows.length}`);
  sections.push(`- Capture errors: ${errors.length}`);
  if (overflows.length > 0) {
    const widths = [...new Set(overflows.map(o => `${o.width}px`))].join(', ');
    sections.push(`- Affected widths: ${widths}`);
  }
  sections.push(`- Section anomalies: ${perBreakpointAnomalies.length} per-breakpoint, ${deltaAnomalies.length} cross-breakpoint deltas`);

  if (perBreakpointAnomalies.length > 0 || deltaAnomalies.length > 0) {
    sections.push('\n### Section anomalies\n');
    sections.push('Heuristics: empty bands, collapsed islands, near-overlapping interactives, dramatic breakpoint deltas. Treat as advisory — surface, don\'t gate.\n');

    // Group per-breakpoint by anomaly type for scanability
    const byType = {};
    for (const a of perBreakpointAnomalies) {
      if (!byType[a.type]) byType[a.type] = [];
      byType[a.type].push(a);
    }
    for (const [type, items] of Object.entries(byType)) {
      sections.push(`**${escapeMd(type)}** (${items.length})`);
      for (const a of items.slice(0, 5)) {
        sections.push(`- [${escapeMd(a.severity)}] ${a.width}px/${escapeMd(a.theme)}: ${escapeMd(a.message)}`);
      }
      if (items.length > 5) sections.push(`- … and ${items.length - 5} more`);
    }
    if (deltaAnomalies.length > 0) {
      sections.push('**breakpoint-delta** (cross-breakpoint)');
      for (const d of deltaAnomalies.slice(0, 5)) {
        sections.push(`- [${escapeMd(d.severity)}] ${escapeMd(d.message)}`);
      }
      if (deltaAnomalies.length > 5) sections.push(`- … and ${deltaAnomalies.length - 5} more`);
    }
  }
}

// axe
const axeSummary = tryRead(join(REPORT_DIR, 'axe', 'summary.json'));
if (axeSummary) {
  sections.push('\n## Accessibility (axe-core)\n');
  sections.push(`- Total findings: ${axeSummary.totalFindings}`);
  sections.push(`- Critical: ${axeSummary.byImpact.critical}`);
  sections.push(`- Serious: ${axeSummary.byImpact.serious}`);
  sections.push(`- Moderate: ${axeSummary.byImpact.moderate}`);
  sections.push(`- Minor: ${axeSummary.byImpact.minor}`);
  sections.push(`- Hover-state-only findings: ${axeSummary.byState.hover}`);
  sections.push(`- Focus-state-only findings: ${axeSummary.byState.focus}`);

  const top = axeSummary.findings.filter(f => f.impact === 'critical' || f.impact === 'serious').slice(0, 5);
  if (top.length > 0) {
    sections.push('\n### Top a11y issues');
    top.forEach(f => {
      const target = f.nodes?.[0]?.target?.[0] ?? '?';
      sections.push(`- **[${f.impact}] ${f.id}** at ${f.viewport}/${f.theme}/${f.state} — \`${target}\``);
    });
  }
}

// SEO
const seo = tryRead(join(REPORT_DIR, 'seo', 'report.json'));
if (seo) {
  sections.push('\n## SEO & Meta\n');
  const blockers = seo.findings.filter(f => f.severity === 'blocker');
  const high = seo.findings.filter(f => f.severity === 'high');
  sections.push(`- Blockers: ${blockers.length}`);
  sections.push(`- High: ${high.length}`);
  sections.push(`- Total findings: ${seo.findings.length}`);

  if (blockers.length > 0) {
    sections.push('\n### Blockers');
    blockers.forEach(f => sections.push(`- **${f.message}**${f.detail ? ` — \`${truncate(f.detail)}\`` : ''}`));
  }
}

// Argos build
const argosUrl = tryReadText(join(REPORT_DIR, 'argos-build-url.txt'));
if (argosUrl) {
  sections.push(`\n## Visual regression\n\nArgos build: ${argosUrl.trim()}`);
}

writeFileSync(join(REPORT_DIR, 'summary.md'), sections.join('\n'));
console.log(`[markdown] wrote ${join(REPORT_DIR, 'summary.md')}`);

// helpers
function tryRead(p) {
  if (!existsSync(p)) return null;
  try { return JSON.parse(readFileSync(p, 'utf8')); } catch { return null; }
}
function tryReadText(p) {
  if (!existsSync(p)) return null;
  try { return readFileSync(p, 'utf8'); } catch { return null; }
}
function ms(v) { return v == null ? '—' : `${Math.round(v)}ms`; }
function num(v, d = 2) { return v == null ? '—' : v.toFixed(d); }
function kb(b) { return b == null ? '—' : `${Math.round(b / 1024)}KB`; }
function flag(v, good, bad) { if (v == null) return ''; if (v <= good) return '✅'; if (v <= bad) return '⚠️'; return '❌'; }
function scoreFlag(s) { if (s >= 90) return '✅'; if (s >= 50) return '⚠️'; return '❌'; }
function truncate(s) { const str = typeof s === 'string' ? s : JSON.stringify(s); return str.length > 80 ? str.slice(0, 77) + '...' : str; }
// Escape Markdown metacharacters in dynamic strings (suspect notes, anomaly
// messages, opportunity titles, etc.) so a class/id that happens to contain
// `*` or `>` doesn't break the surrounding blockquote/list formatting.
function escapeMd(s) {
  return String(s ?? '').replace(/([\\`*_{}\[\]()#+\-!|>])/g, '\\$1');
}
