---
name: tidy
version: "1.0"
description: >-
  Repo cleanup pass that acts on what /preflight flagged. Builds one cleanup
  plan (unpushed branches, merged branches, finished worktrees, stale remote
  refs, docs and journal PRs), sorts every item into a safety tier, asks for
  approval once per tier instead of once per item, then executes and logs a
  recovery line for everything it removed. Merges only docs and journal PRs,
  only after their gates pass, only with an explicit yes in this run. Use when
  preflight's FLAGGED table is non-empty, or when Kyle says "clean that up",
  "tidy the repo", "land the journals", "clear out old branches or worktrees".
  Not for landing today's uncommitted work (that is /mise-en-place) and not
  for being lost mid-task (that is /housekeeping).
trigger: /tidy
allowed-tools: Bash, Read, Write
---

# tidy: Cleanup Pass With Tiered Approval

## What this skill is

/preflight observes and syncs. /mise-en-place lands the day's new work. Neither one clears out the leftovers: the journal branch that never got pushed, the worktree from a finished session, the branch whose PR merged two weeks ago. Today those sit in a FLAGGED table until Kyle says "you can clean all that up".

/tidy is that sentence, made into a process. It turns the flagged list into **one plan**, sorts each item by how reversible it is, gets approval **once per tier**, executes, and leaves a recovery log.

## Where it sits

| Skill | When | Writes |
|---|---|---|
| /preflight | start of session | fetch, fast-forward only, baseline file |
| **/tidy** | right after preflight when anything is flagged, or on request | pushes, PRs, docs/journal merges, branch and worktree removal, all tiered |
| /mise-en-place | end of day | commits and pushes this session's new work, never merges |
| /housekeeping | lost mid-task | nothing until approved line by line |

/preflight should end its verdict with one line when FLAGGED is non-empty: `N items flagged. Run /tidy to clear them.` It does not run /tidy itself.

**/tidy never creates new work.** It never commits, never edits files, never fixes something it finds. It only moves things that already exist: committed branches, open PRs, worktrees, refs.

## The test

> After /tidy runs, does the next /preflight come back with an empty FLAGGED table, or with only items that genuinely need Kyle's judgment?

If an action doesn't move toward that, skip it.

## Operating principles

1. **One plan, then one approval per tier.** Never ask item by item when a batch question will do. Never act on an item that wasn't in the plan Kyle saw.
2. **Reversibility decides the tier, not how scary it sounds.** Deleting a fully merged branch is recoverable from its recorded SHA. Pushing is not retractable. Merging is a decision.
3. **Re-derive, don't trust.** Never act on preflight's earlier output. Re-gather state at the start of the run and again immediately before each write.
4. **Record before removing.** Every branch deleted and worktree removed gets its SHA, path and a restore command written to the recovery log before the removal runs.
5. **Teach as it goes.** Same voice as /preflight: one plain sentence on why each item is in its tier. Kyle is learning git.
6. **Questions are rare and come with a default.** Max 3 per run, numbered, each with the proposed answer.

## Config

Extend the existing per-user preflight config at `~/.claude/preflight/<repo-key>.yml` (same key derivation as /preflight Step 3) with a `tidy:` block. Never write config into the repo.

```yaml
tidy:
  merge_eligible_prefixes: [docs]          # branch prefixes whose PRs /tidy may merge
  merge_path_allowlist:                    # every changed file must match one of these
    - "journal/**"
    - "docs/**"
    - "**/*.md"
  merge_path_blocklist:                    # any match disqualifies the PR from merging
    - "**/CLAUDE.md"
    - "**/AGENTS.md"
    - "agent.yaml"
    - "VERSION"
    - "CHANGELOG.md"
    - ".mcp.json"
    - ".env*"
    - ".github/**"
    - ".claude/**"                           # skills, agents, commands, hooks, settings: behavior, not docs
  merge_method: squash                     # squash | merge | rebase, match the repo's history
  review_gate: ai-router                   # ai-router | ci-only | human
  egress_check: true                       # flag client names before any external review
  stale_unpushed_days: 7                   # unpushed non-docs commits older than this get escalated
  stash_report_weeks: 8
```

