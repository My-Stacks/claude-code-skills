---
name: pull-and-sync
version: "1.0"
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

On first user message, run in parallel:

```bash
git fetch --all --quiet 2>/dev/null
```
```bash
git status -sb 2>/dev/null
```
```bash
git rev-list --count HEAD..@{upstream} 2>/dev/null
```

Then:

- **Not a git repo or no remote:** skip silently, proceed with the session.
- **Up to date:** report once: "Repo is up to date with remote." Move on.
- **Behind remote by N commits:** warn: "Your branch is **N commits behind** remote. Run `/pull-and-sync` to sync before starting work."
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

### 2. Stash if needed

If `git status --porcelain` shows changes:

```bash
git stash push -m "pull-and-sync auto-stash"
```

Record that a stash was made for Step 5.

### 3. Determine topology

- Current branch: `$BRANCH`
- Default branch: `git remote show origin | sed -n 's/.*HEAD branch: //p'` (usually `main`)
- Is `$BRANCH` the default branch?

### 4. Sync

#### 4A. On default branch (main/master)

Check how far behind:

```bash
git log HEAD..origin/main --oneline
```

- **Behind:** `git pull --ff-only origin main`
- **ff-only fails (diverged):** show the divergence. Ask user: "Local main has diverged from remote. Rebase onto remote?" Only run `git pull --rebase origin main` with consent.
- **Up to date:** report and continue.

#### 4B. On a feature branch

**Sync default branch without switching:**

```bash
git fetch origin main:main
```

If this fails (local main has divergent commits), warn: "Local main has commits not on remote. Switch to main and resolve before syncing." Continue with feature branch sync.

**Sync feature branch from remote:**

```bash
git log HEAD..origin/$BRANCH --oneline 2>/dev/null
```

- If no remote tracking branch: note "No remote tracking for $BRANCH." Skip.
- If behind: `git pull --ff-only origin $BRANCH`
- If ff-only fails: show divergence. Ask: "Feature branch has diverged from remote. Rebase onto remote?" Only `git pull --rebase origin $BRANCH` with consent.

**Check if behind updated main:**

```bash
git log HEAD..main --oneline
```

If behind main, offer: "Your branch is N commits behind main. Rebase onto main?" Only `git rebase main` with consent. Explain: this replays your branch's commits on top of the latest main.

### 5. Restore stash

If a stash was made in Step 2:

```bash
git stash pop
```

If pop conflicts: leave stash intact (`git stash list` still shows it). Warn: "Stash conflicts with pulled changes. Your work is safe in the stash — resolve with `git stash pop` after fixing conflicts."

### 6. Report

```
## Sync Complete

**Branch:** feature/my-thing
**Remote:** up to date with origin/feature/my-thing
**Main:** synced (3 new commits pulled)
**Stash:** restored cleanly
**Status:** Ready to work
```

If new commits were pulled, show them (limit 10):

```bash
git log --oneline -10 ORIG_HEAD..HEAD
```

Omit sections with nothing to report.

---

## Safety Rules

- Never force pull, force push, or `reset --hard`.
- Never delete branches.
- Always stash before pulling. Always restore after.
- `--ff-only` by default. Rebase only with user consent.
- If rebase has conflicts: `git rebase --abort`, restore stash, tell user to resolve manually.
- If `git stash pop` conflicts: leave stash in place, explain how to resolve.
- Show what changed before taking any action.
