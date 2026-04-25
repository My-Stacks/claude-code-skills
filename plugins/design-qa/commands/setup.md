---
description: One-time-per-machine setup. Installs Playwright browsers, axe-core, Lighthouse, Pa11y, and (if configured) agent-browser.
allowed-tools: Bash, Read, Write
---

Run the install script: `bash ${CLAUDE_PLUGIN_ROOT}/bin/install.sh`.

The script:
1. Installs Playwright Chromium + dependencies (`npx playwright install --with-deps chromium`).
2. Installs `@axe-core/playwright`, `axe-core`, `pa11y`, `playwright-lighthouse`, and `lighthouse` as dev dependencies in the current project (or globally if no `package.json` is present).
3. If `${user_config.browserDriver}` is `agent-browser`, installs the Vercel `agent-browser` CLI and runs `agent-browser install`.
4. If `${user_config.argosToken}` is set, installs `@argos-ci/playwright`.
5. Verifies all binaries are on PATH.

Report what was installed and any failures. If the project has no `package.json`, ask the user whether to install globally or to initialize a `package.json` in the design-qa report dir.

After install: run `node ${CLAUDE_PLUGIN_ROOT}/bin/verify.js` and report the result.