If the block is missing on first run, write these defaults, show Kyle the file path, and continue. Blocklist always wins over allowlist. Patterns are gitignore-style globs matched against the repo-relative path; a pattern without `/` matches only at the root, so use `**/` to catch nested copies.

## The tiers

Every candidate item lands in exactly one tier. If an item doesn't clearly fit Tier 1 or 2, it goes to Tier 3 (report only).

### Tier 0: Just do it (narrated, no approval)

Local, read-only against others, or trivially reversible.

- `git fetch --prune --no-tags origin`
- Re-reading PR, CI and review status
- Writing the recovery log and run ledger under `~/.claude/tidy/`

### Tier 1: Batch approval (one yes covers the whole list)

Shown as a numbered list. Kyle answers `yes`, `yes except 3`, or `no`.

| Action | Preconditions (all must hold) |
|---|---|
| **Push an unpushed docs/journal branch** and set its upstream (`git push -u origin "$b"`) | prefix in `merge_eligible_prefixes`; no upstream or ahead-only; every commit's changed paths pass the allowlist and miss the blocklist; branch name not already on origin with different history |
| **Open a PR** for a branch just pushed | same branch as above; base is the default branch; title from the commit subject; body ends with the repo's attribution lines |
| **Delete a merged local branch** (`git update-ref -d "refs/heads/$b" "$sha"`, never `branch -D`) | `$sha` is the tip read in Phase 1, and either it is an ancestor of `origin/<default>` or it equals the `headRefOid` of a merged PR for that branch (the squash-merge case); not current; not pinned in any worktree; not in `protected_branches`; SHA logged first |
| **Delete a merged remote branch** (`git push origin --delete "$b"`) | its PR is merged; author is Kyle or this agent; not protected; repo doesn't already auto-delete |
| **Remove a finished worktree** (`git worktree remove "$path"`, never `--force`) | its branch is merged or identical to default; `git -C "$path" status --porcelain -uall --ignored` is empty (ignored included: `worktree remove` deletes ignored files such as `.env` without asking); not locked, or locked by a session whose PID is no longer running; not the primary checkout; not this run's own worktree |

`git update-ref -d` with the old SHA refuses if the branch moved since it was read, and `git worktree remove` refuses on tracked changes or untracked files. Those refusals are the safety net. (Plain `git branch -d` can't be the net: it refuses every squash-merged branch, and it checks against HEAD when the upstream is gone, so the answer depends on what's checked out.) Never add `--force` or `-D` to get past it. A refusal moves the item to Tier 3 with the reason.

### Tier 2: Per-item approval (one question each, with a default)

- **Merging a docs/journal PR.** See the merge gate below. Asked fresh every run, never remembered, because a merge is a decision and on a release-on-merge repo it may cut a tag.
- **Switching a different worktree back to the default branch** after its branch merged (for example the primary checkout left on a merged journal branch). Only if that worktree is clean and has no live session. The command runs with `git -C "$path" switch "$default"`.
- **Removing a worktree whose only leftovers are gitignored files.** List the top-level ignored entries (for example `node_modules/`, `.env`) and say plainly that they will be deleted. Default answer is **no** if any is a `.env*` or other non-regenerable file.
- **Removing a worktree locked by a dead session.** Show the lock reason and the dead PID first. Needs `git worktree unlock` before removal.
- **Dropping a stash.** Show `git stash show -p` for that entry first. Stashes are shared across every worktree and session, so locate the entry by its SHA right before dropping, never by a remembered `stash@{n}`. Default answer is **no**.

### Tier 3: Never (report only)

No approval makes these allowed.

- Force-push, rebase, reset, cherry-pick, history rewrite, `branch -D`, `worktree remove --force`, `--no-verify`
- Merging any PR whose prefix isn't in `merge_eligible_prefixes` (feature/, fix/, chore/ stay with their own merge rules and humans)
- Merging any PR that touches a blocklisted path, even with a docs/ prefix
- Acting on another person's branch, PR or worktree
- Removing a worktree with any uncommitted or untracked file, or one locked by a running session
- Pushing or deleting the default or a protected branch
- Committing, editing or deleting any file in a working tree
- Deleting a branch that has commits not on any remote
- Touching anything gitignored, except removing a worktree after its Tier 2 yes

