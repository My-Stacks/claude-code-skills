#!/usr/bin/env node
// breakpoint-sweep.mjs — the responsive breakpoint sweep.
// Drives Playwright directly (more efficient than calling MCP one width at a time).

import { chromium, devices } from '@playwright/test';
import { mkdirSync, writeFileSync } from 'node:fs';
import { join, resolve, relative, isAbsolute } from 'node:path';

const URL = process.env.DESIGN_QA_URL;
const PRESET = process.env.DESIGN_QA_PRESET || 'agency-default';
const REPORT_DIR = process.env.DESIGN_QA_REPORT_DIR || '.claude/design-qa/reports/latest';
const BYPASS = process.env.DESIGN_QA_BYPASS || '';

if (!URL) {
  console.error('DESIGN_QA_URL is required');
  process.exit(1);
}

const cwd = process.cwd();
const resolvedReportDir = resolve(cwd, REPORT_DIR);
const rel = relative(cwd, resolvedReportDir);
if (rel.startsWith('..') || isAbsolute(rel)) {
  console.error(`DESIGN_QA_REPORT_DIR must stay inside the workspace; got ${resolvedReportDir}`);
  process.exit(1);
}

// When auditing a protected Vercel preview, bootstrap an origin-scoped session
// cookie ONCE up front. Forwarding the bypass secret via `extraHTTPHeaders` on
// every Playwright context would attach it to every request the page makes —
// fonts, analytics, trackers, CDNs — leaking the secret cross-origin. The
// cookie pattern stays scoped to the target hostname.
let bypassCookies = [];
if (BYPASS) {
  let parsedUrl;
  try { parsedUrl = new globalThis.URL(URL); } catch {
    console.error(`DESIGN_QA_URL is not a valid URL: ${URL}`); process.exit(1);
  }
  try {
    const res = await fetch(parsedUrl.toString(), {
      headers: {
        'x-vercel-protection-bypass': BYPASS,
        'x-vercel-set-bypass-cookie': 'true'
      },
      redirect: 'manual'
    });
    const setCookies = typeof res.headers.getSetCookie === 'function'
      ? res.headers.getSetCookie() : [];
    for (const setCookieStr of setCookies) {
      const firstPart = setCookieStr.split(';')[0] || '';
      // Split on the FIRST `=` only — base64-padded / JWT cookie values include `=`.
      const eqIdx = firstPart.indexOf('=');
      if (eqIdx <= 0) continue;
      const name = firstPart.slice(0, eqIdx).trim();
      const value = firstPart.slice(eqIdx + 1).trim();
      if (!name) continue;
      bypassCookies.push({ name, value, domain: parsedUrl.hostname, path: '/' });
    }
    if (bypassCookies.length === 0) {
      console.error('[sweep] target did not return any Set-Cookie headers — refusing to run a guaranteed-401 sweep against a protected preview.');
      process.exit(1);
    }
    console.log(`[sweep] bootstrapped ${bypassCookies.length} bypass cookie(s) for ${parsedUrl.hostname}`);
  } catch (e) {
    console.error(`[sweep] bypass cookie bootstrap failed: ${e.message}`);
    process.exit(1);
  }
}

const PRESETS = {
  fast: [375, 768, 1024, 1440, 1920],
  'agency-default': [
    280, 320, 360, 375, 390, 414, 480, 600, 700, 768,
    834, 900, 1024, 1180, 1280, 1440, 1920, 2560
  ],
  thorough: [
    280, 320, 360, 375, 384, 390, 414, 480, 600, 700, 768,
    834, 900, 1024, 1180, 1280, 1440, 1920, 2560, 3840
  ]
};

// Normalise Playwright device descriptors into the shape the run loop uses
// (`dpr/mobile/touch/userAgent`). Without this, spreading `devices['iPhone SE']`
// would deliver `deviceScaleFactor/isMobile/hasTouch` and the loop would read
// `undefined` instead — silently dropping DPR + touch on those widths.
const fromDevice = (d) => ({
  viewport: d.viewport,
  dpr: d.deviceScaleFactor,
  mobile: d.isMobile,
  touch: d.hasTouch,
  userAgent: d.userAgent
});

