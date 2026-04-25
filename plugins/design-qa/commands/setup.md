---
description: One-time-per-machine setup. Installs Playwright browsers, axe-core, Lighthouse, Pa11y, and (if configured) agent-browser.
allowed-tools: Bash, Read, Write
---

Run the install script: `bash ${CLAUDE_PLUGIN_ROOT}/bin/install.sh`.

The script:
1. Detects the project's package manager. Honors `package.json#packageManager` (Corepack standard) when present, otherwise sniffs lockfiles (`pnpm-lock.yaml`, `yarn.lock`, `bun.lock(b)`), and finally falls back to `npm`. With no `package.json`, packages are installed globally.
2. Installs Playwright Chromium + system dependencies (`npx playwright install --with-deps chromium`).
3. Installs `@axe-core/playwright`, `axe-core`, `pa11y`, `playwright-lighthouse`, `lighthouse`, and `chrome-launcher` as dev dependencies in the current project (or globally if no `package.json` is present).
4. If `${user_config.browserDriver}` is `agent-browser`, installs the Vercel `agent-browser` CLI pinned to `${DESIGN_QA_AGENT_BROWSER_VERSION}` (default `latest`) with `--ignore-scripts` to limit supply-chain blast radius, then runs `agent-browser install` explicitly.
5. If `${user_config.argosToken}` is set (or `DESIGN_QA_ARGOS_TOKEN` is exported), installs both `@argos-ci/playwright` and `@argos-ci/cli`.

Report what was installed and any failures. If the project has no `package.json`, the script installs globally with no prompt — call this out in your report so the user knows to initialize a project if they prefer scoped installs.

After install: run `node ${CLAUDE_PLUGIN_ROOT}/bin/verify.js` and report the result.