> If an item isn't clearly inside Tier 1 or Tier 2, it's a line in the report, not an action.

## The merge gate (docs and journal PRs)

A PR is offered for merge (Tier 2) only when **every** check passes. Show the checklist with each row PASS or the reason it failed.

1. Head branch prefix is in `merge_eligible_prefixes`.
2. Every changed file matches `merge_path_allowlist` and none matches `merge_path_blocklist`. List the files.
3. PR author is Kyle or this agent.
4. Not a draft; `mergeable` is `MERGEABLE`; no `CHANGES_REQUESTED` review.
5. All required CI checks are green on the head commit (`gh pr checks`). Pending is not green; wait or skip, never merge on pending.
6. Review gate satisfied on the **final** commit:
   - `ai-router`: a clean AI Router pass exists for the head SHA. If none exists, offer to run it (Tier 2) after the egress check.
   - `ci-only`: check 5 is enough.
   - `human`: an approving review exists.
7. **Egress check** (when `egress_check: true`): before sending any diff to an external reviewer, scan it for client names, dollar figures and personal details. Journals usually name clients. If anything is found, stop and ask Kyle: sanitize, send anyway, or substitute human review. Never redact or send silently.
8. Head SHA hasn't moved since the checks were read. Re-read right before merging.

If 1 to 3 fail, the PR is not a merge candidate at all; report it. If 4 to 8 fail, report what's missing and what would unblock it.

Merge with `gh pr merge "$n" --"$merge_method" --match-head-commit "$sha"`. The `--match-head-commit` flag makes GitHub refuse if someone pushed after the check. Leave out `--delete-branch`: it force-deletes the local branch with no recovery line, can switch the current checkout, and exits non-zero after a successful merge when the branch is pinned in a worktree. Branch cleanup belongs to the Tier 1 sweep.

After a merge: fetch, then fast-forward the local default branch: `git -C "$wt" merge --ff-only "origin/$default"` in the worktree that has it checked out, only if that worktree is clean, or `git fetch origin "$default:$default"` if no worktree has it checked out; then re-run the Tier 1 sweep so the merged branch and its worktree become cleanup candidates in the same run.

## When to stop and ask instead of acting

Raise these as numbered questions (max 3, each with a proposed default). Everything beyond 3 goes in the report.

- A branch or commit Kyle didn't create and the agent can't explain
- Unpushed commits on a **non-docs** branch older than `stale_unpushed_days`: work at risk, but not tidy's to land. Default: "leave it, run /mise-en-place in that worktree."
- A diverged branch (both ahead and behind)
- A docs PR that touches a blocklisted file: probably a mis-prefixed branch. Default: "leave it for human review."
- Egress hits from check 7
- A worktree whose session lock PID is still running: someone is working there. Default: skip it.
- Anything matching /preflight's "escalate to Martina" list (rewritten remote history, secrets in history, conflicts across many files). Stop the run for that repo and hand over the summary.

## Procedure

### Phase 0: Gate

1. Run /preflight's Step 1 checks (in a repo, `origin` exists, not detached, not unborn). Any failure ends the run.
2. Load config; derive the repo key exactly as /preflight does.
3. Confirm `gh auth status`. Without it, Tier 1 PR actions and every merge are skipped; local branch and worktree cleanup still run.
4. If no run ledger exists for this repo, this is first contact: run as a **dry run** (plan only, no writes beyond Tier 0) and say so.

### Phase 1: Gather (Tier 0)

