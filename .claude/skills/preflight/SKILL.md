---
name: preflight
version: "4.0"
description: >-
  Pre-session safe-sync briefing for git repos. Brings the repo up to date
  before work begins — fast-forwards active branches to origin, flags stale
  ones — then reports local state, open PRs, and where new work should branch
  from. Performs only safe, non-destructive writes (ff-only sync, config
  setup), narrating each before it runs. Never rewrites history, never makes a
  decision that's Kyle's. Teaches the reasoning so Kyle learns git.
allowed-tools: Bash, Read, Edit
---

# preflight — Safe Sync & Situational Awareness Before You Code

## What this skill is

A pre-session briefing that **brings the repo up to date and explains as it goes**. Before Kyle starts a coding session, it answers:

1. **Where am I?** Repo, branch, working tree state.
2. **What's synced?** Local vs origin — and it *fast-forwards active branches* so nothing starts from stale code.
3. **What's in flight?** Open PRs (his, the team's), anything blocking new work.
4. **Where should new work go?** Recommended base branch and branch name pattern.

It performs a **bounded set of safe, non-destructive writes** and narrates each one before doing it. It never rewrites history, never merges/rebases/force-pushes, and never makes a decision that's Kyle's.

## Who this is for

Kyle is a technical founder. Strong on product and program management, comfortable in the terminal, actively learning git. His CTO Martina has 10+ years of git fluency but her workflow is "type commands from memory" — not scalable or teachable. This skill is the teaching layer: it does the observability and routine syncing Martina does in her head, but out loud and with explanations.

## The charter — what preflight MAY and MAY NOT do

This is the load-bearing contract. Everything below obeys it.

**MAY write** (safe, non-destructive, **always narrated before it runs**):
- `git fetch --prune` to update remote-tracking refs.
- **Fast-forward-only** sync of *active* branches to origin (never a merge commit, never a rewrite).
- Create `.claude/preflight.yml` on first run.
- Add `.claude/preflight.yml` to `.gitignore` and commit **that one file** — only when the working tree is otherwise clean.

**NEVER**:
- Non-fast-forward merge, rebase, force-push, reset, cherry-pick.
- Delete or rename a branch or tag.
- Push Kyle's commits.
- Pull or modify a **stale, diverged, ahead-only, or no-upstream** branch (flag only).
- Touch a **dirty working tree** (uncommitted tracked changes) — skip and flag instead.

If a situation isn't clearly inside "MAY," it's a recommendation, not an action.

## Operating principles

1. **Safe writes only, always narrated.** Before any fast-forward or commit, say what you're about to do and why in plain language. After, confirm what moved. Anything outside the charter stays a recommendation Kyle runs himself.

2. **Teach with every action and recommendation.** Kyle is learning git through these sessions. Skip the lecture, never skip the reasoning.

3. **Evidence over opinion.** Not "best practices suggest X." Instead "this PR has been open 3 weeks with no review activity — worth deciding before starting new work."

4. **Decisions stay with Kyle.** Risky or judgment calls (merges, divergence, deletions, rotation) end with what Kyle should consider — never "I'll proceed."

5. **Plain-language git terms.** First time per session you use a term Kyle might not know fluently (upstream, HEAD, fast-forward, refspec, ff-only, reflog), parenthetically explain it.

6. **Know what's out of scope.** No conflict resolution, history rewriting, or secret cleanup. Point Kyle to his existing workflow or to Martina.

## Per-repo config

Config lives at `.claude/preflight.yml` (repo root). It is **always gitignored** — see Step 0.

```yaml
default_branch: main           # main | master | develop
dev_branch: dev                # optional integration branch; omit if none
protected_branches: [main]     # never recommend deleting, even if merged
branch_naming: kebab-feature   # how new branches should be named (descriptive answer)
active_window_days: 14         # branches with commits newer than this are "active"
```

`active_window_days` defaults to 14. `main` and `dev_branch` are **always** treated as active regardless of age.

## The workflow

Run these steps in order. Writes happen only where the charter allows, and only after narrating.

### Step 0: Config & gitignore (first run, idempotent)

The config file must never be committed; the `.gitignore` rule that protects it should be.

