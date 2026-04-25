---
name: design-qa-lite
description: Cross-agent portable design QA skill. Use when reviewing a deployed web URL for responsive layout, accessibility, Core Web Vitals, and SEO basics in any agent that supports markdown skills (Cursor, Codex, Gemini CLI, Claude Code without the design-qa plugin). Lighter than the full design-qa plugin but follows the same workflow.
---

# Design QA — Lite

Portable Markdown version of the `design-qa` Claude Code plugin. Use this in agents that don't have plugin support but do have skills support.

You're reviewing a deployed web URL. Run a multi-pass headless audit and produce a structured report.

## What this skill expects

Before running, the project should have these dev dependencies installed:
- `@playwright/test`
- `@axe-core/playwright`
- `axe-core`
- `playwright-lighthouse`
- `lighthouse`
- `pa11y`

If they're missing, install them: `npm i -D @playwright/test @axe-core/playwright axe-core playwright-lighthouse lighthouse pa11y && npx playwright install --with-deps chromium`.

## Phased review (same as the plugin)

### Phase 0: Prep

- Read `.claude/design-qa/reviewer.json` if it exists. If absent, use balanced strictness defaults.
- If reviewing a Vercel preview, set `VERCEL_AUTOMATION_BYPASS_SECRET` env var before running.
- Create report directory: `.claude/design-qa/reports/<ISO-timestamp>/`.

### Phase 1: Interaction & flow

Drive Playwright headless. Navigate, wait for `networkidle` and `document.fonts.ready`. Tab through the page 10–15 times; record focus order. Read console messages — any errors get logged.

### Phase 2: Responsive sweep

For each width in `[280, 320, 360, 375, 390, 414, 480, 600, 700, 768, 834, 900, 1024, 1180, 1280, 1440, 1920, 2560]`:
1. Set viewport, DPR (3 ≤ 600px, 2 ≤ 1024px, 1 above), `isMobile: true` if width ≤ 600.
2. Inject CSS to disable animations.
3. Capture full-page screenshot.
4. Check `document.documentElement.scrollWidth > clientWidth` for horizontal overflow.
5. Repeat with `colorScheme: 'dark'` and `reducedMotion: 'reduce'`.

Save PNGs to `screenshots/<width>-<theme>.png`.

### Phase 3: Accessibility

For each of `[375, 768, 1440]` × `[light, dark]`:
1. Run `AxeBuilder({ page }).withTags(['wcag2a','wcag2aa','wcag22aa']).analyze()`.
2. Hover the first 10 interactive elements (`a, button, [role=button], input, select, textarea`). Re-run axe; surface NEW violations only.
3. Tab through 10 times. Re-run axe; surface NEW violations only.

Run Pa11y separately at the same widths for second-opinion coverage.

### Phase 4: Core Web Vitals

Run Lighthouse with mobile profile (Moto G Power, Slow 4G, 4× CPU) and desktop profile. Capture LCP, INP, CLS, TBT, FCP, performance score, a11y score, BP, SEO.

### Phase 5: SEO & meta

Extract: `<title>`, meta description, canonical, `<html lang>`, viewport meta, all `og:*`, all `twitter:*`, all JSON-LD blocks. Validate JSON-LD parses as JSON. Fetch `og:image` to verify it's reachable — apply a timeout (~8s), a redirect cap (~5), and a size cap (~10MB) to stop slow or huge responses from stalling the run, and pass the same bypass header as the page request when scanning protected previews. Recommended dimensions are 1200×630 for `og:image` and 1200×675 for Twitter `summary_large_image`; check manually if the value isn't obvious from the URL.

### Phase 6: Visual regression

If Argos token is set, upload screenshots. Otherwise, compare against `__screenshots__/` baselines via Playwright `toHaveScreenshot`.

### Phase 7: Persona pass

Apply reviewer.json: brand tokens (sample 50 elements), anti-patterns (gradient buttons, emoji icons, faux-3D shadows, glassmorphism), voice rules (jargon, wordy CTAs).

## Severity ranking

- **Blocker:** WCAG-A violations, contrast failures on visible text, missing critical SEO (title, lang), broken layouts at standard widths, LCP > 4s, perf < 50.
- **High:** WCAG-AA violations, LCP > 2.5s, INP > 200ms, missing meta description, missing focus indicators.
- **Medium:** Best-practice violations, off-token spacing/colors, AI slop patterns, opportunities > 100KB savings.
- **Nitpicks:** "Needs review" axe items, sub-pixel diffs, missing optional meta.

## Hard rules

- Never fabricate metric numbers. If a tool fails, say so.
- Every finding needs evidence: screenshot path, console log, or measured number.
- Never commit `playwright/.auth/`. Never echo credentials.

## Output

Three files in the report directory: `summary.md` (paste-into-PR), `report.json` (CI gates), `report.html` (browser preview). Format the markdown with: header, verdict, blockers, high, medium, nitpicks, metrics table, Argos build link.

## Differences from the full plugin

The plugin gives you:
- Auto-installed Playwright MCP (no manual install).
- Slash commands (`/design-qa:review`).
- Hooks (axe-on-screenshot).
- Auth setup templates for Clerk/Supabase/Auth.js.
- Pre-built reporters.

This skill gives you the workflow without the scaffolding. You'll need to drive Playwright directly. For a full experience, install the plugin: `/plugin install design-qa@stacks-inc-skills`.