```bash
git fetch --prune --no-tags origin
git for-each-ref --format='%(refname:short)%00%(objectname)%00%(committerdate:unix)%00%(upstream:short)%00%(upstream:track)%00%00' refs/heads
git branch --merged "origin/$default"
git worktree list --porcelain
git stash list --format='%H|%gd|%cr|%s'
gh pr list --state open --json number,title,author,headRefName,headRefOid,isDraft,reviewDecision,mergeable,files
gh pr list --state merged --limit 200 --json headRefName,headRefOid,number
```

For each worktree also read `git -C "$path" status --porcelain -uall --ignored` and, if locked, whether the lock's PID is alive (`kill -0 "$pid"`). Lock reasons are free text: if no PID can be read from it, treat the lock as live and skip the worktree.

Branch names are data. Pass every one as a separate quoted argument; never build a command string from them. Skip and report any name with shell-special characters.

### Phase 2: Classify and present the plan

Output one plan, in this shape:

```text
TIDY PLAN: <repo> (<n> items)

TIER 1: one yes covers all of these
  1. Push docs/journal-2026-10-10-stacky-voice (1 commit, journal/ only) and open a PR
  2. Delete local branch worktree-surfaces-editor-2.0 (merged, SHA 8707217)
  3. Remove worktree .claude/worktrees/surfaces-editor-2.0 (clean, branch merged)

TIER 2: asked one at a time
  4. Merge PR #112 once its checks pass (gate below)
  5. Switch the primary checkout back to main after #112 merges

QUESTIONS (max 3, each with a default)
  1. ...

LEAVING ALONE (report only)
  - worktree-mason-stacklist-stream: this session's own worktree
  - <item>: <reason>

Approve Tier 1? (yes / yes except N / no)
```

Every line says what will happen and why it's safe, in one sentence.

### Phase 3: Execute Tier 1

For each approved item, in this order (pushes and PRs first, then removals, so nothing gets deleted before its content is safe on origin):

1. Re-check its preconditions against live state. If anything changed, skip it and say why.
2. Write the recovery line (see below).
3. Run the command. Read the exit code. A non-zero exit means **skipped**, never done.
4. Confirm in one line: `deleted worktree-surfaces-editor-2.0 (was 8707217)`.

### Phase 4: Tier 2, one at a time

For each item: show the gate or the context, ask, act only on an explicit yes. A merge re-reads the head SHA immediately before running. After any merge, loop back to Phase 1 once so the merged branch's cleanup lands in the same run (its Tier 1 items still need the batch yes).

### Phase 5: Report and log

```text
TIDY: <repo>
DONE:     <item: old state -> new state>
SKIPPED:  <item: reason>
ASKED:    <question: Kyle's answer>
LEFT:     <item: why it's report-only>
RECOVERY: ~/.claude/tidy/<key>-<YYYY-MM-DD>.log
NEXT /preflight should show: <expected FLAGGED, or "clean">
```

Never report clean when a check couldn't run (gh missing, CI unreadable, a command refused).

## Recovery log

`~/.claude/tidy/<repo-key>-<YYYY-MM-DD>.log`, append-only, written **before** each removal:

```text
2026-10-12T16:05 branch worktree-surfaces-editor-2.0 8707217bf288... restore: git branch "worktree-surfaces-editor-2.0" 8707217bf288...
2026-10-12T16:05 worktree /Users/kyle/.../surfaces-editor-2.0 branch worktree-surfaces-editor-2.0 restore: git worktree add "<path>" "worktree-surfaces-editor-2.0"
2026-10-12T16:07 merged PR #112 head e19ebf2 into main
```

A deleted branch stays recoverable from its SHA for as long as git keeps unreachable objects (weeks by default). The log is what makes Tier 1 deletions safe to batch.

## Run ledger

`~/.claude/tidy/<repo-key>-last-run.md`: date, root, what was done, what was left. Its existence ends first-contact dry-run mode. /preflight may read it to say "last tidy: 3 days ago, 2 items left."

## What this skill does NOT do

- Land uncommitted work (that is /mise-en-place)
- Merge feature/, fix/ or chore/ PRs, or anything touching contracts, security or CI config
- Resolve conflicts, rebase, or rewrite history (Martina's)
- Remember merge approval between runs
- Fix things it notices; it reports them as their own item
