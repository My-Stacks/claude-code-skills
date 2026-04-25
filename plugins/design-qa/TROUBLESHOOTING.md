# Troubleshooting

## Plugin install

### `/plugin install design-qa@stacks-inc-skills` fails

1. Verify the marketplace is added: `/plugin marketplace list`. You should see `stacks-inc-skills`. If not: `/plugin marketplace add stacks-inc/claude-code-skills`.
2. Check Claude Code version. Plugin format requires a recent build. Update via your install method (Homebrew, official installer, npm).
3. If the marketplace is on GitHub but the repo is private, you need to authenticate. Use a local path instead during dev: `/plugin marketplace add /path/to/your/clone/of/claude-code-skills`.

### After install, `/design-qa:review` is not a recognized command

1. Run `/plugin` and check that `design-qa` shows as enabled. If not: `/plugin enable design-qa@stacks-inc-skills`.
2. Restart Claude Code (`Cmd-Q`, reopen).
3. Verify the plugin manifest is valid JSON: `cat plugins/design-qa/.claude-plugin/plugin.json | jq .`. If it errors, the plugin won't load.

## Playwright MCP

### Playwright MCP server isn't registering

1. Check the plugin's `mcpServers` block in `plugin.json`. The user_config interpolation only works when the field is set.
2. Manually test: `npx -y @playwright/mcp@latest --headless --isolated`. If this fails, npx itself or your Node version is the issue. Plugin requires Node ≥ 20.
3. Run `/mcp` in Claude Code. You should see `playwright` in the list. If status is "failed," click for the error.

### Tools like `mcp__playwright__browser_navigate` not available

The agent's `tools:` frontmatter must include `mcp__playwright__*`. The `design-reviewer.md` agent already does. If you forked the agent, double-check the tools list.

## Browser & headless issues

### Chromium fails to launch on Linux

Run `npx playwright install --with-deps chromium`. The `--with-deps` flag installs system libraries.

### Screenshots are blank or partial

1. Add `await page.waitForLoadState('networkidle')` before screenshot.
2. Add `await page.evaluate(() => document.fonts.ready)`.
3. For SPA apps that lazy-load content on scroll, scroll to bottom first: `await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight))`.

### Screenshots have flaky animations / timestamps

The breakpoint-sweep script already injects animation-disable CSS. For dynamic regions (timestamps, user counters, ads), add a `data-dynamic` attribute and Argos will mask them.

## Vercel preview deploys

### URL returns 401 / "Authentication required"

1. The preview is protected. Set `userConfig.vercelBypassSecret` to a Protection Bypass for Automation secret from Vercel project settings.
2. Verify the secret works using the header form (avoids putting the secret in shell history, server logs, or referer headers): `curl -I -H "x-vercel-protection-bypass: <secret>" -H "x-vercel-set-bypass-cookie: true" "https://preview.vercel.app/"` should return 200, not 401. Avoid the `?x-vercel-protection-bypass=...` query-string form — it leaks the secret into logs and reports.
3. The bypass secret rotates if you regenerate it. Keep the userConfig in sync.

### Bypass works in browser but not in Playwright

Playwright uses headers, not URL params, for protection bypass. The plugin handles this — but if you're calling Playwright directly, you need both the header AND `x-vercel-set-bypass-cookie: true` to persist.

## Auth

### `auth.setup.ts` runs but storageState is empty

1. Check that the login actually succeeded. Add `await page.screenshot({ path: 'debug-after-login.png' })` after the click and inspect.
2. The session cookie may be on a different domain than the one Playwright stored. Verify `await page.context().cookies()` shows the expected cookie.
3. For Supabase: the session is in `localStorage`, not cookies. The supabase template handles this. If you wrote a custom template, ensure `storageState` includes localStorage by setting `runtimeOptions.captureLocalStorage: true`.

### "Cannot find storageState file"

1. Run `/design-qa:auth-init` once to create the setup file.
2. Run `npx playwright test --project=setup` to execute the auth setup.
3. Verify `playwright/.auth/user.json` exists. If not, the setup test failed silently — run with `--reporter=list` to see errors.