1. **Is it already ignored?** `git check-ignore -q .claude/preflight.yml`
   - Exit 0 → already ignored. Do nothing here (steady-state runs stay write-free).
2. **If not ignored**, add the rule *before* creating the config so git never sees it as a stageable untracked file:
   - Add line `.claude/preflight.yml` to `.gitignore` (create the file if absent) using `Edit`.
   - Stage **only** that file: `git add .gitignore` (never `git add -A` / `git add .`).
   - **Commit gate:** if the working tree is otherwise clean (`git diff --cached --quiet` passes for everything but `.gitignore`, and no other staged work), commit: `git commit -m "chore: ignore .claude/preflight.yml"`. Otherwise **don't commit** — leave it staged and tell Kyle the one command to run. Never push.
3. **If the config is already *tracked*** (caught by `git ls-files`): gitignore won't untrack it. **Flag it** — `git rm --cached` is Kyle's call. Don't silently remove.
4. **Create the config** if missing: ask the config questions (explain each; for `branch_naming` save Kyle's plain-language answer verbatim), then write `.claude/preflight.yml`.

Load `reference.md → "First-run config & gitignore"` if any edge case is unclear.

### Step 1: Location

```
git rev-parse --show-toplevel
git remote -v
git rev-parse --abbrev-ref HEAD
git symbolic-ref -q HEAD
```

Report which repo, remote, branch, attached or detached.

**If not in a repo:** stop. Tell Kyle to cd into a repo and re-run.

**If detached HEAD:** explain in one sentence ("you're viewing a specific commit, not attached to any branch — work here won't automatically belong anywhere"), recommend re-attaching. Do not switch yourself, and **do not sync** in detached state.

### Step 2: Working tree state

```
git status --porcelain
git stash list --format='%gd|%cr|%s'
```

Report modified / staged / untracked / stashes, one line each. This step also gates Step 3: a **dirty tree (modified or staged tracked files)** means the current branch will not be fast-forwarded.

- Flag untracked files matching "shouldn't be here" patterns (`.env`, zero-byte odd names, accidental redirects) — load `reference.md → "Files that look out of place"`.
- Stashes older than 8 weeks: mention as a future cleanup pass, not a blocker.

### Step 3: Sync — classify, fast-forward active, flag the rest

This is the new core. Classify every local branch, fast-forward only the *active* ones, flag everything else with reasoning.

**Gather (one cheap pass, no checkout, stay on the current branch):**

```
git fetch --prune origin
git for-each-ref --format='%(refname:short)|%(committerdate:unix)|%(upstream:short)|%(upstream:track)' refs/heads
gh pr list --state merged --json headRefName   # catches squash-merges that --merged misses
git branch -vv                                  # '+' prefix = checked out in another worktree
```

**ACTIVE (eligible to fast-forward)** — a branch qualifies only if **all** hold:
- has an upstream, **and**
- behind-only (`[behind N]`, not diverged, not ahead), **and**
- is `default_branch` / `dev_branch`, **or** matches `^(feat|feature|fix|chore)/`, **and**
- not merged into the default branch, **and**
- recent (commit within `active_window_days`) — `main`/`dev` are always active.

Everything else is **FLAG-ONLY**: diverged, ahead-only (unpushed), no-upstream, `[gone]` upstream (merged/abandoned), merged-into-default, stale (beyond window), detached HEAD, worktree-pinned (`+`).

**Fast-forward mechanics (ff-only, never merge/rebase):**
- **Non-current active branches** — update the ref in place *without checkout*, batched:
  `git fetch origin main:main dev:dev fix/x:fix/x`
  Git **refuses** any refspec that isn't a clean fast-forward and changes nothing. **Never** prefix a refspec with `+` or pass `--force`. **Skip** worktree-pinned branches (refspec-updating them errors).
- **Current branch** — can't be refspec-updated; use `git pull --ff-only` (aborts on divergence), **only if the tree is clean** (Step 2). Untracked-only is fine.
- **Parse the outcome.** A rejected refspec or aborted ff-only is reported as "skipped: diverged," **never** as "synced."

**Narrate before and report after.** Before: "main is 3 behind origin — fast-forwarding slides your pointer to match, no merge commit." After, two summaries:
- **SYNCED:** `branch: oldSHA → newSHA`
- **FLAGGED:** table of `branch | state | why not pulled | suggested next step`

For diverged default branch, load `reference.md → "Diverged default branch"` before recommending. Deeper mechanics in `reference.md → "Auto-sync mechanics: refspec ff vs pull"` and `→ "Active vs stale: the classification table"`.

### Step 4: Open PRs

```
gh pr list --state open --json number,title,author,headRefName,baseRefName,isDraft,reviewDecision,updatedAt,labels
gh pr list --state open --author "@me" --json number,title,headRefName,baseRefName,reviewDecision,updatedAt
```

**Kyle's PRs:** awaiting review / changes requested / approved / draft — with number, title, branch, age, and a brief note on whether it affects today's work. **Team PRs:** where Kyle is a requested reviewer; files Kyle's about to touch (only if he's said what he's working on).

Don't be prescriptive about *what* to do — surface state and relevance. **Backlog threshold:** 3+ stalled PRs (>1 week, Kyle's action needed) → flag as worth addressing before new work, with reasoning. Load `reference.md → "Managing your PR backlog"` if Kyle asks.

