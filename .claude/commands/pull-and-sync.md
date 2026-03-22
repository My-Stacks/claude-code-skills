---
name: pull-and-sync
version: "1.0"
description: "Sync working branch with latest from default branch using merge --no-ff."
allowed-tools: Bash, Read, Glob, Grep
---

# /pull-and-sync — Sync with Latest

## 1. Gather context

Run in parallel:

- `git branch --show-current` — current branch (`$BRANCH`)
- `git status --porcelain` — uncommitted changes
- `git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@'` — default branch (`$DEFAULT`)
  - Fallback: `git remote show origin | sed -n 's/.*HEAD branch: //p'`

If no remote configured: "No remote configured. Nothing to sync." Stop.
If on `$DEFAULT` branch: "You're on $DEFAULT. Just `git pull` instead." Stop.

## 2. Commit uncommitted changes

If `git status --porcelain` shows changes:

- Stage and commit using conventional commit format
- Show staged files + commit message, wait for approval
- Never `git add -A` — stage specific files by name
- Skip `.env`, credentials, tokens, private keys

If no changes: skip to Step 3.

## 3. Sync default branch

```bash
git checkout "$DEFAULT"
git pull origin "$DEFAULT"
```

If pull fails: report the error. Do not force pull. Stop.

## 4. Merge into working branch

```bash
git checkout "$BRANCH"
git merge --no-ff "$DEFAULT"
```

If merge conflicts: report them. Do not auto-resolve. Let the user handle it.

## 5. Report

```
## Sync Complete

**Branch:** $BRANCH
**Merged:** $DEFAULT (N new commits)
**Status:** Ready to work
```

Show new commits pulled into `$DEFAULT` (limit 10):

```bash
git log --oneline -10 "$BRANCH".."$DEFAULT"
```

Omit sections with nothing to report.

## Safety Rules

- Never force pull, force push, or `reset --hard`
- Never delete branches
- `merge --no-ff` only — no rebasing
- If merge conflicts: report and stop, let user resolve
