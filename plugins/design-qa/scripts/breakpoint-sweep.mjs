#!/usr/bin/env node
// breakpoint-sweep.mjs — the responsive breakpoint sweep.
// Drives Playwright directly (more efficient than calling MCP one width at a time).

import { chromium, devices } from '@playwright/test';
import { mkdirSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';

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
if (!resolvedReportDir.startsWith(cwd + '/') && resolvedReportDir !== cwd) {
  console.error(`DESIGN_QA_REPORT_DIR must stay inside the workspace; got ${resolvedReportDir}`);
  process.exit(1);
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
      reducedMotion: theme.reducedMotion,
      extraHTTPHeaders: BYPASS ? {
        'x-vercel-protection-bypass': BYPASS,
        'x-vercel-set-bypass-cookie': 'true'
      } : {}
    });
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
          return [...main.children].filter(el => el.nodeType === 1);
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

          const fillRatio = leafAreaSum / sectionArea;

          // Adjacent-element near-overlap: walk direct interactive siblings and
          // measure vertical gap between successive ones.
          const interactives = [...sectionEl.querySelectorAll('a, button, input, select, textarea, [role=button], [role=link]')]
            .filter(el => {
              const r = el.getBoundingClientRect();
              return r.width > 0 && r.height > 0;
            });
          let nearOverlap = 0;
          for (let i = 1; i < interactives.length && i < 50; i++) {
            const a = interactives[i - 1].getBoundingClientRect();
            const b = interactives[i].getBoundingClientRect();
            // Only flag pairs that are stacked vertically AND whose horizontal
            // ranges overlap — sibling links in a row with their own gap aren't
            // a problem.
            const horizontallyOverlap = a.right > b.left && b.right > a.left;
            const gap = b.top - a.bottom;
            if (horizontallyOverlap && gap >= 0 && gap < 8) nearOverlap++;
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
            anomalies
          };
        });

        return { overflow, sections: sectionInfo };
      });

      overflow = pageData.overflow;
      const sectionAnomalies = pageData.sections.flatMap(s => s.anomalies);

      await page.screenshot({ path: filePath, fullPage: true });
      const flags = [
        overflow.overflows ? 'OVERFLOW' : null,
        sectionAnomalies.length > 0 ? `${sectionAnomalies.length} section-anomalies` : null
      ].filter(Boolean);
      console.log('ok' + (flags.length > 0 ? ` [${flags.join(', ')}]` : ''));

      manifestEntrySections = pageData.sections;
      manifestEntryAnomalies = sectionAnomalies;
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

// Cross-breakpoint delta check: track section identity across the matrix and
// flag any section whose height swings >8× and gets *taller* on narrower
// viewports (tall-on-narrow is normal; *wider* breakpoints being shorter is
// the smell — a section the design assumes is, say, 600px on desktop but
// spirals to 4000px on tablet usually means a flex/grid item is misbehaving).
const SUSPECT_RATIO = 8;
const heightsByIdentity = new Map();
for (const entry of manifest.entries) {
  for (const section of (entry.sections || [])) {
    if (!heightsByIdentity.has(section.identity)) heightsByIdentity.set(section.identity, []);
    heightsByIdentity.get(section.identity).push({
      width: entry.width,
      theme: entry.theme,
      height: section.height
    });
  }
}

const sectionAnomalyDeltas = [];
for (const [identity, samples] of heightsByIdentity) {
  if (samples.length < 2) continue;
  const heights = samples.map(s => s.height).filter(h => h > 0);
  if (heights.length < 2) continue;
  const min = Math.min(...heights);
  const max = Math.max(...heights);
  if (min > 0 && max / min > SUSPECT_RATIO) {
    const tallest = samples.find(s => s.height === max);
    const shortest = samples.find(s => s.height === min);
    if (tallest && shortest && tallest.width < shortest.width) {
      sectionAnomalyDeltas.push({
        type: 'breakpoint-delta',
        severity: 'medium',
        identity,
        message: `Section "${identity}" is ${max}px at ${tallest.width}px viewport but ${min}px at ${shortest.width}px viewport (${(max / min).toFixed(1)}× swing on the narrower side).`,
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
