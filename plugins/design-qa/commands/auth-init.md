---
description: Bootstrap authentication for design QA. Copies the right Playwright auth setup template into the project, gitignores the storage-state directory, and prompts for credentials.
allowed-tools: Bash, Read, Write, Edit, Glob
---

Bootstrap auth for design-qa runs.

Steps:

1. **Detect or confirm strategy.** Check `${user_config.authStrategy}`. If it's `none`, ask the user which strategy they want (clerk, auth-js, supabase, custom-api, custom-ui) and instruct them to update plugin config.
2. **Copy the template.** From `${CLAUDE_PLUGIN_ROOT}/scripts/auth-strategies/<strategy>.setup.ts` into the project at `playwright/auth.setup.ts`. If a file already exists at that path, ask before overwriting and offer to back it up to `playwright/auth.setup.ts.bak`.
3. **Gitignore.** Add `playwright/.auth/` and `playwright/.auth/*` to the project's `.gitignore` if not already present. Also add `*.storage-state.json`.
4. **Verify.** Confirm the template references `${user_config.*}` for credentials, NOT hardcoded values. If the user pastes credentials in chat, refuse and instruct them to set the relevant `userConfig` fields.
5. **Document.** Write `.claude/design-qa/auth-notes.md` describing the chosen flow, the `userConfig` keys it relies on, and a one-line reminder for the agent ("Auth runs as a Playwright setup project before any design-qa command. Storage state lives in `playwright/.auth/user.json` (gitignored)."

Hard rules:
- NEVER commit a `storageState` file. NEVER echo credentials in chat. NEVER assume "production" credentials should be used — warn loudly if the email looks production-shaped.
- If the strategy is `clerk`, also instruct the user to enable a test instance and create a test user with username/password auth (Clerk OAuth flows can't be automated).
- If the strategy is `custom-ui`, write a stub the user must complete with their app's actual login selectors. Do not try to autodetect them.

End by printing a "Next steps" block: which env vars to set, how to run a dry-run, and how to verify the storage state was captured.