### Step 5: Branch recommendation for new work

The question Kyle came to answer: "where do I start?" Because Step 3 already synced the active branches, the default base is usually current.

```
git switch <default>            # already up to date after Step 3
git switch -c <new-branch-name>
```

Use `branch_naming` to suggest a pattern; don't invent a specific name unless Kyle's said what he's building.

**Special cases:**
- **Work builds on an open PR's branch:** recommend branching from that branch (it was likely synced in Step 3 if active) instead of default, with explanation.
- **Default diverged** (couldn't be fast-forwarded in Step 3): flag — branching now means stale/forked base. Resolve first.
- **On a feature branch with uncommitted work:** handle it first (commit/stash/finish) before starting something new.

### Step 6: Verdict

```
REPO: <path>
BRANCH: <current> (<sync status>)
DEFAULT: <default> (<sync status>)
SYNCED: <branches fast-forwarded this run, or "none needed">
FLAGGED: <branches not pulled + one-word reason each, or "none">
WORKING TREE: <clean / N modified / N untracked / N stashed>
OPEN PRS: <count>, <breakdown>

WHAT TO KNOW BEFORE STARTING:
- <things Kyle should be aware of>

RECOMMENDED BASE FOR NEW WORK:
<branch> (<command to get there>)
```

End with one of:

✅ **Clear to start.** Nothing blocking; active branches synced. Suggest the branch command.

⚠️ **Things worth handling first.** Items that could compound if ignored (flagged branches, PR backlog). Kyle decides priority.

🛑 **Recommend resolving before starting.** Items that will likely cause problems (diverged default, secrets in tree, severely stale backlog). Kyle decides; the skill flags severity.

## When Kyle asks "what would you do?" or "why does this matter?"

**Load `reference.md`** and answer from the relevant section — don't improvise generic git advice.

- Auto-sync / refspec / ff vs pull → "Auto-sync mechanics: refspec ff vs pull"
- Which branches get pulled → "Active vs stale: the classification table"
- Config / gitignore behavior → "First-run config & gitignore"
- Rebase vs merge → "Rebase vs merge"
- Diverged branches → "Diverged default branch"
- Stale stashes/branches → "When to clean up vs when to leave it"
- Secrets in tracked files → "Secrets and sensitive files"
- Detached HEAD → "Detached HEAD"
- PR backlog → "Managing your PR backlog"
- Worktrees → "Worktrees and branch safety"

## What this skill does NOT do

- **No unsafe writes.** Only fast-forwards and the config-gitignore commit. No merges, rebases, resets, force-pushes, deletions, or pushes of Kyle's commits.
- **No touching dirty trees or risky branches.** Diverged/ahead/no-upstream/stale branches are flagged, never modified.
- **No shipping workflow** (push, PR open, merge). Kyle's PR process lives outside this skill.
- **No history rewriting or secret cleanup.** Those are Martina's.
- **No nagging.** Surface things once, with reasoning. Kyle decides.
