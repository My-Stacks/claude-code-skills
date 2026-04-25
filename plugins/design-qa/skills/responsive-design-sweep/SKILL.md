---
name: responsive-design-sweep
description: Use when capturing screenshots of a deployed web page across many viewport widths to find layout breaks. Specifically catches "grey area" widths (700, 900, 1180) where designs commonly fail between standard breakpoints. Sweeps 18 widths × light/dark/reduced-motion themes by default.
---

# Responsive Design Sweep

You're capturing the responsive screenshot matrix for a design QA review.

## Breakpoint matrix

The matrix is determined by `${user_config.breakpointPreset}`:

**`fast`** (5 widths, ~30 screenshots):
```
375, 768, 1024, 1440, 1920
```

**`agency-default`** (18 widths, default, ~108 screenshots):
```
280, 320, 360, 375, 390, 414, 480, 600, 700, 768,
834, 900, 1024, 1180, 1280, 1440, 1920, 2560
```

**`thorough`** (agency-default + extras, ~180 screenshots):
```
agency-default + 384 (foldable outer), 3840 (4K), 844x390 landscape, print media
```

Why these widths: 280 covers folded foldables; 320/360/375/390/414 cover the common phone range including iPhone mini through Pro Max; 480 catches large phone landscape; 600/700 are the **foldable-inner / awkward-tablet zone where designs frequently fail**; 768/834/900 cover the iPad-portrait-to-landscape transition; 1024/1180/1280/1440/1920/2560 cover the laptop-to-large-monitor spectrum.

## Theme variants per width

For each width, capture:
1. Light theme, default state.
2. Dark theme (`prefers-color-scheme: dark`).
3. Reduced motion (`prefers-reduced-motion: reduce`) — light theme.
4. Focus state on the first interactive CTA above the fold (Tab once, screenshot).

Skip variants 3 and 4 if `${user_config.breakpointPreset}` is `fast`.

## Stability before screenshot

ALWAYS, before each screenshot:
1. `await page.waitForLoadState('networkidle')`.
2. `await page.evaluate(() => document.fonts.ready)`.
3. Inject CSS to disable animations: `* { animation-duration: 0s !important; transition-duration: 0s !important; }`.
4. Wait 200ms for the disable to take effect.

## How to invoke

The script `${CLAUDE_PLUGIN_ROOT}/bin/run-sweep.sh <url> <preset>` handles all of this. It:
- Iterates the matrix.
- Uses Playwright's device emulation when a width matches a known device (e.g., 390 → "iPhone 14 Pro" with DPR 3, touch, mobile UA).
- For unknown widths, sets DPR=2 and `isMobile: true` for widths ≤ 600.
- Saves PNGs to `.claude/design-qa/reports/<timestamp>/screenshots/<width>-<theme>-<state>.png`.
- Writes `manifest.json` with one entry per screenshot including the in-page horizontal-overflow check result.

You should call this script rather than driving Playwright MCP one width at a time — it's much faster and uses far fewer tokens.

## After the sweep

Read `manifest.json`. For each entry where `horizontalOverflow: true`, this is a Blocker if the width is ≤ 1440. Surface them.

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