const DEVICE_HINTS = {
  280: { name: 'Galaxy Fold (folded)', viewport: { width: 280, height: 653 }, dpr: 3, mobile: true, touch: true, userAgent: devices['Galaxy Note 3']?.userAgent },
  320: { name: 'iPhone SE 1st gen', viewport: { width: 320, height: 568 }, dpr: 2, mobile: true, touch: true },
  360: { name: 'Android baseline', viewport: { width: 360, height: 640 }, dpr: 3, mobile: true, touch: true },
  375: { name: 'iPhone SE / iPhone 8', ...fromDevice(devices['iPhone SE']) },
  390: { name: 'iPhone 14 Pro', ...fromDevice(devices['iPhone 14 Pro']) },
  414: { name: 'iPhone 11 Pro Max', ...fromDevice(devices['iPhone 11 Pro Max']) },
  768: { name: 'iPad portrait', ...fromDevice(devices['iPad (gen 7)']) },
  834: { name: 'iPad Pro 11" portrait', ...fromDevice(devices['iPad Pro 11']) },
  1024: { name: 'iPad landscape / small laptop', viewport: { width: 1024, height: 768 }, dpr: 2, mobile: false, touch: false },
  1280: { name: 'Laptop', viewport: { width: 1280, height: 800 }, dpr: 2, mobile: false, touch: false },
  1440: { name: 'Desktop', viewport: { width: 1440, height: 900 }, dpr: 2, mobile: false, touch: false },
  1920: { name: '1080p desktop', viewport: { width: 1920, height: 1080 }, dpr: 1, mobile: false, touch: false },
  2560: { name: '1440p / 5K-scaled', viewport: { width: 2560, height: 1440 }, dpr: 1, mobile: false, touch: false }
};

const widths = PRESETS[PRESET] || PRESETS['agency-default'];
const themes = PRESET === 'fast'
  ? [{ name: 'light', colorScheme: 'light', reducedMotion: 'no-preference' }]
  : [
      { name: 'light', colorScheme: 'light', reducedMotion: 'no-preference' },
      { name: 'dark', colorScheme: 'dark', reducedMotion: 'no-preference' },
      { name: 'reduced-motion', colorScheme: 'light', reducedMotion: 'reduce' }
    ];

mkdirSync(join(REPORT_DIR, 'screenshots'), { recursive: true });

console.log(`[sweep] ${widths.length} widths × ${themes.length} themes = ${widths.length * themes.length} screenshots`);

const browser = await chromium.launch({ headless: true });
const manifest = { url: URL, preset: PRESET, startedAt: new Date().toISOString(), entries: [] };

let count = 0;
const total = widths.length * themes.length;

