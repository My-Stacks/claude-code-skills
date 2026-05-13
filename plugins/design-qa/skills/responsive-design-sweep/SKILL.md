---
name: responsive-design-sweep
description: Use when capturing screenshots of a deployed web page across many viewport widths to find layout breaks. Specifically catches "grey area" widths (700, 900, 1180) where designs commonly fail between standard breakpoints. Sweeps 18 widths × light/dark/reduced-motion themes by default.
---

# Responsive Design Sweep

You're capturing the responsive screenshot matrix for a design QA review.

## Breakpoint matrix

The matrix is determined by `${user_config.breakpointPreset}`:

**`fast`** (5 widths × 1 theme = 5 screenshots):
```text
375, 768, 1024, 1440, 1920
```

**`agency-default`** (18 widths × 3 themes = 54 screenshots):
```text
280, 320, 360, 375, 390, 414, 480, 600, 700, 768,
834, 900, 1024, 1180, 1280, 1440, 1920, 2560
```

**`thorough`** (21 widths × 3 themes = 63 screenshots):
```text
agency-default + 384 (foldable outer), 3840 (4K)
```

(Earlier versions of this doc listed `844x390 landscape` and `print media` for `thorough`; those aren't implemented in `breakpoint-sweep.mjs` and the doc has been pulled back to match the runner's actual matrix.)

Why these widths: 280 covers folded foldables; 320/360/375/390/414 cover the common phone range including iPhone mini through Pro Max; 480 catches large phone landscape; 600/700 are the **foldable-inner / awkward-tablet zone where designs frequently fail**; 768/834/900 cover the iPad-portrait-to-landscape transition; 1024/1180/1280/1440/1920/2560 cover the laptop-to-large-monitor spectrum.

## Theme variants per width

For each width, the runner captures three theme variants:
1. Light theme, default state.
2. Dark theme (`prefers-color-scheme: dark`).
3. Reduced motion (`prefers-reduced-motion: reduce`) — light theme.

The `fast` preset captures only variant 1 (light, default).

A separate focus-state pass over interactive elements happens during the `run-axe.mjs` accessibility audit, not in the responsive sweep.

## Stability before screenshot

ALWAYS, before each screenshot:
1. `await page.waitForLoadState('networkidle')`.
2. `await page.evaluate(() => document.fonts.ready)`.
3. Inject CSS to disable animations and transitions, including their delays: `*, *::before, *::after { animation-duration: 0s !important; animation-delay: 0s !important; transition-duration: 0s !important; transition-delay: 0s !important; }`.
4. Wait 200ms for the disable to take effect.

## How to invoke

The script `${CLAUDE_PLUGIN_ROOT}/bin/run-sweep.sh <url> <preset>` handles all of this (delegating to `breakpoint-sweep.mjs`). It:
- Iterates the matrix.
- Uses Playwright's device emulation when a width matches a known device (e.g., 390 → "iPhone 14 Pro" with DPR 3, touch, mobile UA).
- For unknown widths, sets DPR=3 for widths ≤ 600, DPR=2 for widths ≤ 1024, DPR=1 above; treats widths ≤ 600 as mobile and ≤ 768 as touch.
- Saves PNGs to `.claude/design-qa/reports/<timestamp>/screenshots/<width>-<theme>.png` (one per width × theme; interaction states are exercised in the axe pass, not here).
- Writes `manifest.json` with one entry per screenshot — the entries reference the same `<width>-<theme>.png` filenames and include the in-page horizontal-overflow check result.

You should call this script rather than driving Playwright MCP one width at a time — it's much faster and uses far fewer tokens.

## Section anomalies (heuristic sub-pass)

`scrollWidth > clientWidth` only catches horizontal overflow. It misses the failure modes that show up as visual mistakes: huge empty bands between sections, hydration-collapsed islands, near-overlapping interactives, and dramatic per-section breakpoint deltas.

The runner walks top-level sections (`main > section`, falling back to direct children of `<main>`) on every captured viewport and emits findings under `manifest.entries[].sectionAnomalies[]`:

- **`empty-band`** (high) — section height > 600px AND content fill ratio < 0.30. The page's design probably calls for a hero or content block that didn't render, or a flex/grid container is over-stretching.
- **`collapsed-island`** (medium) — section rendered at < 40px. Hydration failure, missing data, or empty config.
- **`near-overlap`** (medium) — adjacent interactive elements (`a`, `button`, `input`) with vertical gap < 8px. Likely a missing margin/padding token.

After the sweep loop, the runner also computes cross-breakpoint deltas under `manifest.sectionAnomalyDeltas[]`:

- **`breakpoint-delta`** (medium) — a section's max/min height ratio across the breakpoint matrix is > 8× *and* the tallest sample is at a narrower viewport than the shortest. Tall-on-narrow is normal; tall-on-narrow-when-wider-is-shorter usually means a layout primitive is misbehaving.

These are heuristics — surface them to the user, but **don't gate CI on them**. The reporters render them in their own "Section anomalies" block flagged as advisory.

## After the sweep

Read `manifest.json`. For each entry where `horizontalOverflow: true`, this is a Blocker if the width is ≤ 1440. Surface them. Then fold in the per-breakpoint and cross-breakpoint section-anomaly findings (above) as Medium / High advisories — they are not blockers by default, but they often surface real visual bugs the static analyses miss.

For each width, view the screenshots side by side (light/dark) and look for:
- Touch targets <44×44 (a11y) — only at widths ≤ 768.
- Text smaller than 14px on mobile or 16px on body copy.
- Images stretched or letterboxed unintentionally.
- Hero CTAs truncated, buttons wrapping awkwardly, navigation collapsing too early/late.

## Output to the parent agent

Return a summary with:
- Total screenshots captured.
- Count of widths with horizontal overflow.
- The 3 worst breakpoints (most issues).
- Path to the report directory so the parent agent can view individual screenshots.
