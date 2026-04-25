---
description: One-time-per-machine setup. Installs Playwright browsers, axe-core, and (in the full tier) Lighthouse + Pa11y.
allowed-tools: Bash, Read, Write
---

Run the install script: `bash ${CLAUDE_PLUGIN_ROOT}/bin/install.sh`.

## Tiers

The install ships in two tiers, controlled by `DESIGN_QA_INSTALL_TIER`:

- **`minimum`** — Playwright + `@axe-core/playwright` + `axe-core` only. Use this when you only need responsive sweeps + accessibility passes and want to avoid the ~180-package transitive footprint Lighthouse brings.
- **`full`** (default) — minimum + `lighthouse` + `chrome-launcher` + `pa11y`. Required for `/design-qa:perf` and the full audit pipeline.

To install the minimum tier:

```bash
DESIGN_QA_INSTALL_TIER=minimum bash ${CLAUDE_PLUGIN_ROOT}/bin/install.sh
```

## What the script does

1. Detects the project's package manager. Honors `package.json#packageManager` (Corepack standard) when present, otherwise sniffs lockfiles (`pnpm-lock.yaml`, `yarn.lock`, `bun.lock(b)`), and finally falls back to `npm`. With no `package.json`, packages are installed globally.
2. Installs Playwright Chromium + system dependencies (`npx playwright install --with-deps chromium`).
3. Installs `@axe-core/playwright` and `axe-core` as dev dependencies.
4. **Full tier only:** Installs `lighthouse` and `chrome-launcher` (drives Lighthouse directly — `playwright-lighthouse` is NOT installed; the plugin avoids it because of a `wsEndpoint` foot-gun in current Playwright). Also installs `pa11y`.
5. If `${user_config.browserDriver}` is `agent-browser`, installs the `agent-browser` CLI pinned to `${DESIGN_QA_AGENT_BROWSER_VERSION}` (default `latest`) with `--ignore-scripts` to limit supply-chain blast radius, then runs `agent-browser install` explicitly. *Note: agent-browser is currently a config slot only — the plugin runners use Playwright regardless.*
6. If `${user_config.argosToken}` is set (or `DESIGN_QA_ARGOS_TOKEN` is exported), installs both `@argos-ci/playwright` and `@argos-ci/cli`.

Report what was installed and any failures. If the project has no `package.json`, the script installs globally with no prompt — call this out so the user knows to initialize a project if they prefer scoped installs.

## npm audit noise

The full tier surfaces ~50 transitive advisories from Lighthouse's deep dependency chain (Puppeteer, deprecated middleware, etc.). These are dev-time tools — none ship to runtime — but the noise is real. If a security scanner gates CI on `npm audit`, scope the audit to production dependencies only:

```bash
npm audit --omit=dev
```

See `TROUBLESHOOTING.md` for context.

## After install

Run `node ${CLAUDE_PLUGIN_ROOT}/bin/verify.js` and report the result. Verify honors the same `DESIGN_QA_INSTALL_TIER` so it doesn't flag missing optional deps in the minimum tier.
