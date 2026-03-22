---
name: pull-and-sync
version: "1.0"
description: "Sync working branch with latest from default branch using merge --no-ff."
allowed-tools: Bash
---

# /pull-and-sync — Sync with Latest

## 1. Gather context

- `git branch --show-current` — current branch (`$BRANCH`)
- `git status --porcelain` — uncommitted changes
- `git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@'` — default branch (`$DEFAULT`). Fallback: `git remote show origin | sed -n 's/.*HEAD branch: //p'`

If `$DEFAULT` is empty or on the default branch already, stop and tell the user.

## 2. Commit uncommitted changes

If `git status --porcelain` shows changes, commit them. If no changes, skip to Step 3.

## 3. Sync default branch

```bash
BEFORE=$(git rev-parse "$DEFAULT")
git checkout "$DEFAULT"
git pull --ff-only origin "$DEFAULT"
```

If pull fails, report and stop.

## 4. Merge into working branch

```bash
git checkout "$BRANCH"
git merge --no-ff --no-edit "$DEFAULT"
```

If merge conflicts, report and stop. Let the user resolve.

## 5. Report

Show what was pulled — `git log --oneline -10 "$BEFORE".."$DEFAULT"`. If nothing new, say so.
