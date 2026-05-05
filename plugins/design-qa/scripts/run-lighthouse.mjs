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
import { join, resolve, relative, isAbsolute } from 'node:path';

const REPORT_DIR = process.env.DESIGN_QA_REPORT_DIR;
if (!REPORT_DIR) {
  console.error('DESIGN_QA_REPORT_DIR is required');
  process.exit(1);
}

const cwd = process.cwd();
const resolvedReportDir = resolve(cwd, REPORT_DIR);
// Use path.relative so the containment check is platform-agnostic — a literal
// `/` separator breaks on Windows where path.resolve emits backslashes.
const rel = relative(cwd, resolvedReportDir);
if (rel.startsWith('..') || isAbsolute(rel)) {
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

  // Lazy-import here so --merge mode doesn't load chrome-launcher unnecessarily.
  const lighthouse = (await import('lighthouse')).default;
  const chromeLauncher = await import('chrome-launcher');

  // --no-sandbox is required when Chromium runs as root (CI containers,
  // Docker), but it's a real foot-gun on a dev machine auditing arbitrary URLs
  // because it removes the Linux sandbox layer. Default to sandboxed; opt in
  // via env or auto-detect when we know we have to (CI / running as root).
  const isRoot = typeof process.getuid === 'function' && process.getuid() === 0;
  const noSandbox =
    process.env.DESIGN_QA_CHROME_NO_SANDBOX === '1' ||
    process.env.CI === 'true' ||
    isRoot;
  const chromeFlags = ['--headless=new'];
  if (noSandbox) chromeFlags.push('--no-sandbox');

  // Comma-separated URL substrings (Lighthouse pattern syntax) to block during
  // the audit — the documented escape hatch for instrumentation-suspect runs
  // (a stalled tracker under simulated 4× CPU + Slow 4G inflates mobile metrics).
  const blockedUrlPatterns = (process.env.DESIGN_QA_BLOCKED_URL_PATTERNS || '')
    .split(',')
    .map(s => s.trim())
    .filter(Boolean);

  const chrome = await chromeLauncher.launch({ chromeFlags });
  try {
    // When the target is a protected Vercel preview, we DO NOT pass the bypass
    // secret to Lighthouse via `extraHeaders`. Lighthouse's extraHeaders applies
    // to *every* network request the audit makes — including third-party
    // subresources (analytics, fonts, etc.) — which would leak the secret
    // cross-origin. Instead, bootstrap a Vercel bypass cookie on the same Chrome
    // instance via CDP. The cookie is origin-scoped by Chrome, so third parties
    // don't see it, and Vercel honors the cookie for the whole session.
    if (BYPASS) {
      await bootstrapBypassCookie(chrome.port, parsedUrl, BYPASS);
    }

    const options = {
      logLevel: 'error',
      output: ['html', 'json'],
      onlyCategories: ['performance', 'accessibility', 'best-practices', 'seo'],
      port: chrome.port,
      ...(blockedUrlPatterns.length > 0 ? { blockedUrlPatterns } : {}),
      formFactor: profile,
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
    const result = {
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
  } catch (e) {
    // The shell wrapper iterates `for profile in mobile desktop` and exits on
    // the first non-zero status (set -euo pipefail). If we swallowed this, the
    // missing result.json would silently fall through to the merge step and
    // get treated as "scan ran but produced nothing."
    console.error(`[lighthouse] ${profile} run failed: ${e.message}`);
    process.exitCode = 1;
    throw e;
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

  // Hard fail when both profiles are missing/unparsable. Otherwise the
  // reporters fall through to a green report — gates use optional chaining
  // (lhSource?.metrics?.lcp > 4000) which evaluates to false when lhSource is
  // null, so a fully-broken Lighthouse run would silently mark CI green.
  if (!mobile && !desktop) {
    console.error('[lighthouse] both mobile and desktop results are missing or unparsable — refusing to write a passing summary.');
    process.exit(1);
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

// Bootstrap the Vercel bypass cookie on Chrome via CDP, so the secret never
// reaches third-party origins via Lighthouse's `extraHeaders`. The flow:
//   1. Make a same-origin GET to the target URL with the bypass header — this
//      one request *does* carry the secret, but only to the target origin.
//      Vercel responds with a Set-Cookie that grants bypass for the session.
//   2. Walk every Set-Cookie from that response and inject it into Chrome via
//      `Network.setCookie` against the target hostname. Chrome's origin model
//      then keeps the cookie scoped — third-party subresources won't see it.
//   3. Lighthouse runs with empty extraHeaders. The audit inherits the cookie
//      via Chrome's normal cookie handling.
async function bootstrapBypassCookie(chromePort, parsedUrl, bypass) {
  // Use Node's built-in WebSocket (Node 22+) to talk CDP, avoiding a new dep.
  // Hard fail when WebSocket is missing — falling back to Lighthouse's
  // extraHeaders would leak the bypass secret to every third-party origin
  // (analytics, fonts, CDNs). Worse, an earlier version of this code claimed
  // to "fall back" but actually returned and ran fully unauthenticated against
  // a 401 page, which the merge step then silently marked green.
  if (typeof globalThis.WebSocket !== 'function') {
    console.error('[lighthouse] Node WebSocket is required for the Vercel bypass cookie bootstrap (Node ≥ 22). Upgrade Node, or unset VERCEL_AUTOMATION_BYPASS_SECRET / DESIGN_QA_BYPASS to scan a non-protected URL.');
    process.exit(1);
  }

  // 1. Get a Vercel-issued bypass cookie via a same-origin request.
  let setCookieValues = [];
  try {
    const res = await fetch(parsedUrl.toString(), {
      headers: {
        'x-vercel-protection-bypass': bypass,
        'x-vercel-set-bypass-cookie': 'true'
      },
      redirect: 'manual'
    });
    setCookieValues = typeof res.headers.getSetCookie === 'function'
      ? res.headers.getSetCookie()
      : [];
  } catch (e) {
    console.error(`[lighthouse] bypass bootstrap fetch failed: ${e.message}`);
    process.exit(1);
  }

  if (setCookieValues.length === 0) {
    console.error('[lighthouse] target did not return any Set-Cookie headers — bypass cookie not bootstrapped, refusing to run a guaranteed-401 audit.');
    process.exit(1);
  }

  // 2. Connect to Chrome's first browser target via CDP and inject cookies.
  let pageWsUrl;
  try {
    const targetsRes = await fetch(`http://127.0.0.1:${chromePort}/json`);
    const targets = await targetsRes.json();
    const pageTarget = targets.find(t => t.type === 'page') || targets[0];
    if (!pageTarget) throw new Error('no Chrome targets found');
    pageWsUrl = pageTarget.webSocketDebuggerUrl;
  } catch (e) {
    console.warn(`[lighthouse] could not discover CDP target: ${e.message}`);
    return;
  }

  let injectedCount = 0;
  let injectFailure = null;
  await new Promise((resolve, reject) => {
    const ws = new globalThis.WebSocket(pageWsUrl);
    let id = 0;
    const pending = new Map();
    const send = (method, params = {}) => new Promise((res, rej) => {
      const msgId = ++id;
      pending.set(msgId, { res, rej });
      try {
        ws.send(JSON.stringify({ id: msgId, method, params }));
      } catch (err) {
        // ws.send can throw synchronously (CLOSING/CLOSED state). Without this
        // the outer Promise never settled — the bootstrap call would hang.
        pending.delete(msgId);
        rej(err);
      }
    });

    ws.addEventListener('message', (ev) => {
      try {
        const msg = JSON.parse(ev.data);
        if (msg.id && pending.has(msg.id)) {
          const { res, rej } = pending.get(msg.id);
          pending.delete(msg.id);
          msg.error ? rej(new Error(msg.error.message)) : res(msg.result);
        }
      } catch { /* ignore non-JSON frames */ }
    });

    ws.addEventListener('open', async () => {
      try {
        await send('Network.enable');
        for (const setCookieStr of setCookieValues) {
          const firstPart = setCookieStr.split(';')[0] || '';
          // Split on the FIRST `=` only — encoded session cookies (base64 with
          // `==` padding, JWTs, or anything URL-encoded) routinely include `=`
          // inside the value. A naive split('=') would truncate the value and
          // produce a corrupted bypass cookie.
          const eqIdx = firstPart.indexOf('=');
          if (eqIdx <= 0) continue;
          const name = firstPart.slice(0, eqIdx).trim();
          const value = firstPart.slice(eqIdx + 1).trim();
          if (!name) continue;
          // Pass `url` so Chrome derives domain/path/secure from the origin —
          // forcing domain/sameSite/path breaks `__Host-` prefixed cookies and
          // overrides any path-scoping Vercel applied. CDP reports back
          // `success: false` when a cookie is rejected; surface that instead
          // of declaring success regardless.
          const result = await send('Network.setCookie', {
            url: parsedUrl.origin,
            name,
            value
          });
          if (result?.success === false) {
            throw new Error(`Chrome rejected cookie "${name}" via Network.setCookie`);
          }
          injectedCount++;
        }
      } catch (e) {
        injectFailure = e;
      } finally {
        ws.close();
      }
    });

    ws.addEventListener('close', resolve);
    ws.addEventListener('error', (ev) => {
      reject(new Error(`CDP WebSocket error: ${ev?.message || 'unknown'}`));
    });
  });

  if (injectFailure) {
    console.error(`[lighthouse] cookie inject failed: ${injectFailure.message}`);
    process.exit(1);
  }
  console.log(`[lighthouse] injected ${injectedCount} bypass cookie(s) for ${parsedUrl.hostname} via CDP`);
}
