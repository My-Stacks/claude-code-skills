---
name: pull-and-sync
version: "1.1"
description: "Sync local repo with remote before starting work."
trigger: /pull-and-sync
---

## Version Check
To check for updates: `curl -s https://raw.githubusercontent.com/My-Stacks/claude-code-skills/main/versions.yaml`
Compare against this file's version in frontmatter.

# Pull & Sync

Get the house in order before a work session. Fetches from remote, syncs branches, detects conflicts, reports what changed.

## Session Start Behavior

This is behavioral — follow these instructions at the start of every new session when this skill is loaded.

On first user message, fetch first, then check status:

```bash
git fetch --all --quiet 2>/dev/null
```

Then in parallel:

```bash
git status -sb 2>/dev/null
```
```bash
git rev-list --count HEAD..@{upstream} 2>/dev/null
```
```bash
git rev-list --count @{upstream}..HEAD 2>/dev/null
```

Then:

- **Not a git repo, no remote, or no upstream tracking branch:** skip silently, proceed with the session.
- **Detached HEAD** (`git branch --show-current` returns empty): skip silently.
- **Up to date:** report once: "Repo is up to date with remote." Move on.
- **Behind remote by N commits:** warn: "Your branch is **N commits behind** remote. Run `/pull-and-sync` to sync before starting work."
- **Ahead by N commits:** report: "Your branch is **N commits ahead** of remote."
- **Diverged (local and remote both have commits):** warn: "Your branch has **diverged** from remote (N local, M remote commits). Run `/pull-and-sync` to resolve before starting work."

Keep it to 1-2 lines. Do not block the session — the user can choose to sync or continue.

---

## `/pull-and-sync` — Full Sync

### 1. Gather context

Run in parallel:

- `git branch --show-current` — current branch
- `git remote -v` — configured remotes
- `git status --porcelain` — uncommitted changes
- `git fetch --all --prune` — fetch everything, clean stale refs
- `git rev-parse --abbrev-ref @{upstream} 2>/dev/null` — tracking branch

If no remotes configured: "No remote configured. Nothing to sync." Stop.

If `git branch --show-current` returns empty (detached HEAD): "Detached HEAD — checkout a branch first." Stop.

### 2. Stash if needed

If `git status --porcelain` shows changes:

```bash
git stash push -m "pull-and-sync auto-stash"
```

Record that a stash was made for Step 5.

### 3. Determine topology

- Current branch: `$BRANCH`
- Default branch: `git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@'` → `$DEFAULT`
  - Fallback if ref not set: `git remote show origin | sed -n 's/.*HEAD branch: //p'`
- Is `$BRANCH` equal to `$DEFAULT`?

### 4. Sync

Before any sync operation, capture the current HEAD for later reporting:

```bash
BEFORE=$(git rev-parse HEAD)
```

#### 4A. On default branch

Check how far behind:

```bash
git log HEAD.."origin/$DEFAULT" --oneline
```

- **Behind:** `git pull --ff-only origin "$DEFAULT"`
- **ff-only fails (diverged):** show the divergence. Ask user: "Local $DEFAULT has diverged from remote. Rebase onto remote?" Only run `git pull --rebase origin "$DEFAULT"` with consent.
- **Up to date:** report and continue.

#### 4B. On a feature branch

**Sync feature branch from remote:**

```bash
git log HEAD.."origin/$BRANCH" --oneline 2>/dev/null
```

- If no remote tracking branch: note "No remote tracking for $BRANCH." Skip.
- If behind: `git pull --ff-only origin "$BRANCH"`
- If ff-only fails: show divergence. Ask: "Feature branch has diverged from remote. Rebase onto remote?" Only `git pull --rebase origin "$BRANCH"` with consent.

**Check if behind remote default branch:**

```bash
git log HEAD.."origin/$DEFAULT" --oneline
```

If behind, offer: "Your branch is N commits behind $DEFAULT. Rebase onto origin/$DEFAULT?" Only `git rebase "origin/$DEFAULT"` with consent. Explain: this replays your branch's commits on top of the latest $DEFAULT.

### 5. Restore stash

If a stash was made in Step 2:

```bash
git stash apply
```

If apply succeeds, drop the stash explicitly:

```bash
git stash drop
```

If apply conflicts: leave stash in place (verify with `git stash list`). Warn: "Stash conflicts with pulled changes. Your work is safe in the stash — resolve with `git stash pop` after fixing conflicts."

### 6. Report

```
## Sync Complete

**Branch:** $BRANCH
**Remote:** up to date with origin/$BRANCH
**Default branch:** synced (3 new commits on origin/$DEFAULT)
**Stash:** restored cleanly
**Status:** Ready to work
```

If new commits were pulled, show them using `$BEFORE` captured in Step 4 (limit 10):

```bash
git log --oneline -10 $BEFORE..HEAD
```

Omit sections with nothing to report.

---

## Safety Rules

- Never force pull, force push, or `reset --hard`.
- Never delete branches.
- Always stash uncommitted changes before pulling. Always restore after.
- `--ff-only` by default. Rebase only with user consent.
- If rebase has conflicts: run `git rebase --abort` (branch returns to pre-rebase HEAD; any prior ff-pull remains). Then attempt stash restore. If stash restore also conflicts, leave stash in place and report both issues clearly.
- If `git stash apply` conflicts: leave stash in place, explain how to resolve.
- Show what changed before taking any action.
