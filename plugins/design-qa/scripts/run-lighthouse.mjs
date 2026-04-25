#!/usr/bin/env node
// run-lighthouse.mjs — Lighthouse runs for mobile and desktop profiles.

import { writeFileSync, mkdirSync } from 'node:fs';
import { join, resolve } from 'node:path';
import lighthouse from 'lighthouse';
import * as chromeLauncher from 'chrome-launcher';

const URL_ENV = process.env.DESIGN_QA_URL;
const REPORT_DIR = process.env.DESIGN_QA_REPORT_DIR;
const BYPASS = process.env.DESIGN_QA_BYPASS || '';

if (!URL_ENV || !REPORT_DIR) {
  console.error('DESIGN_QA_URL and DESIGN_QA_REPORT_DIR are required');
  process.exit(1);
}

const cwd = process.cwd();
const resolvedReportDir = resolve(cwd, REPORT_DIR);
if (!resolvedReportDir.startsWith(cwd + '/') && resolvedReportDir !== cwd) {
  console.error(`DESIGN_QA_REPORT_DIR must stay inside the workspace; got ${resolvedReportDir}`);
  process.exit(1);
}

// Ensure the URL parses; reject unsupported schemes.
let parsedUrl;
try {
  parsedUrl = new globalThis.URL(URL_ENV);
} catch {
  console.error(`DESIGN_QA_URL is not a valid URL: ${URL_ENV}`);
  process.exit(1);
}
if (parsedUrl.protocol !== 'http:' && parsedUrl.protocol !== 'https:') {
  console.error(`DESIGN_QA_URL must be http(s); got ${parsedUrl.protocol}`);
  process.exit(1);
}

const extraHeaders = BYPASS
  ? {
      'x-vercel-protection-bypass': BYPASS,
      'x-vercel-set-bypass-cookie': 'true'
    }
  : {};

async function runProfile(profile) {
  const chrome = await chromeLauncher.launch({ chromeFlags: ['--headless=new', '--no-sandbox'] });
  try {
    const options = {
      logLevel: 'error',
      output: ['html', 'json'],
      onlyCategories: ['performance', 'accessibility', 'best-practices', 'seo'],
      port: chrome.port,
      formFactor: profile,
      // Pass bypass via headers, not query string — keeps the secret out of
      // report.html, report.json, target server logs, and the Chrome process list.
      extraHeaders,
      screenEmulation: profile === 'mobile'
        ? { mobile: true, width: 412, height: 823, deviceScaleFactor: 1.75, disabled: false }
        : { mobile: false, width: 1350, height: 940, deviceScaleFactor: 1, disabled: false },
      throttling: profile === 'mobile'
        ? { rttMs: 150, throughputKbps: 1638.4, cpuSlowdownMultiplier: 4, requestLatencyMs: 562.5, downloadThroughputKbps: 1474.56, uploadThroughputKbps: 675 }
        : { rttMs: 40, throughputKbps: 10240, cpuSlowdownMultiplier: 1, requestLatencyMs: 0, downloadThroughputKbps: 0, uploadThroughputKbps: 0 }
    };

    console.log(`[lighthouse] running ${profile}...`);
    const runnerResult = await lighthouse(parsedUrl.toString(), options);
    if (!runnerResult || !runnerResult.lhr || !Array.isArray(runnerResult.report)) {
      throw new Error(`Lighthouse returned no result for ${profile}`);
    }

    const dir = join(REPORT_DIR, 'lighthouse', profile);
    mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, 'report.html'), runnerResult.report[0]);
    writeFileSync(join(dir, 'report.json'), runnerResult.report[1]);

    const lhr = runnerResult.lhr;
    return {
      profile,
      scores: {
        performance: Math.round((lhr.categories.performance?.score ?? 0) * 100),
        accessibility: Math.round((lhr.categories.accessibility?.score ?? 0) * 100),
        bestPractices: Math.round((lhr.categories['best-practices']?.score ?? 0) * 100),
        seo: Math.round((lhr.categories.seo?.score ?? 0) * 100)
      },
      metrics: {
        lcp: lhr.audits['largest-contentful-paint']?.numericValue,
        inp: lhr.audits['interaction-to-next-paint']?.numericValue ?? null,
        cls: lhr.audits['cumulative-layout-shift']?.numericValue,
        tbt: lhr.audits['total-blocking-time']?.numericValue,
        fcp: lhr.audits['first-contentful-paint']?.numericValue,
        tti: lhr.audits['interactive']?.numericValue,
        speedIndex: lhr.audits['speed-index']?.numericValue
      },
      opportunities: Object.values(lhr.audits)
        .filter(a => a.details?.type === 'opportunity' && a.numericValue > 0)
        .sort((a, b) => b.numericValue - a.numericValue)
        .slice(0, 5)
        .map(a => ({ id: a.id, title: a.title, savingsMs: a.numericValue, savingsBytes: a.details?.overallSavingsBytes }))
    };
  } finally {
    // Always reap Chrome, even if Lighthouse threw.
    try { await chrome.kill(); } catch { /* already exited */ }
  }
}

mkdirSync(join(REPORT_DIR, 'lighthouse'), { recursive: true });
const results = {};
results.mobile = await runProfile('mobile');
results.desktop = await runProfile('desktop');

writeFileSync(join(REPORT_DIR, 'lighthouse', 'summary.json'), JSON.stringify(results, null, 2));

console.log('\n[lighthouse] summary:');
for (const [profile, r] of Object.entries(results)) {
  console.log(`  ${profile}: perf=${r.scores.performance} a11y=${r.scores.accessibility} bp=${r.scores.bestPractices} seo=${r.scores.seo}`);
  console.log(`    LCP=${Math.round(r.metrics.lcp)}ms CLS=${r.metrics.cls?.toFixed(3)} TBT=${Math.round(r.metrics.tbt)}ms`);
}
