---
name: verify
description: Prove a change works before calling it done or opening/updating a PR in a Stacklist repo. Runs the repo's safe Verify command from the Stacklist repo registry and, for visual frontend changes, captures desktop + phone screenshots next to the reference. Use before every "done", "ready" or PR in My-Stacks repos, and in every bot/routine run.
argument-hint: "[reference: figma url or component name]"
---

# Verify

Reference for visual changes (optional): `$ARGUMENTS`

## 1. Find this repo's entry

- Repo slug: `git remote get-url origin` → `My-Stacks/<name>`.
- Registry: `${CLAUDE_PLUGIN_ROOT}/registry/repos.yaml`. In a cloud routine without the plugin installed, it is `plugins/stacklist-dev/registry/repos.yaml` in the cloned `My-Stacks/claude-code-skills`. Read the entry under `repos.<name>`.
- No entry → report `VERIFY: none (repo not in registry)` and stop. Never invent a command.

## 2. Run the Verify command

- Run the entry's `verify` exactly as written, from the repo root (or the worktree root you are working in). Capture the exit code; don't eyeball output.
- `verify: null` → report `VERIFY: none` with the entry's comment. The change needs a human.
- Never substitute a broader command (integration/e2e suites, `npm test` where the registry says otherwise, deploy, migrate). The registry's command is the safe one; others in the repo may write to a real DB or call paid APIs.
- Fails → read the failure, fix it if it is caused by your change, rerun once. Still failing, or failing on code you didn't touch → stop and report it.

## 3. Visual check (frontend only)

Only when the entry's `area` is `fe` or `mobile` and the diff changes rendered UI (components, styles, layout, copy):

- Get the rendered result: the PR's Vercel preview URL if a PR exists (`gh pr checks` lists it), else the local dev server if one is already running. Don't start a second dev server; check with `pgrep -fl` first.
- Screenshot the affected route at desktop (1440 px) and phone (390 px) widths with the browser tools you have (Playwright or Chrome).
- Put each next to the reference (Figma frame via the Figma tools, or the named existing component) and list the visible differences. "Looks fine" is not a finding.
- No reference given → still capture both screenshots and say there was no reference.

## 4. Report

```
VERIFY: pass | fail | none
command: <the command>   exit: <code>
<on fail: the last ~30 relevant lines>
UI: <screenshot paths + differences vs reference> | not applicable
```

`VERIFY: pass` plus (for UI) screenshots with no unexplained differences is the only state in which you may call the work done or the PR ready. In a bot/routine run, anything else means: don't open the PR, label the issue `needs-human`, and post what you tried.
