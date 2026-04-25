---
name: design-qa-lite
description: Cross-agent portable design QA skill. Use when reviewing a deployed web URL for responsive layout, accessibility, Core Web Vitals, and SEO basics in any agent that supports markdown skills (Cursor, Codex, Gemini CLI, Claude Code without the design-qa plugin). Lighter than the full design-qa plugin but follows the same workflow.
---

# Design QA — Lite

Portable Markdown version of the `design-qa` Claude Code plugin. Use this in agents that don't have plugin support but do have skills support.

You're reviewing a deployed web URL. Run a multi-pass headless audit and produce a structured report.

## What this skill expects

Two install tiers — pick based on what you actually need.

**Minimum** (~3 deps, ~50 packages — fast, low audit noise):

```bash
npm i -D @playwright/test @axe-core/playwright axe-core
npx playwright install --with-deps chromium
```

Use minimum when you only need responsive sweep + accessibility. Skip phases 4 and 6 below.

**Full** (+3 deps, ~180 packages — required for Lighthouse + pa11y):

```bash
npm i -D @playwright/test @axe-core/playwright axe-core lighthouse chrome-launcher pa11y
npx playwright install --with-deps chromium
```

> **Note on `npm audit` noise:** the full tier surfaces ~50 transitive advisories from Lighthouse's deep dep chain (Puppeteer, deprecated middleware). These are dev-time tools — they don't ship to runtime. Use `npm audit --omit=dev` if a security scanner gates CI on the audit. Drop to the minimum tier if you can't tolerate the noise.

> **Do NOT install `playwright-lighthouse`.** The integration pattern (using `browser.wsEndpoint()`) breaks against current Playwright. Drive Lighthouse via `chrome-launcher` directly (pattern shown in phase 4).

## Phased review (same as the plugin)

### Phase 0: Prep

- Read `.claude/design-qa/reviewer.json` if it exists. If absent, use balanced strictness defaults.
- If reviewing a Vercel preview, set `VERCEL_AUTOMATION_BYPASS_SECRET` env var. Forward it as `extraHTTPHeaders: { 'x-vercel-protection-bypass': SECRET, 'x-vercel-set-bypass-cookie': 'true' }` on every Playwright context — never append it to the URL as a query param (the secret would land in reports, server logs, and the Chrome process list).
- Create report directory: `.claude/design-qa/reports/<ISO-timestamp>/`.

### Phase 1: Interaction & flow

Drive Playwright headless. Navigate, wait for `networkidle` and `document.fonts.ready`. Tab through the page 10–15 times; record focus order. Read console messages — any errors get logged.

### Phase 2: Responsive sweep + section anomalies

For each width in `[280, 320, 360, 375, 390, 414, 480, 600, 700, 768, 834, 900, 1024, 1180, 1280, 1440, 1920, 2560]`:

1. Set viewport, DPR (3 ≤ 600px, 2 ≤ 1024px, 1 above), `isMobile: true` if width ≤ 600.
2. Inject CSS to disable animations + transitions, including delays:
   `*, *::before, *::after { animation-duration: 0s !important; animation-delay: 0s !important; transition-duration: 0s !important; transition-delay: 0s !important; }`.
3. Wait 200ms for the disable to take effect.
4. Capture full-page screenshot to `screenshots/<width>-<theme>.png`.
5. Check `document.documentElement.scrollWidth > clientWidth` for horizontal overflow.
6. Repeat with `colorScheme: 'dark'` and `reducedMotion: 'reduce'`.

