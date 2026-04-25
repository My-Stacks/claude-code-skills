---
description: Capture or update the visual regression baseline. Uses Argos if configured, otherwise Playwright's toHaveScreenshot baselines.
argument-hint: <url>
allowed-tools: Bash, Read, Write, mcp__playwright__*
---

Capture/update visual regression baseline against `$1`.

1. If `${user_config.argosToken}` is set:
   - Run `bash ${CLAUDE_PLUGIN_ROOT}/bin/run-argos-baseline.sh "$1"`. The script captures the breakpoint matrix and uploads to Argos as a "reference" build (which becomes the baseline).
   - Print the Argos build URL.
2. Otherwise:
   - Run `bash ${CLAUDE_PLUGIN_ROOT}/bin/run-playwright-baseline.sh "$1"`. The script uses Playwright's built-in `toHaveScreenshot` and writes baselines to `__screenshots__/` with one subfolder per breakpoint.
   - Add the baseline directory to git unless `.gitignore` already excludes it.
3. Confirm the baseline file count matches the breakpoint matrix size.
4. Document: any future `/design-qa:review` will compare against this baseline.

If baselines already exist:
- If using Argos: tell the user to mark the latest review build as "approved" in the Argos UI to update the baseline.
- If using Playwright: ask before overwriting. Offer `--update-snapshots=missing` (safe) vs `--update-snapshots` (overwrite all).

NEVER overwrite Playwright baselines without explicit user confirmation.
