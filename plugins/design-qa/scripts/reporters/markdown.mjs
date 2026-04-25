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
  sections.push('## Core Web Vitals\n');
  sections.push('| Metric | Mobile | Desktop |');
  sections.push('|---|---|---|');
  sections.push(`| LCP | ${ms(m.metrics.lcp)} ${flag(m.metrics.lcp, 2500, 4000)} | ${ms(d.metrics.lcp)} ${flag(d.metrics.lcp, 2500, 4000)} |`);
  sections.push(`| INP | ${ms(m.metrics.inp)} | ${ms(d.metrics.inp)} |`);
  sections.push(`| CLS | ${num(m.metrics.cls, 3)} ${flag(m.metrics.cls, 0.1, 0.25)} | ${num(d.metrics.cls, 3)} ${flag(d.metrics.cls, 0.1, 0.25)} |`);
  sections.push(`| TBT | ${ms(m.metrics.tbt)} | ${ms(d.metrics.tbt)} |`);
  sections.push(`| Perf | ${m.scores.performance ?? '—'} ${scoreFlag(m.scores.performance)} | ${d.scores.performance ?? '—'} ${scoreFlag(d.scores.performance)} |`);
  sections.push(`| A11y | ${m.scores.accessibility ?? '—'} ${scoreFlag(m.scores.accessibility)} | ${d.scores.accessibility ?? '—'} ${scoreFlag(d.scores.accessibility)} |`);
  sections.push(`| BP | ${m.scores.bestPractices ?? '—'} | ${d.scores.bestPractices ?? '—'} |`);
  sections.push(`| SEO | ${m.scores.seo ?? '—'} | ${d.scores.seo ?? '—'} |`);

  if (m.opportunities?.length > 0) {
    sections.push('\n### Top mobile opportunities');
    m.opportunities.slice(0, 5).forEach(o => {
      sections.push(`- **${o.title}** — ${ms(o.savingsMs)} savings${o.savingsBytes ? ` (${kb(o.savingsBytes)})` : ''}`);
    });
  }
}

// Responsive sweep
const sweep = tryRead(join(REPORT_DIR, 'manifest.json'));
if (sweep) {
  const overflows = sweep.entries.filter(e => e.horizontalOverflow);
  const errors = sweep.entries.filter(e => e.error);
  sections.push('\n## Responsive sweep\n');
  sections.push(`- Screenshots captured: ${sweep.entries.length}`);
  sections.push(`- Widths with horizontal overflow: ${overflows.length}`);
  sections.push(`- Capture errors: ${errors.length}`);
  if (overflows.length > 0) {
    const widths = [...new Set(overflows.map(o => `${o.width}px`))].join(', ');
    sections.push(`- Affected widths: ${widths}`);
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