for (const w of widths) {
  const hint = DEVICE_HINTS[w] || {
    name: `${w}px`,
    viewport: { width: w, height: Math.round(w * 1.4) },
    dpr: w <= 600 ? 3 : w <= 1024 ? 2 : 1,
    mobile: w <= 600,
    touch: w <= 768
  };

  for (const theme of themes) {
    count++;
    const label = `${w}-${theme.name}`;
    const fileName = `${label}.png`;
    const filePath = join(REPORT_DIR, 'screenshots', fileName);

    process.stdout.write(`[${count}/${total}] ${label}... `);

    const context = await browser.newContext({
      viewport: hint.viewport,
      deviceScaleFactor: hint.dpr,
      isMobile: hint.mobile,
      hasTouch: hint.touch,
      userAgent: hint.userAgent,
      colorScheme: theme.colorScheme,
      reducedMotion: theme.reducedMotion
    });
    if (bypassCookies.length > 0) await context.addCookies(bypassCookies);
    const page = await context.newPage();

    let overflow = null;
    let consoleErrors = [];
    let error = null;
    let manifestEntrySections = [];
    let manifestEntryAnomalies = [];

    page.on('console', msg => {
      if (msg.type() === 'error') consoleErrors.push(msg.text());
    });

    try {
      await page.goto(URL, { waitUntil: 'networkidle', timeout: 30000 });
      await page.evaluate(() => (document.fonts?.ready ?? Promise.resolve()));

      // Disable animations for stability
      await page.addStyleTag({
        content: `*, *::before, *::after {
          animation-duration: 0s !important;
          animation-delay: 0s !important;
          transition-duration: 0s !important;
          transition-delay: 0s !important;
        }`
      });
      await page.waitForTimeout(200);

      // Horizontal overflow + section-anomaly walk in one evaluate.
      // Section anomalies catch the failure modes that "no horizontal scroll"
      // can't see: huge empty bands between sections, hydration-collapsed
      // islands, near-overlapping interactive elements, and dramatic
      // breakpoint deltas (the cross-breakpoint check happens after the loop).
      const pageData = await page.evaluate(() => {
        const overflow = {
          scrollWidth: document.documentElement.scrollWidth,
          clientWidth: document.documentElement.clientWidth,
          overflows: document.documentElement.scrollWidth > document.documentElement.clientWidth
        };

        // Pick top-level "sections": prefer <section> children of <main>, fall
        // back to direct <main> children, fall back to <body> children.
        const sectionRoots = (() => {
          const main = document.querySelector('main') || document.body;
          const sections = main.querySelectorAll(':scope > section');
          if (sections.length > 0) return [...sections];
          // `Element.children` is already an HTMLCollection of element nodes —
          // no nodeType filter needed.
          return [...main.children];
        })();

        const isInteractive = (el) =>
          el.matches('a, button, input, select, textarea, [role=button], [role=link]');

        const sectionInfo = sectionRoots.map((sectionEl, index) => {
          const rect = sectionEl.getBoundingClientRect();
          const sectionArea = Math.max(1, rect.width * rect.height);

          // Sum leaf-element rect areas inside this section. Leaf = no element
          // children. Use a small DOM walk; cap visited count so a giant page
          // can't OOM the eval.
          let leafAreaSum = 0;
          let leafCount = 0;
          let visited = 0;
          const stack = [sectionEl];
          while (stack.length > 0 && visited < 5000) {
            const el = stack.pop();
            visited++;
            if (el.children.length === 0) {
              const r = el.getBoundingClientRect();
              if (r.width > 0 && r.height > 0) {
                leafAreaSum += r.width * r.height;
                leafCount++;
              }
            } else {
              for (const child of el.children) stack.push(child);
            }
          }

          // Cap fillRatio at 1.0. Leaf rects can overlap (a card's title and
          // body both render inside the same container), pushing the sum
          // above the section area. Without the cap reports could read
          // "184% filled" — confusing and undermines the empty-band check.
          const fillRatio = Math.min(1, leafAreaSum / sectionArea);

          // Adjacent-element near-overlap: only compare elements that share
          // the same parent. Walking every interactive descendant in DOM order
          // would falsely pair controls from different containers (e.g. the
          // last button of card A vs the first link of card B). Sort siblings
          // by visual position (top, then left) so flex `order:` / grid
          // placement that scrambles DOM order doesn't produce noise.
          const allInteractives = [...sectionEl.querySelectorAll('a, button, input, select, textarea, [role=button], [role=link]')]
            .filter(el => {
              const r = el.getBoundingClientRect();
              return r.width > 0 && r.height > 0;
            })
            .sort((a, b) => {
              const ar = a.getBoundingClientRect();
              const br = b.getBoundingClientRect();
              return ar.top - br.top || ar.left - br.left;
            });
          const NEAR_OVERLAP_CAP = 50;
          const interactives = allInteractives.slice(0, NEAR_OVERLAP_CAP);
          const nearOverlapTruncated = allInteractives.length > NEAR_OVERLAP_CAP;
          let nearOverlap = 0;
          for (let i = 1; i < interactives.length; i++) {
            const prev = interactives[i - 1];
            const curr = interactives[i];
            if (prev.parentElement !== curr.parentElement) continue;
            const a = prev.getBoundingClientRect();
            const b = curr.getBoundingClientRect();
            // Stacked vertically AND horizontal ranges overlap. Negative gaps
            // mean true visual overlap — flag those, don't filter them out.
            const horizontallyOverlap = a.right > b.left && b.right > a.left;
            const gap = b.top - a.bottom;
            if (horizontallyOverlap && gap < 8) nearOverlap++;
          }

          // Stable identity for cross-breakpoint comparison: section index +
          // tagName + id-or-first-class signature.
          const firstClass = sectionEl.classList[0] || '';
          const identity = `${index}:${sectionEl.tagName.toLowerCase()}:${sectionEl.id || firstClass || 'unknown'}`;

          const anomalies = [];
          if (rect.height > 600 && fillRatio < 0.30) {
            anomalies.push({
              type: 'empty-band',
              severity: 'high',
              message: `Section "${identity}" is ${Math.round(rect.height)}px tall but only ${Math.round(fillRatio * 100)}% is filled with content.`
            });
          }
          if (rect.height > 0 && rect.height < 40) {
            anomalies.push({
              type: 'collapsed-island',
              severity: 'medium',
              message: `Section "${identity}" rendered at ${Math.round(rect.height)}px — likely a hydration failure or empty config.`
            });
          }
          if (nearOverlap > 0) {
            anomalies.push({
              type: 'near-overlap',
              severity: 'medium',
              message: `Section "${identity}" has ${nearOverlap} interactive-element pair(s) with <8px vertical gap.`
            });
          }

          return {
            identity,
            height: Math.round(rect.height),
            fillRatio: Number(fillRatio.toFixed(3)),
            leafCount,
            interactiveCount: allInteractives.length,
            interactiveTruncated: nearOverlapTruncated,
            anomalies
          };
        });

        return { overflow, sections: sectionInfo };
      });

      const truncatedSections = pageData.sections.filter(s => s.interactiveTruncated);
      if (truncatedSections.length > 0) {
        // Surface so the reader knows near-overlap counts may understate.
        console.log(`[sweep] near-overlap: truncated ${truncatedSections.length} section(s) at the 50-interactive cap (${truncatedSections.map(s => `${s.identity}=${s.interactiveCount}`).join(', ')})`);
      }

      overflow = pageData.overflow;
      const sectionAnomalies = pageData.sections.flatMap(s => s.anomalies);
      // Persist diagnostics BEFORE the screenshot — a screenshot failure
      // shouldn't erase analyses that already succeeded for this viewport.
      manifestEntrySections = pageData.sections;
      manifestEntryAnomalies = sectionAnomalies;

      await page.screenshot({ path: filePath, fullPage: true });
      const flags = [
        overflow.overflows ? 'OVERFLOW' : null,
        sectionAnomalies.length > 0 ? `${sectionAnomalies.length} section-anomalies` : null
      ].filter(Boolean);
      console.log('ok' + (flags.length > 0 ? ` [${flags.join(', ')}]` : ''));
    } catch (e) {
      error = e.message;
      console.log(`FAIL: ${e.message.split('\n')[0]}`);
    } finally {
      manifest.entries.push({
        width: w,
        deviceLabel: hint.name,
        theme: theme.name,
        dpr: hint.dpr,
        isMobile: hint.mobile,
        hasTouch: hint.touch,
        file: fileName,
        horizontalOverflow: overflow?.overflows ?? null,
        scrollWidth: overflow?.scrollWidth ?? null,
        consoleErrors: consoleErrors.length > 0 ? consoleErrors : undefined,
        error,
        sections: manifestEntrySections,
        sectionAnomalies: manifestEntryAnomalies
      });
      await context.close();
    }
  }
}

