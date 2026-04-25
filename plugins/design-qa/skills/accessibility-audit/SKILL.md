---
name: accessibility-audit
description: Use when running a WCAG 2.2 AA accessibility audit on a deployed web page. Combines axe-core and Pa11y, triggers hover/focus states (which axe misses by default), tests across light/dark themes, and outputs severity-ranked findings.
---

# Accessibility Audit

You're running a WCAG 2.2 AA scan against a deployed page.

## Why this is more than just "run axe once"

Default axe-core scans miss:
- Color contrast on **hover** and **focus** states (axe scans default state only).
- Color contrast in **dark mode** (axe scans the current theme).
- Issues that only surface when components are in an error/loading/disabled state.
- Some parsing rules and SC 1.4.10 reflow that Pa11y catches.

So: run axe in multiple states, AND run Pa11y for second-opinion coverage.

## How to invoke

The full audit is wrapped in `${CLAUDE_PLUGIN_ROOT}/bin/run-axe.sh <url>`.

This script:
1. Loads the page in headless Chromium at 375 (mobile), 768 (tablet), 1440 (desktop).
2. Runs `@axe-core/playwright` `AxeBuilder` with WCAG 2.2 A and AA rules.
3. For each interactive element (`a`, `button`, `[role=button]`, `input`, `select`, `textarea`):
   a. Triggers `:hover` via `page.hover()`. Re-runs axe on just that element's subtree.
   b. Triggers `:focus` via `page.focus()`. Re-runs axe.
4. Switches to dark theme (`emulateMedia: { colorScheme: 'dark' }`). Repeats steps 2-3.
5. Outputs JSON to `.claude/design-qa/reports/<timestamp>/axe/<width>-<theme>-<state>.json`.

Then `${CLAUDE_PLUGIN_ROOT}/bin/run-pa11y.sh <url>` runs Pa11y at the same widths and writes to `.claude/design-qa/reports/<timestamp>/pa11y/`.

## Combining results

After both scripts complete:

1. Deduplicate findings by `(rule_id, selector, viewport)`.
2. Apply the reviewer persona's `excludeRules` from `.claude/design-qa/reviewer.json`. Note suppressions explicitly.
3. Severity:
   - **Blocker:** WCAG-A violations, contrast failures on visible text (any state), keyboard traps, missing labels on form inputs.
   - **High:** WCAG-AA violations, missing focus indicators, heading hierarchy issues.
   - **Medium:** Best-practice violations (missing landmarks, redundant ARIA).
   - **Nitpicks:** "Needs review" items that require human judgment.

## What axe misses entirely (still flag manually if you see them)

axe and Pa11y combined cover ~57% of WCAG. Things you should still look for in the screenshots:

- **Cognitive load:** dense interfaces, ambiguous icons without labels.
- **Motion sickness:** auto-playing video, parallax that respects `prefers-reduced-motion`.
- **Form usability:** error messages adjacent to inputs, success confirmation, undo affordances.
- **Brand contrast vs. functional contrast:** "the brand is gray-on-gray" doesn't excuse 3.0:1 contrast.

## Output

Return a markdown report:
```markdown
## Accessibility (axe + Pa11y, WCAG 2.2 AA)
- Scanned: 3 viewports × 2 themes × 2 interaction states = 12 scans
- Total unique violations: N
- Suppressed by reviewer config: N (rules: ...)

### Blockers (N)
- `color-contrast` on `.cta-primary:hover` at 1440 dark — 3.1:1 vs 4.5:1 required. Evidence: `axe/1440-dark-hover.json`.

### High (N)
...
```

Include the path to all underlying JSON in case the parent agent wants to drill in.
