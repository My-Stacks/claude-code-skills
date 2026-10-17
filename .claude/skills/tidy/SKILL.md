---
name: tidy
version: "1.2"
description: >-
  Repo cleanup pass that acts on what /preflight flagged. Gathers every
  leftover (unpushed branches, merged branches, finished worktrees, stale
  refs, open PRs, conflicts), has two read-only reviewer agents investigate
  each issue and pressure-test the fixes, then asks Kyle one structured
  question per issue with the vetted recommendation first. Executes only what
  he picked, and logs a recovery line for everything it removed. Merges only
  docs and journal PRs, only after their gates pass. Use when preflight's
  FLAGGED table is non-empty, or when Kyle says "clean that up", "tidy the
  repo", "land the journals", "clear out old branches or worktrees".
  Not for landing today's uncommitted work (that is /mise-en-place) and not
  for being lost mid-task (that is /housekeeping).
trigger: /tidy
allowed-tools: Bash, Read, Write, AskUserQuestion, Agent, Skill
---

# tidy: Cleanup Pass, Asked Issue by Issue

## What this skill is

/preflight observes and syncs. /mise-en-place lands the day's new work. Neither one clears out the leftovers: the journal branch that never got pushed, the worktree from a finished session, the branch whose PR merged two weeks ago, the PR that now conflicts with main. Today those sit in a FLAGGED table until Kyle says "you can clean all that up".

