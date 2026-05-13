---
name: core-web-vitals
description: Use when measuring Lighthouse / Core Web Vitals (LCP, INP, CLS, TBT) on a deployed page. Runs both mobile and desktop profiles, reports actual measured numbers, and identifies top opportunities.
---

# Core Web Vitals & Lighthouse

Measure performance on `<url>` using `${CLAUDE_PLUGIN_ROOT}/bin/run-lighthouse.sh <url>`.

## Hard rule: never fabricate metrics

If the script fails (URL unreachable, auth required, Lighthouse crashes), say so plainly. Do not invent numbers. Surface the failure to the parent agent.

## How to invoke

`${CLAUDE_PLUGIN_ROOT}/bin/run-lighthouse.sh <url>` runs each profile in its own Node subprocess:

1. **Mobile run.** Profile: Moto G Power-shaped emulation, Slow 4G throttling, 4× CPU slowdown. This is Google's default for `web.dev/measure` and the only profile that matters for Core Web Vitals as a search ranking signal.
2. **Desktop run.** No throttling, 1350×940 emulation.
3. **Merge step.** A third short Node call combines `lighthouse/mobile/result.json` + `lighthouse/desktop/result.json` into the shared `lighthouse/summary.json` shape, computing the instrumentation-suspect flag along the way.

Why subprocess-per-profile: chrome-launcher state can leak between back-to-back launches in the same Node process, returning null categories on the first profile. Each profile in a fresh subprocess eliminates the leak.

Each run outputs HTML + JSON to `.claude/design-qa/reports/<timestamp>/lighthouse/<profile>/`.

## Instrumentation-suspect filter

A single stalled third-party tracker (Termly, PostHog, Segment, Hotjar) under simulated 4× CPU + Slow 4G can blow up mobile metrics — Kyle observed mobile LCP=48s on a fast static page that desktop measured at 1.4s. Reporting that as a Blocker would mislead reviewers.

The merge step computes `summary.mobile.instrumentationSuspect = true` whenever `mobile metric / desktop metric > 8` for LCP, TBT, FCP, TTI, or speedIndex, and exposes the offending metrics under `summary.mobile.suspectMetrics`. Reporters render the affected mobile cells with a ⚠️ annotation. The CI gates in `report.json` evaluate `lcpUnder4s` and `perfScoreOver50` against **desktop** when mobile is suspect, and surface a `gates.mobileMetricsTrusted: false` advisory.

When mobile metrics matter for the call you're making, re-run with the offending domain blocked, or cross-reference with Vercel Speed Insights (real user data, not synthetic). The wrapper forwards `DESIGN_QA_BLOCKED_URL_PATTERNS` (comma-separated URL substrings, Lighthouse pattern syntax) to `lighthouse({ blockedUrlPatterns })` — e.g. `DESIGN_QA_BLOCKED_URL_PATTERNS="termly.io,posthog.com,segment.io,hotjar" ${CLAUDE_PLUGIN_ROOT}/bin/run-lighthouse.sh <url>`.

## Reading the JSON

The merge step writes `lighthouse/summary.json` with a flat wrapper shape — read from that, not from the raw Lighthouse `report.json` (which lives at `lighthouse/<profile>/report.json` for drill-down).

```jsonc
// lighthouse/summary.json
{
  "mobile": {
    "scores": { "performance": 71, "accessibility": 96, "bestPractices": 100, "seo": 100 },
    "metrics": { "lcp": 3200, "inp": 142, "cls": 0.04, "tbt": 210, "fcp": 1800, "tti": 4100, "speedIndex": 2900 },
    "opportunities": [{ "id": "...", "title": "...", "savingsMs": 1400, "savingsBytes": 180000 }],
    "instrumentationSuspect": false,    // true when mobile metric / desktop > 8×
    "suspectMetrics": []                 // populated when suspect (e.g. ['lcp', 'tbt'])
  },
  "desktop": { /* same shape */ }
}
```

| Field | Path on summary.json |
|---|---|
| LCP | `mobile.metrics.lcp` (ms; same path on `desktop`) |
| INP | `mobile.metrics.inp` (ms, may be null if no interactions) |
| CLS | `mobile.metrics.cls` |
| TBT | `mobile.metrics.tbt` (ms) |
| FCP | `mobile.metrics.fcp` (ms) |
| Perf score | `mobile.scores.performance` (0–100, already scaled) |
| A11y score | `mobile.scores.accessibility` |
| Best Practices | `mobile.scores.bestPractices` |
| SEO | `mobile.scores.seo` |
| Top opportunities | `mobile.opportunities[]` (already top-5, sorted by savings) |
| Suspect mobile run | `mobile.instrumentationSuspect`, `mobile.suspectMetrics` |

When `instrumentationSuspect` is true, `report.json` flips `gates.mobileMetricsTrusted` to `false` and evaluates `gates.lcpUnder4s` / `gates.perfScoreOver50` against `desktop` instead — the advisory bit is non-blocking, the metric gates use the trustworthy source.

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

```text
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