await browser.close();

// Cross-breakpoint delta check: compare per-section heights *within the same
// theme* across breakpoints. Mixing light/dark/reduced-motion samples masks
// real issues and produces false positives — a tall dark section at 320px and
// a short light section at 1440px shouldn't trigger a breakpoint-delta if
// each theme is internally stable.
const SUSPECT_RATIO = 8;
const samplesByKey = new Map();
for (const entry of manifest.entries) {
  for (const section of (entry.sections || [])) {
    const key = `${section.identity}@@${entry.theme}`;
    if (!samplesByKey.has(key)) samplesByKey.set(key, []);
    samplesByKey.get(key).push({
      identity: section.identity,
      width: entry.width,
      theme: entry.theme,
      height: section.height
    });
  }
}

const sectionAnomalyDeltas = [];
for (const [key, samples] of samplesByKey.entries()) {
  if (samples.length < 2) continue;
  const heights = samples.map(s => s.height).filter(h => h > 0);
  if (heights.length < 2) continue;
  const min = Math.min(...heights);
  const max = Math.max(...heights);
  if (min > 0 && max / min > SUSPECT_RATIO) {
    const tallest = samples.find(s => s.height === max);
    const shortest = samples.find(s => s.height === min);
    // Flip the direction. Original heuristic flagged
    // tallest.width < shortest.width — i.e. tall at narrow, short at wide. But
    // that's the *normal* stacked-mobile / row-desktop pattern: a 12-item grid
    // legitimately swings 8× in height when it stacks. Flagging it produced
    // noise on every responsive page. Invert: only flag tallest.width >
    // shortest.width — tall at WIDE, short at NARROW. That direction implies
    // desktop-only content (sidebar, banner) appearing only above a breakpoint
    // or layout that fails to scale down — a real signal worth the medium tag.
    if (tallest && shortest && tallest.width > shortest.width) {
      // Identity from the Map key — the per-sample object is fragile (insertion
      // order from forEach is stable today but not contractually guaranteed).
      const [identity, theme] = key.split('@@');
      sectionAnomalyDeltas.push({
        type: 'breakpoint-delta',
        severity: 'medium',
        identity,
        theme,
        message: `Section "${identity}" (${theme}) is ${max}px at ${tallest.width}px viewport but ${min}px at ${shortest.width}px viewport (${(max / min).toFixed(1)}× swing — section grows on wider viewports, opposite of normal stacking).`,
        samples
      });
    }
  }
}
manifest.sectionAnomalyDeltas = sectionAnomalyDeltas;

manifest.completedAt = new Date().toISOString();
writeFileSync(join(REPORT_DIR, 'manifest.json'), JSON.stringify(manifest, null, 2));

const overflows = manifest.entries.filter(e => e.horizontalOverflow);
const errors = manifest.entries.filter(e => e.error);
const totalAnomalies = manifest.entries.reduce((sum, e) => sum + (e.sectionAnomalies?.length ?? 0), 0);

console.log(`\n[sweep] complete.`);
console.log(`  total: ${manifest.entries.length}`);
console.log(`  with overflow: ${overflows.length}`);
console.log(`  errors: ${errors.length}`);
console.log(`  section anomalies: ${totalAnomalies} per-breakpoint, ${sectionAnomalyDeltas.length} cross-breakpoint deltas`);

if (overflows.length > 0) {
  console.log(`  affected widths: ${[...new Set(overflows.map(e => e.width))].join(', ')}`);
}
