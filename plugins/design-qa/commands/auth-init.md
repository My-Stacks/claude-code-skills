---
description: Bootstrap authentication for design QA. Copies the right Playwright auth setup template into the project, gitignores the storage-state directory, and prompts for credentials.
allowed-tools: Bash, Read, Write, Edit, Glob
---

Bootstrap auth for design-qa runs.

Steps:

1. **Detect or confirm strategy.** Check `${user_config.authStrategy}`. If it's `none`, ask the user which strategy they want (clerk, auth-js, supabase, custom-api, custom-ui) and instruct them to update plugin config.
2. **Copy the template.** From `${CLAUDE_PLUGIN_ROOT}/scripts/auth-strategies/<strategy>.setup.ts` into the project at `playwright/auth.setup.ts`. If a file already exists at that path, ask before overwriting and offer to back it up to `playwright/auth.setup.ts.bak`.
3. **Gitignore.** Add `playwright/.auth/` and `playwright/.auth/*` to the project's `.gitignore` if not already present. Also add `*.storage-state.json`.
4. **Verify.** Confirm the template reads credentials from environment variables (`DESIGN_QA_TEST_EMAIL`, `DESIGN_QA_TEST_PASSWORD`, `DESIGN_QA_BASE_URL`, plus strategy-specific vars like `DESIGN_QA_SUPABASE_URL`/`DESIGN_QA_SUPABASE_ANON_KEY` for Supabase or `CLERK_PUBLISHABLE_KEY`/`CLERK_SECRET_KEY` for Clerk), NOT from hardcoded values. If the user pastes credentials in chat, refuse and instruct them to export those env vars before running design-qa, or to put them in a `.env.local` that the user's tooling loads (do not commit it). Note: `userConfig` is for non-secret plugin configuration (browser driver, breakpoint preset, auth strategy choice) — the test-account credentials live in env vars so the auth setup script can read them at Playwright runtime.
5. **Document.** Write `.claude/design-qa/auth-notes.md` describing the chosen flow and the env vars it reads. Include a one-line reminder for the agent that, **in v0.1**, the design-qa runner scripts (`run-axe.sh`, `run-lighthouse.sh`, `run-seo.sh`, `run-sweep.sh`, etc.) do **not** yet read the generated storage state — they hit the URL anonymously. The auth setup file is wired into a project's `playwright.config.ts` so it runs ahead of *Playwright* tests, but the headless-runner scripts that drive Lighthouse/axe directly bypass it. This is a known v0.1 gap; a `--auth` flag / `DESIGN_QA_STORAGE_STATE` consumer per runner is on the follow-up list.

Hard rules:
- NEVER commit a `storageState` file. NEVER echo credentials in chat. NEVER assume "production" credentials should be used — warn loudly if the email looks production-shaped.
- If the strategy is `clerk`, also instruct the user to enable a test instance and create a test user with username/password auth (Clerk OAuth flows can't be automated).
- If the strategy is `custom-ui`, write a stub the user must complete with their app's actual login selectors. Do not try to autodetect them.

End by printing a "Next steps" block: which env vars to set, how to run a dry-run, and how to verify the storage state was captured.