**Section-anomaly sub-pass** (`scrollWidth > clientWidth` alone misses real layout bugs — it doesn't catch huge empty bands between sections, hydration-collapsed islands, near-overlapping interactives, or dramatic per-section breakpoint deltas):

Walk top-level sections (`main > section`, falling back to direct children of `<main>`) on each viewport and emit findings when:

- **`empty-band`** (high) — section height > 600px AND fill-ratio < 0.30 (where fill ratio = sum of leaf-element rect areas ÷ section bounding rect area). Indicates an empty hero, broken flex/grid, or a content block that didn't render.
- **`collapsed-island`** (medium) — section rendered at < 40px. Hydration failure or empty config.
- **`near-overlap`** (medium) — adjacent interactive elements (`a`, `button`, `input`, `[role=button]`) with vertical gap < 8px and overlapping horizontal range. Missing margin/padding token.
- **`breakpoint-delta`** (medium, computed across the matrix after the loop) — a section's max/min height ratio across breakpoints is > 8× *and* the tallest sample is at a narrower viewport than the shortest. Tall-on-narrow is normal; tall-on-narrow-when-the-wider-breakpoint-is-shorter is the smell.

Surface these as advisories. **Do not gate CI on them** — they're heuristics with false-positive risk.

### Phase 3: Accessibility

For each of `[375, 768, 1440]` × `[light, dark]`:
1. Run `AxeBuilder({ page }).withTags(['wcag2a','wcag2aa','wcag21a','wcag21aa','wcag22aa','best-practice']).analyze()`.
2. Hover the first 10 interactive elements (`a, button, [role=button], input, select, textarea`). Re-run axe with the same tags; the hover-only set = violations not in the default-state result.
3. Tab through 10 times. Re-run axe; the focus-only set = violations not in default AND not in hover.

Use a stable per-violation-per-node key for dedup (`${rule.id}|${JSON.stringify(node.target)}`); `target.join(',')` collides when CSS selectors themselves contain commas.

Run Pa11y separately at the same widths for second-opinion coverage. If reviewing a protected preview, pa11y has no header CLI flag — write a temp config file with `headers` and pass `--config <path>`.

### Phase 4: Core Web Vitals

**Drive Lighthouse via `chrome-launcher`, NOT `playwright-lighthouse`.** Spawn each profile in its own Node subprocess — chrome-launcher state can leak between back-to-back launches in the same process and the first profile's `lhr.categories.*` come back null.

```js
import lighthouse from 'lighthouse';
import * as chromeLauncher from 'chrome-launcher';

const chrome = await chromeLauncher.launch({ chromeFlags: ['--headless=new', '--no-sandbox'] });
try {
  const result = await lighthouse(URL, {
    port: chrome.port,
    formFactor: 'mobile',          // or 'desktop'
    onlyCategories: ['performance', 'accessibility', 'best-practices', 'seo'],
    extraHeaders: { 'x-vercel-protection-bypass': BYPASS, 'x-vercel-set-bypass-cookie': 'true' },
    // Pass bypass via headers — never via query string.
  });
} finally {
  await chrome.kill();
}
```

Wrap mobile and desktop in `try/finally` so Chrome reaps even if Lighthouse throws.

**Instrumentation-suspect filter.** A single stalled third-party tracker (Termly, PostHog, Segment, Hotjar) under simulated 4× CPU + Slow 4G can blow up mobile metrics — observed mobile LCP=48s on a fast static page that desktop measured at 1.4s. After both profiles complete, compute `mobileSuspect = mobile.lcp / desktop.lcp > 8` (also check TBT, FCP, TTI, speedIndex). When suspect, render the affected mobile metric with a `⚠️ instrumentation-suspect` annotation, demote it from Blocker to Medium, and evaluate the metric gate against desktop instead. Do NOT silently drop the mobile run — the user should know mobile was flagged.

When mobile metrics matter for the call you're making, re-run with Lighthouse's `blockedUrlPatterns` for the offending domain, or cross-reference with Vercel Speed Insights (real user data, not synthetic).

### Phase 5: SEO & meta

Extract: `<title>`, meta description, canonical, `<html lang>`, viewport meta, all `og:*`, all `twitter:*`, all JSON-LD blocks. Validate JSON-LD parses as JSON. Fetch `og:image` to verify it's reachable — apply a timeout (~8s), a redirect cap (~5), and a size cap (~10MB) to stop slow or huge responses from stalling the run. **Only forward the bypass header to same-origin `og:image` URLs**; if `og:image` points to a CDN or third-party host, fetch without the secret so it doesn't leak to that origin. Recommended dimensions are 1200×630 for `og:image` and 1200×675 for Twitter `summary_large_image`; check manually if the value isn't obvious from the URL.

### Phase 6: Visual regression

If Argos token is set, upload screenshots. Otherwise, compare against `__screenshots__/` baselines via Playwright `toHaveScreenshot`.

### Phase 7: Persona pass

Apply reviewer.json: brand tokens (sample 50 elements), anti-patterns (gradient buttons, emoji icons, faux-3D shadows, glassmorphism), voice rules (jargon, wordy CTAs).

## Severity ranking

- **Blocker:** WCAG-A violations, contrast failures on visible text, missing critical SEO (title, lang), broken layouts at standard widths, **trustworthy** LCP > 4s, perf < 50 (skip if mobile is instrumentation-suspect — use desktop).
- **High:** WCAG-AA violations, LCP > 2.5s, INP > 200ms, missing meta description, missing focus indicators, `empty-band` section anomaly.
- **Medium:** Best-practice violations, off-token spacing/colors, AI slop patterns, opportunities > 100KB savings, `collapsed-island` / `near-overlap` / `breakpoint-delta` section anomalies.
- **Nitpicks:** "Needs review" axe items, sub-pixel diffs, missing optional meta.

## Alternative driver: agent-browser

Default to Playwright. For most audits the parallelism advantage matters — a 36-snapshot sweep takes ~3 min on Playwright vs ~25 min on agent-browser's single-session sequential model.

agent-browser is viable for interactive/smoke passes (especially when you want first-class console + errors capture). Two foot-guns to know about:

- **eval envelope.** `agent-browser eval --json` returns `{success, data: {origin, result}}` — it's an envelope, not a flat value. Easy to mis-parse and silently lose data. Always read `.data.result` (or check `.success === false`), never assume the top-level shape.
- **Lighthouse.** agent-browser ships its own chrome-launcher hookup that works first-try, so the wsEndpoint foot-gun in #4 doesn't apply. But the runtime overhead per audit is much higher.

Both drivers should converge on identical findings (axe rule IDs, pa11y codes, SEO meta extraction). If they don't, that's a bug in the driver wrapper, not a real difference in the page.

## Hard rules

- Never fabricate metric numbers. If a tool fails, say so.
- Every finding needs evidence: screenshot path, console log, or measured number.
- Never commit `playwright/.auth/`. Never echo credentials.

## Output

Three files in the report directory: `summary.md` (paste-into-PR), `report.json` (CI gates), `report.html` (browser preview). Format the markdown with: header, verdict, blockers, high, medium, nitpicks, metrics table, section-anomaly section if any, Argos build link.

When mobile is instrumentation-suspect, render the mobile column with a `⚠️` annotation and include a one-line note recommending `blockedUrlPatterns` or Speed Insights for follow-up.

## Differences from the full plugin

The plugin gives you:
- Auto-installed Playwright MCP (no manual install).
- Slash commands (`/design-qa:review`).
- Hooks (axe-on-screenshot).
- Auth setup templates for Clerk/Supabase/Auth.js.
- Pre-built reporters with the section-anomaly + suspect-metric rendering.

This skill gives you the workflow without the scaffolding. You'll need to drive Playwright directly. For a full experience, install the plugin: `/plugin install design-qa@stacks-inc-skills`.
