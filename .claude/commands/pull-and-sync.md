---
name: pull-and-sync
version: "1.0"
description: "Sync working branch with latest from default branch using merge --no-ff."
allowed-tools: Bash
---

# /pull-and-sync — Sync with Latest

## 1. Gather context

Run in parallel:

- `git branch --show-current` — current branch (`$BRANCH`)
- `git status --porcelain` — uncommitted changes
- `git remote get-url origin 2>/dev/null` — verify remote exists
- `git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@'` — default branch (`$DEFAULT`)
  - Fallback: `git rev-parse --abbrev-ref origin/HEAD 2>/dev/null`
  - Last resort: `git remote show origin | sed -n 's/.*HEAD branch: //p'`

**Stop conditions** (check in order):

- No `origin` remote: "No remote configured. Nothing to sync." Stop.
- `$DEFAULT` is empty after all attempts: "Cannot determine default branch." Stop.
- `$BRANCH` equals `$DEFAULT`: "You're on $DEFAULT. Just `git pull` instead." Stop.

## 2. Commit uncommitted changes

If `git status --porcelain` shows changes:

- Stage and commit using conventional commit format
- Show staged files + commit message, wait for approval
- Never `git add -A` — stage specific files by name
- Skip `.env*`, `*.pem`, `*.key`, `*.p12`, credentials, tokens, private keys, secrets
- If user declines the commit, stop: "Working tree is dirty. Commit or stash changes before syncing."

If no changes: skip to Step 3.

## 3. Sync default branch

Record pre-sync state: `BEFORE=$(git rev-parse "$DEFAULT")`

```bash
git checkout "$DEFAULT"
git pull --ff-only origin "$DEFAULT"
```

If `--ff-only` fails (local default has diverged): report the divergence and stop. Do not force pull or merge on the default branch.

If pull fails for any other reason: report the error and stop.

## 4. Merge into working branch

```bash
git checkout "$BRANCH"
git merge --no-ff --no-edit "$DEFAULT"
```

If merge conflicts: report them. Do not auto-resolve. Let the user handle it.

## 5. Report

```
## Sync Complete

**Branch:** $BRANCH
**Merged:** $DEFAULT (N new commits)
**Status:** Ready to work
```

Compute N and show new commits using `$BEFORE` from Step 3 (limit 10):

```bash
git log --oneline -10 "$BEFORE".."$DEFAULT"
```

Omit sections with nothing to report.

## Safety Rules

- Never force pull, force push, or `reset --hard`
- Never delete branches
- `merge --no-ff` only — no rebasing
- `--ff-only` when pulling default branch — no surprise merge commits
- If merge conflicts: report and stop, let user resolve
