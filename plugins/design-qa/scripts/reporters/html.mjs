#!/usr/bin/env node
// reporters/html.mjs — generate a clickable HTML report with embedded screenshots.

import { readFileSync, writeFileSync, existsSync, readdirSync } from 'node:fs';
import { join, basename } from 'node:path';

const REPORT_DIR = process.argv[2];
if (!REPORT_DIR) { console.error('usage: html.mjs <reportDir>'); process.exit(1); }

function tryRead(p) {
  if (!existsSync(p)) return null;
  try { return JSON.parse(readFileSync(p, 'utf8')); } catch { return null; }
}

const sweep = tryRead(join(REPORT_DIR, 'manifest.json'));
const lh = tryRead(join(REPORT_DIR, 'lighthouse', 'summary.json'));
const axe = tryRead(join(REPORT_DIR, 'axe', 'summary.json'));
const seo = tryRead(join(REPORT_DIR, 'seo', 'report.json'));

const screenshots = existsSync(join(REPORT_DIR, 'screenshots'))
  ? readdirSync(join(REPORT_DIR, 'screenshots')).filter(f => f.endsWith('.png'))
  : [];

const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Design QA: ${escape(sweep?.url ?? 'Report')}</title>
<style>
  * { box-sizing: border-box; }
  body { font: 14px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif; color: #111; background: #fafafa; margin: 0; padding: 0; }
  header { background: #111; color: #fff; padding: 24px 32px; }
  header h1 { margin: 0 0 4px; font-size: 20px; }
  header .url { font-family: ui-monospace, "SF Mono", Menlo, monospace; opacity: 0.8; font-size: 13px; }
  main { max-width: 1400px; margin: 0 auto; padding: 24px 32px; }
  section { background: #fff; border: 1px solid #e5e5e5; border-radius: 8px; padding: 20px; margin-bottom: 16px; }
  h2 { margin: 0 0 16px; font-size: 16px; }
  table { width: 100%; border-collapse: collapse; }
  th, td { text-align: left; padding: 8px 12px; border-bottom: 1px solid #f0f0f0; font-size: 13px; }
  th { background: #f9f9f9; font-weight: 600; }
  .ok { color: #16a34a; }
  .warn { color: #ca8a04; }
  .bad { color: #dc2626; }
  .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: 12px; }
  .shot { background: #fff; border: 1px solid #e5e5e5; border-radius: 6px; overflow: hidden; }
  .shot img { width: 100%; height: auto; display: block; }
  .shot .label { padding: 8px 12px; font-size: 12px; font-family: ui-monospace, monospace; background: #f9f9f9; border-top: 1px solid #e5e5e5; display: flex; justify-content: space-between; }
  .shot.overflow { border-color: #dc2626; }
  .shot.overflow .label { background: #fee2e2; }
  .badge { display: inline-block; padding: 2px 6px; border-radius: 4px; font-size: 11px; font-weight: 600; }
  .badge.crit { background: #dc2626; color: #fff; }
  .badge.serious { background: #ea580c; color: #fff; }
  .badge.moderate { background: #ca8a04; color: #fff; }
  .badge.minor { background: #6b7280; color: #fff; }
</style>
</head>
<body>
<header>
  <h1>Design QA Report</h1>
  <div class="url">${escape(sweep?.url ?? 'no url captured')}</div>
  <div class="url" style="margin-top: 8px; font-size: 11px;">Generated ${new Date().toISOString()}</div>
</header>

<main>

${lh ? `
<section>
  <h2>Core Web Vitals</h2>
  <table>
    <tr><th>Metric</th><th>Mobile</th><th>Desktop</th></tr>
    <tr><td>LCP</td><td class="${lhCls(lh.mobile.metrics.lcp, 2500, 4000)}">${ms(lh.mobile.metrics.lcp)}</td><td class="${lhCls(lh.desktop.metrics.lcp, 2500, 4000)}">${ms(lh.desktop.metrics.lcp)}</td></tr>
    <tr><td>INP</td><td>${ms(lh.mobile.metrics.inp)}</td><td>${ms(lh.desktop.metrics.inp)}</td></tr>
    <tr><td>CLS</td><td class="${lhCls(lh.mobile.metrics.cls, 0.1, 0.25)}">${num(lh.mobile.metrics.cls, 3)}</td><td class="${lhCls(lh.desktop.metrics.cls, 0.1, 0.25)}">${num(lh.desktop.metrics.cls, 3)}</td></tr>
    <tr><td>TBT</td><td>${ms(lh.mobile.metrics.tbt)}</td><td>${ms(lh.desktop.metrics.tbt)}</td></tr>
    <tr><td>Performance</td><td class="${scoreCls(lh.mobile.scores.performance)}">${lh.mobile.scores.performance}</td><td class="${scoreCls(lh.desktop.scores.performance)}">${lh.desktop.scores.performance}</td></tr>
    <tr><td>Accessibility</td><td>${lh.mobile.scores.accessibility}</td><td>${lh.desktop.scores.accessibility}</td></tr>
    <tr><td>Best Practices</td><td>${lh.mobile.scores.bestPractices}</td><td>${lh.desktop.scores.bestPractices}</td></tr>
    <tr><td>SEO</td><td>${lh.mobile.scores.seo}</td><td>${lh.desktop.scores.seo}</td></tr>
  </table>
  <p style="margin-top: 12px;"><a href="lighthouse/mobile/report.html">Mobile Lighthouse →</a> &nbsp; <a href="lighthouse/desktop/report.html">Desktop Lighthouse →</a></p>
</section>
` : ''}

${axe ? `
<section>
  <h2>Accessibility (axe-core)</h2>
  <p>
    <span class="badge crit">${axe.byImpact.critical} critical</span>
    <span class="badge serious">${axe.byImpact.serious} serious</span>
    <span class="badge moderate">${axe.byImpact.moderate} moderate</span>
    <span class="badge minor">${axe.byImpact.minor} minor</span>
  </p>
  <p>Hover-state-only: ${axe.byState.hover} · Focus-state-only: ${axe.byState.focus}</p>
  ${axe.findings.slice(0, 10).map(f => `
    <div style="border-top: 1px solid #f0f0f0; padding: 8px 0; font-size: 13px;">
      <span class="badge ${impactClass(f.impact)}">${escape(f.impact)}</span>
      <strong>${escape(f.id)}</strong> — ${escape(f.viewport)}/${escape(f.theme)}/${escape(f.state)}
      <div style="font-family: ui-monospace, monospace; color: #666; margin-top: 4px;">${escape(f.nodes?.[0]?.target?.[0] ?? '?')}</div>
    </div>
  `).join('')}
</section>
` : ''}

${seo ? `
<section>
  <h2>SEO &amp; Meta</h2>
  ${seo.findings.length === 0 ? '<p>✅ No findings.</p>' : `
    <table>
      <tr><th>Severity</th><th>Category</th><th>Message</th></tr>
      ${seo.findings.map(f => `<tr><td>${escape(f.severity)}</td><td>${escape(f.category)}</td><td>${escape(f.message)}</td></tr>`).join('')}
    </table>
  `}
</section>
` : ''}

${sweep ? `
<section>
  <h2>Responsive sweep · ${sweep.entries.length} screenshots</h2>
  <p>Overflow widths: ${[...new Set(sweep.entries.filter(e => e.horizontalOverflow).map(e => e.width))].join(', ') || 'none ✅'}</p>
  <div class="grid">
    ${sweep.entries.filter(e => !e.error).map(e => `
      <div class="shot ${e.horizontalOverflow ? 'overflow' : ''}">
        <img src="screenshots/${escape(e.file)}" alt="${escape(e.deviceLabel)} ${escape(e.theme)}" loading="lazy">
        <div class="label">
          <span>${e.width}px · ${escape(e.theme)}</span>
          <span>${e.horizontalOverflow ? '❌ overflow' : '✅'}</span>
        </div>
      </div>
    `).join('')}
  </div>
</section>
` : ''}

</main>
</body>
</html>`;

writeFileSync(join(REPORT_DIR, 'report.html'), html);
console.log(`[html] wrote ${join(REPORT_DIR, 'report.html')}`);

function ms(v) { return v == null ? '—' : `${Math.round(v)}ms`; }
function num(v, d = 2) { return v == null ? '—' : v.toFixed(d); }
function lhCls(v, good, bad) { if (v == null) return ''; if (v <= good) return 'ok'; if (v <= bad) return 'warn'; return 'bad'; }
function scoreCls(s) { if (s >= 90) return 'ok'; if (s >= 50) return 'warn'; return 'bad'; }
function escape(s) { return String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])); }
// Whitelist axe impact values before interpolating into a class attribute,
// otherwise an attacker-controlled report could close the attribute and inject markup.
function impactClass(impact) {
  return ({ critical: 'crit', serious: 'serious', moderate: 'moderate', minor: 'minor' }[impact]) || 'minor';
}