### Storage state expires

Tokens expire. For long-running CI, refresh storageState before each test run. For local development, just re-run setup when you hit a 401.

## Lighthouse

### Lighthouse fails with "No usable URL"

The URL must include a protocol (`https://`). Lighthouse can't follow redirects from `http://` to `https://` in some configurations. Use the canonical URL.

### Lighthouse INP is null

INP requires user interactions to measure. Lighthouse synthetic runs can't capture INP unless you script interactions via the puppeteer integration. The plugin reports `null` rather than fabricate a number.

### Lighthouse perf score is wildly different from web.dev/measure

Lighthouse desktop profile uses no throttling. Mobile uses Slow 4G + 4× CPU slowdown. web.dev/measure uses the same defaults but may have different network conditions on the runner. For consistency, always compare same-profile-to-same-profile.

## axe-core

### axe finds 0 violations but the site is obviously broken

axe scans the rendered DOM at the moment of scan. If the site renders client-side and you're scanning before hydration, axe sees nothing. The script waits for `networkidle` first, but for apps with delayed hydration, add a longer `waitForTimeout` or an `expect(...).toBeVisible()` for a known-late element.

### axe reports color-contrast issues that look fine visually

axe respects `prefers-color-scheme`. If you're scanning in dark mode and the site renders dark-mode styles correctly, the issue is real. Check the reported color values against your design tokens.

## Argos

### `argos upload` says "no token"

Set the token via plugin userConfig (`argosToken`) or env var `ARGOS_TOKEN`. The plugin maps userConfig to env vars when it shells out.

### Argos build never completes

1. Check the Argos dashboard. Build may have failed (e.g., screenshot count mismatch with reference build).
2. The first build on a branch becomes the baseline. Subsequent builds compare. If your reference build doesn't exist yet on `main`, the first run on a feature branch will compare against an empty baseline → all screenshots flagged as new.
3. Fix: run `/design-qa:visual-baseline` on `main` first, approve in Argos UI, then run on feature branches.

## Performance / cost

### `/design-qa:review` takes 10+ minutes

The agency-default preset captures 18 widths × 3 themes = 54 screenshots, plus a11y at 6 viewports, plus 2 Lighthouse runs. That's the cost of thoroughness. Switch to `breakpointPreset: "fast"` for quick PR checks (5 widths × 1 theme = 5 screenshots).

### Token cost is high

The agent reads dozens of axe JSON files, screenshots, and Lighthouse reports. Token-saving options:
1. `breakpointPreset: "fast"`.
2. Run sub-commands (`/design-qa:a11y`) instead of full review when only one dimension matters.
3. Switch `browserDriver: "agent-browser"` — Vercel's CLI returns hashed/diffed views instead of raw screenshots, much cheaper context-wise.

## Hooks

### Screenshot-axe-hook never fires

1. Check `hooks/hooks.json` references the right tool name. Should be `mcp__playwright__browser_take_screenshot` exactly.
2. Verify the hook is enabled in plugin metadata: `"hooks": "./hooks/hooks.json"` in `plugin.json`. (Note: the current build registers hooks via the file's existence; future Claude Code versions may require explicit registration.)
3. Check `.claude/design-qa/reviewer.json` doesn't have `hooks: false`.

## Reporter output

### `summary.md` is empty or partial

A reporter only includes a section if the corresponding sub-report exists. If you ran `/design-qa:perf` only, the markdown will only have the Lighthouse section. Run the full `/design-qa:review` for the complete report.

### HTML report screenshots are broken

The HTML report uses relative paths (`screenshots/foo.png`). It must stay in the report directory. Don't move just the HTML.

## Still stuck

Open an issue at https://github.com/stacks-inc/claude-code-skills/issues with:
- The command you ran
- The error output
- Output of `node ${CLAUDE_PLUGIN_ROOT}/bin/verify.js`
- Your plugin userConfig (with secrets redacted)
