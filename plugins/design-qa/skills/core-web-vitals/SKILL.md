---
name: core-web-vitals
description: Use when measuring Lighthouse / Core Web Vitals (LCP, INP, CLS, TBT) on a deployed page. Runs both mobile and desktop profiles, reports actual measured numbers, and identifies top opportunities.
---

# Core Web Vitals & Lighthouse

Measure performance on `<url>` using `playwright-lighthouse`.

## Hard rule: never fabricate metrics

If the script fails (URL unreachable, auth required, Lighthouse crashes), say so plainly. Do not invent numbers. Surface the failure to the parent agent.

## How to invoke

`${CLAUDE_PLUGIN_ROOT}/bin/run-lighthouse.sh <url>` runs:

1. **Mobile run.** Profile: Moto G Power, Slow 4G throttling, 4× CPU slowdown. This is Google's default for `web.dev/measure` and the only profile that matters for Core Web Vitals as a search ranking signal.
2. **Desktop run.** No throttling, 1440×900 viewport.

Each run outputs HTML + JSON to `.claude/design-qa/reports/<timestamp>/lighthouse/<profile>/`.

## Reading the JSON

Pull these fields:

| Field | JSON path |
|---|---|
| LCP | `audits.largest-contentful-paint.numericValue` (ms) |
| INP | `audits.interaction-to-next-paint.numericValue` (ms, may be null if no interactions captured) |
| CLS | `audits.cumulative-layout-shift.numericValue` |
| TBT | `audits.total-blocking-time.numericValue` (ms) |
| FCP | `audits.first-contentful-paint.numericValue` (ms) |
| Perf score | `categories.performance.score` (0-1) |
| A11y score | `categories.accessibility.score` |
| Best Practices | `categories.best-practices.score` |
| SEO | `categories.seo.score` |

## Thresholds (Google's official Web Vitals as of 2026)

| Metric | Good | Needs improvement | Poor |
|---|---|---|---|
| LCP | ≤ 2.5s | 2.5–4.0s | > 4.0s |
| INP | ≤ 200ms | 200–500ms | > 500ms |
| CLS | ≤ 0.1 | 0.1–0.25 | > 0.25 |
| TBT | ≤ 200ms | 200–600ms | > 600ms |

## Severity mapping

- **Blocker:** Mobile Perf score < 50, LCP > 4s, CLS > 0.25.
- **High:** Mobile Perf score < 80, LCP > 2.5s, INP > 200ms, CLS > 0.1.
- **Medium:** Any Lighthouse opportunity with > 100KB savings or > 500ms savings.
- **Nitpicks:** "Diagnostics" items that aren't classified as opportunities.

## Top opportunities

Pull `audits` where `details.type === 'opportunity'` and sort by `numericValue` (estimated savings in ms or bytes). Surface the top 3:

```
1. eliminate-render-blocking-resources — saves ~1,400ms (CSS/JS in head)
2. unused-javascript — saves ~340KB across 4 bundles
3. modern-image-formats — saves ~180KB (5 images served as PNG, could be AVIF/WebP)
```

## Output

```markdown
## Core Web Vitals & Lighthouse

| Metric | Mobile | Desktop |
|---|---|---|
| LCP | 3.2s ⚠️ | 1.4s ✅ |
| INP | 142ms ✅ | 38ms ✅ |
| CLS | 0.04 ✅ | 0.02 ✅ |
| TBT | 210ms ⚠️ | 30ms ✅ |
| Perf | 71 ⚠️ | 96 ✅ |
| A11y | 96 ✅ | 96 ✅ |
| BP | 100 ✅ | 100 ✅ |
| SEO | 100 ✅ | 100 ✅ |

### Top opportunities (mobile)
1. ...
2. ...
3. ...

Reports: `lighthouse/mobile/report.html`, `lighthouse/desktop/report.html`
```