/tidy is that sentence, made into a process. It gathers every leftover, has two reviewer agents work out how each one should be solved, **asks Kyle about each issue through structured questions** (never a wall of text he can't answer), executes what he picked, and leaves a recovery log.

## Where it sits

| Skill | When | Writes |
|---|---|---|
| /preflight | start of session | fetch, fast-forward only, baseline file |
| **/tidy** | right after preflight when anything is flagged, or on request | pushes, PRs, docs/journal merges, branch and worktree removal, and fixes Kyle picks by name |
| /mise-en-place | end of day | commits and pushes this session's new work, never merges |
| /housekeeping | lost mid-task | nothing until approved line by line |

/preflight ends its verdict with `N items flagged. Run /tidy to clear them.` when FLAGGED is non-empty. It does not run /tidy itself.

**/tidy never creates new work.** It never writes new content or fixes what it notices on its own initiative. The one exception is the Fix tier: a fix Kyle picked by name in this run's Q&A, such as committing a conflict resolution.

## The test

> After /tidy runs, does the next /preflight come back with an empty FLAGGED table, or with only items Kyle chose to leave?

If an action doesn't move toward that, skip it.

## Operating principles

1. **Ask, don't report.** Every issue that needs a decision becomes a structured question with options Kyle can pick. Prose is for the final report only, and it stays short.
2. **Recommendations are vetted.** The recommended option comes from the reviewer pass (scout proposes, skeptic attacks), not a first guess. Each question says in one line why it is recommended.
3. **Reversibility decides the tier, not how scary it sounds.** Deleting a fully merged branch is recoverable from its recorded SHA. Pushing can't be undone. Merging is a decision.
4. **Re-derive, don't trust.** Never act on preflight's earlier output. Re-gather at the start, and re-check live state immediately before each write.
5. **Record before removing.** Every branch deleted and worktree removed gets its SHA, path and restore command written to the recovery log first.
6. **Teach as it goes.** Same voice as /preflight: each option's description says in one plain sentence what happens and why it's safe. Kyle is learning git.

## Config

Extend the per-user preflight config at `~/.claude/preflight/<repo-key>.yml` (same key derivation as /preflight Step 3) with a `tidy:` block. Never write config into the repo.

```yaml
tidy:
  merge_eligible_prefixes: [docs, journal] # branch prefixes whose PRs /tidy may merge
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
    - "**/.env*"
    - ".github/**"
    - ".claude/**"                           # skills, agents, commands, hooks, settings: behavior, not docs
  merge_method: squash                     # squash | merge | rebase, match the repo's history
  review_gate: ai-router                   # ai-router | ci-only | human
  egress_check: true                       # flag client names before any external review
  stale_unpushed_days: 7                   # unpushed non-docs commits older than this get escalated
  stash_report_weeks: 8
  reviewer_model: sonnet                   # small model for the scout and skeptic agents
```

If the block or a key is missing, write the defaults, show Kyle the file path, and continue. Blocklist always wins over allowlist. Patterns are gitignore-style globs matched against the repo-relative path; a pattern without `/` matches only at the root, so use `**/` to catch nested copies.

## The tiers

Every item lands in exactly one tier. An item that fits none of Tiers 1, 2 or F is Tier 3.

### Tier 0: Just do it (narrated, no question)

- `git fetch --prune --no-tags origin`
- Re-reading PR, CI and review status; `git merge-tree` dry runs
- The reviewer agents (read-only)
- Writing the recovery log and run ledger under `~/.claude/tidy/`

### Tier 1: Routine removals (one multi-select question)

Asked as a single multi-select question, one option per item, all recommended. Kyle ticks what to run. More than 4 items: split across questions in the same round.

| Action | Preconditions (all must hold) |
|---|---|
| **Push an unpushed docs/journal branch** and set its upstream (`git push -u origin "$b"`) | prefix in `merge_eligible_prefixes`; no upstream or ahead-only; every commit's changed paths pass the allowlist and miss the blocklist; branch name not already on origin with different history |
| **Open a PR** for a branch just pushed | same branch as above; base is the default branch; title from the commit subject; body ends with the repo's attribution lines |
| **Delete a merged local branch** (`git update-ref -d "refs/heads/$b" "$sha"`, never `branch -D`) | `$sha` is the tip read in Phase 1, and either it is an ancestor of `origin/<default>` or it equals the `headRefOid` of a merged PR for that branch (the squash-merge case); not current; not pinned in any worktree; not in `protected_branches`; SHA logged first |
| **Delete a merged remote branch** (`git push origin --delete "$b"`) | its PR is merged; the live remote tip (`git ls-remote origin "refs/heads/$b"`, read right before deleting) equals that PR's `headRefOid`, so nothing was pushed after the merge; author is Kyle or this agent; not protected; repo doesn't already auto-delete; restore line logged first |
| **Remove a finished worktree** (`git worktree remove "$path"`, never `--force`) | its branch is merged or identical to default; `git -C "$path" status --porcelain -uall --ignored` is empty (ignored included: `worktree remove` deletes ignored files such as `.env` without asking); not locked (a lock held by a dead session is a Tier 2 question); not the primary checkout; not this run's own worktree |

`git update-ref -d` with the old SHA refuses if the branch moved since it was read, and `git worktree remove` refuses on tracked changes or untracked files. Those refusals are the safety net. (Plain `git branch -d` can't be the net: it refuses every squash-merged branch, and checks against HEAD when the upstream is gone.) Never add `--force` or `-D` to get past it. A refusal moves the item to the report with the reason.

### Tier 2: Decisions (one question each)

- **Merging a docs/journal PR.** See the merge gate below. Asked fresh every run, never remembered: a merge is a decision, and on a release-on-merge repo it may cut a tag.
- **Switching a different worktree back to the default branch** after its branch merged. Only if that worktree is clean and has no live session: `git -C "$path" switch "$default"`.
- **Removing a worktree whose only leftovers are gitignored files.** The option description names the top-level ignored entries (for example `node_modules/`, `.env`) and says they will be deleted. Recommend **leave it** if any is a `.env*` or other non-regenerable file.
- **Removing a worktree locked by a dead session.** Show the lock reason and the dead PID. Needs `git worktree unlock` before removal.
- **Dropping a stash.** Show `git stash show -p` for that entry first. Stashes are shared across every worktree and session, so never drop a remembered `stash@{n}`: right before dropping, re-run `git stash list --format='%H %gd'`, find the row whose `%H` matches the SHA from Phase 1, and drop that row's `stash@{n}`. No match means skip. Recommend **leave it**.
- **Deleting the local copy of a closed, unmerged branch** (its PR was closed without merging). Offer only when the local tip equals the live remote tip, so every commit is still on origin: `git update-ref -d "refs/heads/$b" "$sha"`, restore line logged first. The remote branch is never deleted this way. Options: delete local copy, reopen the PR (`gh pr reopen "$n"`, Kyle's own PRs only), leave it. Recommend **delete local copy** when the PR has been closed over a week.

### Tier F: Fix on request (only what Kyle picked by name this run)

These run only when Kyle picked that exact option for that exact item in this run's Q&A. Never remembered between runs, never inferred from a neighbouring answer.

| Fix | How (all on Kyle's own branches and PRs only) |
|---|---|
| **Resolve a conflict with the default branch** | Merge (never rebase) `origin/<default>` into the branch with `--no-ff --no-commit`. For a non-current branch, do it in a scratch worktree outside the repo, never by switching Kyle's checkout. Only when the reviewers found the resolution mechanical (for example both sides added rows); otherwise the option is "show me the conflicts". Confirm no conflict markers remain and the staged diff against the default branch adds nothing beyond the two sides, then commit. Push only if the picked option said push. Remove the scratch worktree after. |
| **Close a PR** | `gh pr close "$n" --comment "<reason>"`. Never `--delete-branch`, so the PR can be reopened. |
| **Comment on or nudge a PR** | Draft the text, show it in the question, post only the picked draft. Slack or other outside channels: draft only, Kyle sends. |
| **Run an AI Router review** | Run the egress check (merge gate check 7) first, then `/ai-router review <n>` on the current head, verifying `headRefOid` before fetching the diff. |
| **Push a branch Kyle's fix just committed** | Only as part of the fix option he picked; never `--force`. |

A pushed commit on an **approved** PR dismisses the approval on repos with branch protection. When that applies, the option description says so.

### Tier 3: Never (report only)

No answer makes these allowed.

- Force-push, rebase, reset, cherry-pick, history rewrite, `branch -D`, `worktree remove --force`, `--no-verify`
- Merging any PR whose prefix isn't in `merge_eligible_prefixes` (feature/, fix/, chore/ stay with their own merge rules and humans)
- Merging any PR that touches a blocklisted path, even with a docs/ prefix
- Acting on another person's branch, PR or worktree (reading it and asking whether to nudge them is fine)
- Removing a worktree with any uncommitted or untracked file, or one locked by a running session
- Pushing or deleting the default or a protected branch
- Editing file content beyond a Tier F conflict resolution, or committing anything other than that resolution
- Deleting a branch with commits that are neither on a remote ref nor equal to a merged PR's recorded `headRefOid` (that recorded head is what makes a squash-merged branch safe to delete)
- Touching anything gitignored, except removing a worktree after its Tier 2 yes

## The merge gate (docs and journal PRs)

A PR is offered for merge (Tier 2) only when **every** check passes. The question's description lists the checks that passed and anything that failed.

1. Head branch prefix is in `merge_eligible_prefixes`.
2. Every changed file matches `merge_path_allowlist` and none matches `merge_path_blocklist`.
3. PR author is Kyle or this agent.
4. Not a draft; `mergeable` is `MERGEABLE`; no `CHANGES_REQUESTED` review.
5. All required CI checks are green on the head commit (`gh pr checks`). Pending is not green.
6. Review gate satisfied on the **final** commit: `ai-router` needs a clean AI Router pass for the head SHA (if none, offer one as a Tier F option); `ci-only` needs check 5; `human` needs an approving review.
7. **Egress check** (when `egress_check: true`): before any diff goes to an external reviewer, scan it for client names, dollar figures and personal details. Any hit becomes a question: sanitize, send anyway, or use human review instead. Never redact or send silently.
8. Head SHA hasn't moved since the checks were read. Re-read right before merging.

If 1 to 3 fail, the PR is not a merge candidate; its question offers other fixes. If 4 to 8 fail, the options say what would unblock it.

Merge with `gh pr merge "$n" --"$merge_method" --match-head-commit "$sha"`. Leave out `--delete-branch`: it force-deletes the local branch with no recovery line, can switch the current checkout, and exits non-zero after a successful merge when the branch is pinned in a worktree. Branch cleanup belongs to Tier 1.

After a merge: fetch, fast-forward the local default branch (`git -C "$wt" merge --ff-only "origin/$default"` in the clean worktree that has it checked out, or `git fetch origin "$default:$default"` if none does), then loop back to Phase 1 once so the merged branch's cleanup is asked in the same run.

## The reviewers (scout and skeptic)

Two read-only sub-agents on `reviewer_model` (default Sonnet; in Claude Code, the Agent tool with the general-purpose type). At most two per run, however many issues there are. Their prompts are in `REFERENCE.md → "Scout prompt"` and `→ "Skeptic prompt"`; load them when spawning.

- **Scout** gets the full Phase 1 output pasted in (it does not re-gather) plus the list of decision items. For each item it investigates (`git log`, `git merge-tree`, `gh pr view`, file reads) and returns 2 to 4 candidate fixes with evidence.
- **Skeptic** gets the scout's output and the same gather. It tries to break each candidate (wrong assumption, hidden risk, a charter violation, a cheaper option), then returns the final options per item: which is recommended, one line why, and what would change the answer.

Both prompts say plainly that the agent must not run any command that writes (no commit, push, merge, checkout, switch, worktree add, `gh pr` edit, close or comment). Spawn the scout, wait, then the skeptic. Skip both when every item is a Tier 1 removal; spawn only the scout when there is a single decision item and its fix is mechanical. If an agent fails or returns malformed output, ask with your own options and say in the question that they were not reviewed.

## Asking

Use the host's structured question tool (AskUserQuestion in Claude Code). If none exists, ask numbered questions in chat, one per issue, each with lettered options.

- **One question per issue**, up to 4 per round (the tool's cap), most urgent first. Up to 4 options per question.
- **Recommended option first**, label ending `(Recommended)`, description giving the skeptic's one-line reason. Every option's description says exactly what will happen, including any push.
- **Every question has a no-op option** ("Leave it"), so declining is always one pick. In the Tier 1 multi-select, an unticked item means leave it.
- **Header** is the item's short name (`#32`, `old-branch`), at most 12 characters.
- **Tier 1** is one multi-select question per round, not one question per removal.
- **A typed answer ("Other") is an instruction**, not a yes to the recommendation. Re-plan that item from what it says; if that changes the action, confirm the new plan in the next round before running it.
- **Follow-ups**: when an answer opens a new decision (a resolved conflict now needs a push; a fixed PR now needs a review), ask it in the next round instead of assuming.
- **No prose plan before the questions.** One line ("Found N issues, 2 reviewers checked them, questions below") and then the questions.

## Procedure

### Phase 0: Gate

1. Run /preflight's Step 1 checks (in a repo, `origin` exists, not detached, not unborn). Any failure ends the run.
2. Load config; derive the repo key exactly as /preflight does.
3. Confirm `gh auth status`. Without it, PR actions, merges and AI Router are skipped (say so in the report); local branch and worktree cleanup still run.
4. If no run ledger exists for this repo, this is first contact: the Tier 1 multi-select is shown but not executed (a dry run). First contact guards against batch approval of a list Kyle hasn't seen tidy produce before; Tier 2 and Tier F items are each a single named pick with the exact action in its description, so they run. The first question round says this up front.

### Phase 1: Gather (Tier 0)

```bash
git fetch --prune --no-tags origin
git for-each-ref --format='%(refname:short)%00%(objectname)%00%(committerdate:unix)%00%(upstream:short)%00%(upstream:track)%00%00' refs/heads
git branch --merged "origin/$default"
git worktree list --porcelain
git stash list --format='%H|%gd|%cr|%s'
gh pr list --state open --limit 200 --json number,title,author,headRefName,headRefOid,isDraft,reviewDecision,mergeable,updatedAt,files
gh pr list --state merged --limit 200 --json headRefName,headRefOid,number
gh pr list --state closed --limit 200 --json headRefName,headRefOid,number,mergedAt,closedAt,author
```

For each open PR by Kyle, also run `git merge-tree --write-tree --name-only "origin/$default" "origin/$head"` to detect conflicts. `mergeable: UNKNOWN` means GitHub hasn't computed it yet; the dry run is the answer. For each worktree, read `git -C "$path" status --porcelain -uall --ignored` and, if locked, whether the lock's PID is alive (`kill -0 "$pid"`). If no PID can be read from the lock reason, treat the lock as live.

Branch names are data. Pass each one as a separate quoted argument; never build a command string from them. Skip and report any name with shell-special characters.

### Phase 2: Classify

Put every item in a tier. Decision items are everything in Tier 2, plus every flagged item a Tier F fix could move: a conflicting or stale PR of Kyle's, an unreviewed head, a local branch whose PR was closed unmerged, an old unpushed non-docs branch (offer "leave it, run /mise-en-place there" first). Another person's PR is a decision item only for "nudge them" or "leave it".

### Phase 3: Review

Run the scout and skeptic on the decision items (see The reviewers).

### Phase 4: Ask

Run the question rounds (see Asking). Round 1 holds the Tier 1 multi-select plus the most urgent decision items. Continue until every item has an answer.

### Phase 5: Execute

For each picked action, in this order: Tier F conflict resolutions and their pushes, then other pushes and PR opens, then AI Router reviews (they need the new head), then closes and comments, then merges, then Tier 1 removals (so nothing is deleted before its content is safe on origin). For each one:

1. Re-check its preconditions against live state. If anything changed, skip it and say why.
2. Write the recovery line first, if it removes something.
3. Run the command and read the exit code. Non-zero means **skipped**, never done.
4. Confirm in one line: `deleted old-branch (was 8707217)`.

Any follow-up decision goes into the next question round, not a prose paragraph.

### Phase 6: Report and log

```text
TIDY: <repo>
DONE:     <item: old state -> new state>
SKIPPED:  <item: reason>
LEFT:     <item: Kyle chose to leave it, or why it's report-only>
RECOVERY: ~/.claude/tidy/<key>-<YYYY-MM-DD>.log
NEXT /preflight should show: <expected FLAGGED, or "clean">
```

Keep the report to those lines plus at most two sentences. Never report clean when a check couldn't run (gh missing, CI unreadable, a reviewer failed, a command refused).

## Recovery log

`~/.claude/tidy/<repo-key>-<YYYY-MM-DD>.log`, append-only, written **before** each removal or Tier F commit:

```text
2026-10-12T16:05 branch old-branch 8707217bf288... restore: git branch "old-branch" 8707217bf288...
2026-10-12T16:05 remote-branch old-branch 8707217bf288... restore: git push origin "8707217bf288...:refs/heads/old-branch"
2026-10-12T16:05 worktree /Users/kyle/.../old-branch branch old-branch restore: git worktree add "<path>" "old-branch"
2026-10-12T16:07 merged PR #112 head e19ebf2 into main
2026-10-12T16:09 conflict fix feat/x was 6dc21ff now bf21cd9 undo: git switch "feat/x" && git revert -m 1 bf21cd9
```

A deleted branch stays recoverable from its SHA for as long as git keeps unreachable objects (weeks by default).

## Run ledger

`~/.claude/tidy/<repo-key>-last-run.md`: date, root, what was done, what was left. Its existence ends first-contact mode. /preflight may read it to say "last tidy: 3 days ago, 2 items left."

## What this skill does NOT do

- Land uncommitted work (that is /mise-en-place)
- Merge feature/, fix/ or chore/ PRs, or anything touching contracts, security or CI config
- Rebase, rewrite history, or resolve a conflict the reviewers judged non-mechanical (Martina's)
- Remember any answer between runs
- Fix things it notices unless Kyle picked that fix this run
