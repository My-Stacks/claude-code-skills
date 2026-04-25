#!/usr/bin/env node
// run-lighthouse.mjs — Lighthouse runs for mobile and desktop profiles.

import { writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import lighthouse from 'lighthouse';
import * as chromeLauncher from 'chrome-launcher';

const URL = process.env.DESIGN_QA_URL;
const REPORT_DIR = process.env.DESIGN_QA_REPORT_DIR;
const BYPASS = process.env.DESIGN_QA_BYPASS || '';

if (!URL || !REPORT_DIR) {
  console.error('DESIGN_QA_URL and DESIGN_QA_REPORT_DIR are required');
  process.exit(1);
}

const targetUrl = BYPASS
  ? `${URL}${URL.includes('?') ? '&' : '?'}x-vercel-protection-bypass=${BYPASS}&x-vercel-set-bypass-cookie=true`
  : URL;

async function runProfile(profile) {
  const chrome = await chromeLauncher.launch({ chromeFlags: ['--headless=new', '--no-sandbox'] });

  const options = {
    logLevel: 'error',
    output: ['html', 'json'],
    onlyCategories: ['performance', 'accessibility', 'best-practices', 'seo'],
    port: chrome.port,
    formFactor: profile,
    screenEmulation: profile === 'mobile'
      ? { mobile: true, width: 412, height: 823, deviceScaleFactor: 1.75, disabled: false }
      : { mobile: false, width: 1350, height: 940, deviceScaleFactor: 1, disabled: false },
    throttling: profile === 'mobile'
      ? { rttMs: 150, throughputKbps: 1638.4, cpuSlowdownMultiplier: 4, requestLatencyMs: 562.5, downloadThroughputKbps: 1474.56, uploadThroughputKbps: 675 }
      : { rttMs: 40, throughputKbps: 10240, cpuSlowdownMultiplier: 1, requestLatencyMs: 0, downloadThroughputKbps: 0, uploadThroughputKbps: 0 }
  };

  console.log(`[lighthouse] running ${profile}...`);
  const runnerResult = await lighthouse(targetUrl, options);
  await chrome.kill();

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
}

const results = {};
results.mobile = await runProfile('mobile');
results.desktop = await runProfile('desktop');

writeFileSync(join(REPORT_DIR, 'lighthouse', 'summary.json'), JSON.stringify(results, null, 2));

console.log('\n[lighthouse] summary:');
for (const [profile, r] of Object.entries(results)) {
  console.log(`  ${profile}: perf=${r.scores.performance} a11y=${r.scores.accessibility} bp=${r.scores.bestPractices} seo=${r.scores.seo}`);
  console.log(`    LCP=${Math.round(r.metrics.lcp)}ms CLS=${r.metrics.cls?.toFixed(3)} TBT=${Math.round(r.metrics.tbt)}ms`);
}
