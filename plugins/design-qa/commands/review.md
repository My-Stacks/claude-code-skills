---
description: Run a full headless design QA review against a URL. Sweeps breakpoints, runs axe + Lighthouse + SEO checks, optionally uploads to Argos, and produces a structured report.
argument-hint: <url> [pages...]
allowed-tools: Task, Bash, Read, Write, mcp__playwright__*
---

Run the **design-reviewer** subagent against `$1` as the primary URL. Additional positional arguments are extra pages to review (e.g. `/dashboard`, `/pricing`).

Before invoking the agent:
1. Verify Playwright MCP is registered (`mcp__playwright__browser_navigate` exists). If not, instruct the user to run `/design-qa:setup`.
2. Verify the report directory `.claude/design-qa/reports/` is writable. Create it if missing.
3. Note the configured browser driver (`${user_config.browserDriver}`), breakpoint preset (`${user_config.breakpointPreset}`), and auth strategy (`${user_config.authStrategy}`).

Then dispatch:

> Use the `design-reviewer` subagent to review `$1`. Additional pages: `${@:2}`. Apply the configured reviewer persona at `${user_config.reviewerConfigPath}`. Driver: `${user_config.browserDriver}`. Preset: `${user_config.breakpointPreset}`. Auth: `${user_config.authStrategy}`. Argos upload: `${user_config.argosUploadOnReview}`. Write reports to `.claude/design-qa/reports/<timestamp>/`. After the review, paste the contents of `summary.md` into chat.
