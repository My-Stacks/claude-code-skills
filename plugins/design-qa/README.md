# `design-qa` — Stacklab Design QA Specialist

Headless responsive UI review for Claude Code, optimized for Vercel preview deploys but works against any URL.

## What it does

A single `/design-qa:review <url>` runs a full multi-pass audit:

1. **Responsive sweep** across 18 breakpoints (configurable) with light/dark/reduced-motion variants. Captures default, hover, focus, and active states for interactive elements.
2. **Accessibility audit** via axe-core at every breakpoint. Catches WCAG 2.2 AA violations including contrast on hover/focus/dark mode (which axe misses by default unless states are triggered first).
3. **Core Web Vitals** via Lighthouse — LCP, INP, CLS, TBT, plus a11y/SEO/best-practices scores.
4. **SEO + meta** — Open Graph, Twitter Card, JSON-LD validation, canonical URL, viewport meta, lang attribute, heading hierarchy, alt text.
5. **Visual regression** — uploads to Argos for baseline comparison, OR uses Playwright's built-in `toHaveScreenshot` if Argos isn't configured.
6. **Reviewer persona pass** — Claude reads `.claude/design-qa/reviewer.json` (strictness, brand voice rules, page-type priorities) and applies your team's design principles to the screenshots.

Output: Markdown summary (for PR comments), JSON (for CI gates), and HTML (for human review).

## Stack

- **Browser driver:** Microsoft Playwright MCP (default) or Vercel `agent-browser` CLI (for token-efficient long loops + real Mobile Safari via iOS Simulator).
- **a11y:** [@axe-core/playwright](https://www.npmjs.com/package/@axe-core/playwright) + Pa11y for second opinion.
- **Perf:** [`playwright-lighthouse`](https://www.npmjs.com/package/playwright-lighthouse).
- **Visual regression:** Argos (default) or Playwright `toHaveScreenshot` fallback.
- **Auth:** Templates for Clerk, Auth.js / NextAuth, Supabase Auth, custom API, custom UI flows. Storage state pattern.
- **Vercel:** Auto-uses `VERCEL_AUTOMATION_BYPASS_SECRET` from plugin userConfig.

## Install

```bash
/plugin marketplace add stacks-inc/claude-code-skills
/plugin install design-qa@stacks-inc-skills
```

You'll be prompted for:
- Vercel bypass secret (optional; only if previews are protected)
- Argos token (optional)
- Browser driver, breakpoint preset, auth strategy

## Commands

| Command | Description |
|---|---|
| `/design-qa:setup` | One-time per machine. Installs Playwright browsers + axe + lighthouse + pa11y. |
| `/design-qa:auth-init` | Bootstraps auth setup file based on chosen strategy. Adds `playwright/.auth/` to `.gitignore`. |
| `/design-qa:review <url>` | Full review pass. Generates markdown/json/html reports under `.claude/design-qa/reports/<timestamp>/`. |
| `/design-qa:responsive-sweep <url>` | Just the breakpoint screenshot matrix. |
| `/design-qa:a11y <url>` | Just the axe + pa11y audit. |
| `/design-qa:perf <url>` | Just Lighthouse / Core Web Vitals. |
| `/design-qa:seo <url>` | Just SEO/OG/JSON-LD checks. |
| `/design-qa:visual-baseline <url>` | Capture/update Argos baseline. |

## Breakpoints

Default `agency-default` preset (18 widths, includes "grey area" widths where designs commonly break):

```
280, 320, 360, 375, 390, 414, 480, 600, 700, 768,
834, 900, 1024, 1180, 1280, 1440, 1920, 2560
```

Plus light/dark theme + reduced-motion variants.

`fast` = `[375, 768, 1024, 1440, 1920]`.

`thorough` = agency-default + `[3840, 384, 844x390 landscape, print media]`.

## Reviewer persona

Drop a `.claude/design-qa/reviewer.json` at project root:

```json
{
  "strictness": "balanced",
  "brand": {
    "name": "Acme",
    "voice": ["clear", "warm", "no jargon"],
    "tokens": {
      "spacing": [4, 8, 12, 16, 24, 32, 48, 64],
      "radius": [4, 8, 12, 16],
      "fontFamilies": ["Inter", "Geist"]
    }
  },
  "pageTypePriorities": {
    "marketing": ["typography", "hero clarity", "CTA hierarchy"],
    "product": ["accessibility", "interaction states", "error handling"],
    "checkout": ["accessibility", "error states", "performance"]
  },
  "excludeRules": ["color-contrast-enhanced"]
}
```

The reviewer-persona skill loads this file at every review run and shapes Claude's analysis.

## Output

Every run writes to `.claude/design-qa/reports/<ISO-timestamp>/`:

- `summary.md` — paste-into-PR markdown
- `report.json` — for CI gates
- `report.html` — open in browser for screenshots + diffs
- `screenshots/` — full PNG matrix
- `axe/` — per-breakpoint axe JSON
- `lighthouse/` — Lighthouse JSON + HTML
- `argos-build-id.txt` — if uploaded

## Hooks

A PostToolUse hook on `mcp__playwright__browser_take_screenshot` automatically runs axe-core against the current DOM and stores the result alongside the screenshot. This means every screenshot you take during ad-hoc inspection (not just during `/design-qa:review`) gets a free a11y scan.

Disable with `"hooks": false` in `.claude/design-qa/reviewer.json`.

## Authentication

When `authStrategy` is set to anything other than `none`, run `/design-qa:auth-init` once per project. It will:

1. Copy the right auth setup template into `playwright/auth.setup.ts`.
2. Add `playwright/.auth/` to `.gitignore` if not already there.
3. Prompt for credentials and store them via `userConfig` (sensitive, never echoed back to the agent).
4. Document the auth flow for the agent in `.claude/design-qa/auth-notes.md`.

The agent NEVER:
- Commits storage state files.
- Echoes credentials in chat.
- Uses production accounts (warns if email looks production-shaped).

## Risks & known issues

- **Plugin format is young (shipped late 2025).** Pin Claude Code to a tested version. If `/plugin install` fails, see [Troubleshooting](#troubleshooting).
- **Token cost.** A full `agency-default` run can hit 50–100MB of screenshots and many context tokens. Default settings cap matrix to 3 hero pages × 18 widths × 2 themes. Tune via `reviewer.json`.
- **Headless Chromium ≠ Mobile Safari.** Set `browserDriver: "agent-browser"` and pass `--ios` flag for real iOS Simulator runs (macOS+Xcode required).
- **OS-dependent screenshot diffs.** Argos handles this; Playwright's `toHaveScreenshot` does not. Prefer Argos for team baselines.

## Troubleshooting

See `plugins/design-qa/TROUBLESHOOTING.md` once you hit something.
