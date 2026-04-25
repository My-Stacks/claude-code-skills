---
description: Just Core Web Vitals and Lighthouse. Mobile + desktop runs.
argument-hint: <url>
allowed-tools: Bash, Read, Write
---

Run Lighthouse against `$1`.

1. Run `bash ${CLAUDE_PLUGIN_ROOT}/bin/run-lighthouse.sh "$1"` — uses `playwright-lighthouse`:
   - One mobile run (Moto G Power profile, slow 4G throttling).
   - One desktop run (no throttling).
   - Outputs HTML + JSON to `.claude/design-qa/reports/<timestamp>/lighthouse/`.
2. Parse the JSON. Surface:
   - LCP, INP, CLS, TBT, FCP — actual numbers, with green/yellow/red thresholds.
   - Performance / Accessibility / Best Practices / SEO scores.
   - Top 3 opportunities (render-blocking, unused JS, oversized images, etc.) with byte-cost.
3. Report as a markdown table with mobile and desktop columns side-by-side.
4. Severity:
   - **Blocker:** LCP > 4s, performance score < 50, CLS > 0.25.
   - **High:** LCP > 2.5s, INP > 200ms, performance score < 80.
   - **Medium:** any opportunity > 100KB savings.

Never fabricate metric numbers. If Lighthouse fails to run (e.g., URL 401s), report the failure and stop.
