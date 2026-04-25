#!/usr/bin/env node
// run-lighthouse.mjs — runs ONE Lighthouse profile per invocation.
//
// Why subprocess-per-profile: real-world testing showed the second sequential
// chrome-launcher boot in the same Node process can return null categories on
// the first profile (state leak between launches). Running each profile in a
// fresh Node process eliminates the leak.
//
// Modes:
//   --profile mobile|desktop   Run a single Lighthouse profile.
//   --merge                    Combine the two profile result.json files into
//                              lighthouse/summary.json with an outlier guard.

import { writeFileSync, readFileSync, existsSync, mkdirSync } from 'node:fs';
import { join, resolve } from 'node:path';

const REPORT_DIR = process.env.DESIGN_QA_REPORT_DIR;
if (!REPORT_DIR) {
  console.error('DESIGN_QA_REPORT_DIR is required');
  process.exit(1);
}

const cwd = process.cwd();
const resolvedReportDir = resolve(cwd, REPORT_DIR);
if (!resolvedReportDir.startsWith(cwd + '/') && resolvedReportDir !== cwd) {
  console.error(`DESIGN_QA_REPORT_DIR must stay inside the workspace; got ${resolvedReportDir}`);
  process.exit(1);
}

const args = process.argv.slice(2);
const flagIndex = (name) => args.indexOf(name);
const flagValue = (name) => {
  const i = flagIndex(name);
  return i >= 0 && args[i + 1] ? args[i + 1] : null;
};

const profileArg = flagValue('--profile');
const mergeMode = args.includes('--merge');

if (mergeMode) {
  await runMerge();
} else if (profileArg) {
  if (profileArg !== 'mobile' && profileArg !== 'desktop') {
    console.error(`--profile must be "mobile" or "desktop"; got "${profileArg}"`);
    process.exit(1);
  }
  await runProfileMode(profileArg);
} else {
  console.error('usage: run-lighthouse.mjs --profile <mobile|desktop> | --merge');
  process.exit(1);
}

async function runProfileMode(profile) {
  const URL_ENV = process.env.DESIGN_QA_URL;
  const BYPASS = process.env.DESIGN_QA_BYPASS || '';

  if (!URL_ENV) {
    console.error('DESIGN_QA_URL is required for --profile mode');
    process.exit(1);
  }

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

  // Lazy-import here so --merge mode doesn't load chrome-launcher unnecessarily.
  const lighthouse = (await import('lighthouse')).default;
  const chromeLauncher = await import('chrome-launcher');

  const chrome = await chromeLauncher.launch({ chromeFlags: ['--headless=new', '--no-sandbox'] });
  let result;
  try {
    const options = {
      logLevel: 'error',
      output: ['html', 'json'],
      onlyCategories: ['performance', 'accessibility', 'best-practices', 'seo'],
      port: chrome.port,
      formFactor: profile,
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

    const dir = join(resolvedReportDir, 'lighthouse', profile);
    mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, 'report.html'), runnerResult.report[0]);
    writeFileSync(join(dir, 'report.json'), runnerResult.report[1]);

    const lhr = runnerResult.lhr;
    result = {
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

    writeFileSync(join(dir, 'result.json'), JSON.stringify(result, null, 2));

    const lcp = result.metrics.lcp != null ? `${Math.round(result.metrics.lcp)}ms` : '—';
    const cls = result.metrics.cls != null ? result.metrics.cls.toFixed(3) : '—';
    const tbt = result.metrics.tbt != null ? `${Math.round(result.metrics.tbt)}ms` : '—';
    console.log(`[lighthouse] ${profile}: perf=${result.scores.performance} a11y=${result.scores.accessibility} bp=${result.scores.bestPractices} seo=${result.scores.seo}`);
    console.log(`[lighthouse]   LCP=${lcp} CLS=${cls} TBT=${tbt}`);
  } finally {
    try { await chrome.kill(); } catch { /* already exited */ }
  }
}

async function runMerge() {
  const dir = join(resolvedReportDir, 'lighthouse');
  const mobile = readResult(join(dir, 'mobile', 'result.json'));
  const desktop = readResult(join(dir, 'desktop', 'result.json'));

  const summary = {
    mobile,
    desktop
  };

  // Outlier / instrumentation-suspect filter. When a single third-party stalls
  // the mobile run under simulated 4× CPU + Slow 4G, mobile metrics can come
  // back wildly inflated relative to desktop (Kyle observed mobile LCP 48s vs
  // desktop 1.4s on a fast static page). Flag the metric so reporters can
  // demote it from "blocker" to "advisory" rather than misleading the reader.
  const SUSPECT_RATIO = 8;
  const checkSuspect = (metric) => {
    if (mobile && desktop && mobile.metrics?.[metric] != null && desktop.metrics?.[metric] != null) {
      const m = mobile.metrics[metric];
      const d = desktop.metrics[metric];
      if (d > 0 && m / d > SUSPECT_RATIO) return true;
    }
    return false;
  };

  if (mobile) {
    const suspectMetrics = ['lcp', 'tbt', 'fcp', 'tti', 'speedIndex'].filter(checkSuspect);
    mobile.instrumentationSuspect = suspectMetrics.length > 0;
    mobile.suspectMetrics = suspectMetrics;
    if (suspectMetrics.length > 0) {
      mobile.suspectNote = `Mobile metric(s) ${suspectMetrics.join(', ')} are >${SUSPECT_RATIO}× the desktop value, which usually means a third-party tracker stalled under throttling. Consider re-running with Lighthouse blockedUrlPatterns for known-flaky trackers (Termly, PostHog, Segment, Hotjar) before treating mobile as authoritative.`;
    }
  }

  writeFileSync(join(dir, 'summary.json'), JSON.stringify(summary, null, 2));
  console.log(`[lighthouse] merged summary written to ${join(dir, 'summary.json')}`);
  if (mobile?.instrumentationSuspect) {
    console.warn(`[lighthouse] ⚠️  mobile metrics flagged instrumentation-suspect: ${mobile.suspectMetrics.join(', ')}`);
  }
}

function readResult(p) {
  if (!existsSync(p)) {
    console.warn(`[lighthouse] missing result file: ${p}`);
    return null;
  }
  try {
    return JSON.parse(readFileSync(p, 'utf8'));
  } catch (e) {
    console.warn(`[lighthouse] could not parse ${p}: ${e.message}`);
    return null;
  }
}
