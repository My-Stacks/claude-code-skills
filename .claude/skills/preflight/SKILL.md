---
name: preflight
version: "4.1"
description: >-
  Pre-session safe-sync briefing for git repos. Brings the repo up to date
  before work begins — fast-forwards active branches to origin, flags stale
  ones — then reports local state, open PRs, and where new work should branch
  from. Performs only safe, non-destructive writes (ff-only sync, config
  setup), narrating each before it runs. Never rewrites history, never makes a
  decision that's Kyle's. Teaches the reasoning so Kyle learns git.
trigger: /preflight
allowed-tools: Bash, Read, Edit, Write
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
- `git fetch --prune --no-tags origin` to update remote-tracking refs (`--no-tags` so local tags are never moved).
- **Fast-forward-only** sync of *active* branches to origin (never a merge commit, never a rewrite).
- Create `.claude/preflight.yml` on first run (never stage or commit it).
- Add `.claude/preflight.yml` to `.gitignore` and commit **only `.gitignore`** — only when the working tree is otherwise clean.

**NEVER**:
- Non-fast-forward merge, rebase, force-push, reset, cherry-pick.
- Create, switch, delete, or rename a branch or tag. (Branch-switch/create commands shown to Kyle are **suggestions he runs**, never executed by the skill.)
- Commit anything other than the `.gitignore` rule. Never `git add -A`/`git add .`; never commit the config file.
- Push Kyle's commits.
- Pull or modify a **stale, diverged, ahead-only, or no-upstream** branch, or any branch whose upstream is not `origin/<same-name>` (flag only).
- Touch a **dirty working tree** (uncommitted tracked changes) — skip the write and flag instead.

If a situation isn't clearly inside "MAY," it's a recommendation, not an action.

## Operating principles

1. **Safe writes only, always narrated.** Before any fast-forward or commit, say what you're about to do and why in plain language. After, confirm what moved. Anything outside the charter stays a recommendation Kyle runs himself.
2. **Teach with every action and recommendation.** Kyle is learning git. Skip the lecture, never skip the reasoning.
3. **Evidence over opinion.** Not "best practices suggest X." Instead "this PR has been open 3 weeks with no review activity — worth deciding before starting new work."
4. **Decisions stay with Kyle.** Risky or judgment calls (merges, divergence, deletions, rotation) end with what Kyle should consider — never "I'll proceed."
5. **Plain-language git terms.** First time per session you use a term Kyle might not know fluently (upstream, HEAD, fast-forward, refspec, ff-only, reflog), parenthetically explain it.
6. **Know what's out of scope.** No conflict resolution, history rewriting, or secret cleanup. Point Kyle to his existing workflow or to Martina.

## Per-repo config

Config lives at `.claude/preflight.yml` (repo root). It is **always gitignored** — see Step 3.

```yaml
default_branch: main           # main | master | develop
dev_branch: dev                # optional integration branch; omit if none
protected_branches: [main]     # never recommend deleting, even if merged
branch_naming: kebab-feature   # how new branches should be named (descriptive answer)
active_window_days: 14         # branches with commits newer than this are "active"
active_prefixes: [feat, feature, fix, chore]  # branch prefixes eligible for auto-sync
```

`active_window_days` defaults to 14 (a ~two-week window). `main` and `dev_branch` are **always** treated as active regardless of age. If the remote default differs from `default_branch`, trust the remote: resolve it with `git symbolic-ref -q refs/remotes/origin/HEAD`.

## The workflow

Run these steps in order. Writes happen only where the charter allows, only after narrating, and only after the preconditions in Steps 1–2 pass.

### Step 1: Location & preconditions

```bash
git rev-parse --is-inside-work-tree
git rev-parse --show-toplevel
git remote -v
git branch --show-current      # empty output => detached HEAD
```

Report which repo, remote, branch, attached or detached. This step gates **all later writes**:

- **Not in a repo** (`--is-inside-work-tree` non-zero): stop. Tell Kyle to cd into a repo and re-run. **No writes.**
- **No `origin` remote** (`git remote | grep -qx origin` fails): run read-only only. Skip Step 3's commit and all of Step 4's syncing; report "no `origin` — nothing to sync against."
- **Detached HEAD** (`git branch --show-current` empty): explain in one sentence ("you're viewing a specific commit, not attached to any branch — work here won't automatically belong anywhere"), recommend re-attaching. **Do not switch, do not sync, do not run Step 3 writes.**
- **Unborn/empty repo** (no commits yet): report it; skip Step 3 commit and Step 4 sync.

### Step 2: Working tree state

```bash
git status --porcelain
git stash list --format='%gd|%cr|%s'
```

Report modified / staged / untracked / stashes, one line each. **Define cleanliness once and reuse it:**

- **tracked-dirty** = any `git status --porcelain` line NOT beginning with `??` (staged or modified tracked files). This blocks *all* writes in Steps 3 and 4.
- **untracked-only** = output is empty or every line begins with `??`. Writes may proceed (but see the untracked-collision note in Step 4).

Also: flag untracked files matching "shouldn't be here" patterns (`.env`, zero-byte odd names, accidental redirects) — load `reference.md → "Files that look out of place"`. Stashes older than 8 weeks: mention as a future cleanup pass, not a blocker.

### Step 3: Config & gitignore (first run, idempotent)

The config file must never be committed; the `.gitignore` rule that protects it should be. **Order matters** — check tracked state first, then ignore state, then write.

1. **Already tracked?** `git ls-files --error-unmatch .claude/preflight.yml` (exit 0 = tracked). If tracked, gitignore won't untrack it — **flag it** (`git rm --cached .claude/preflight.yml` is Kyle's call) and skip the rest of Step 3. Don't silently remove.
2. **Repo `.gitignore` already has the rule?** `grep -qxF '.claude/preflight.yml' .gitignore` (file may not exist). If present, it's protected — skip to step 5 below. (Don't rely on `git check-ignore` alone: it also matches global excludes / `.git/info/exclude`, which doesn't satisfy "the repo's own `.gitignore` carries the rule.")
3. **tracked-dirty? (Step 2)** Then **do not edit, stage, or commit anything.** Tell Kyle: add `.claude/preflight.yml` to `.gitignore` and commit it when his tree is clean (give the two commands). Note the config stays unignored until then — avoid `git add .`. Skip to step 5.
4. **Clean tree:** add the rule and commit only it:
   ```bash
   # add the line (create .gitignore if absent) via Edit/Write, then:
   git add .gitignore
   test "$(git diff --cached --name-only)" = ".gitignore"   # MUST hold; abort if not
   git commit -m "chore: ignore .claude/preflight.yml" -- .gitignore
   ```
   The `test` is the gate: it confirms `.gitignore` is the *only* staged path before committing. Never amend (a new commit, never `--amend`); never push. If `git commit` fails (hooks, signing), report it — never retry with `--no-verify`.
5. **Create the config** if missing: ask the config questions (explain each; for `branch_naming` save Kyle's plain-language answer verbatim), then write `.claude/preflight.yml`. Never `git add` it.

Load `reference.md → "First-run config & gitignore"` for the reasoning and edge cases.

### Step 4: Sync — classify, fast-forward active, flag the rest

Classify every local branch, fast-forward only the *active* ones, flag everything else with reasoning. Skip this whole step if Step 1 found no `origin`, detached HEAD, or an unborn repo.

**Gather (one cheap pass, no checkout, stay on the current branch):**

```bash
git fetch --prune --no-tags origin
git for-each-ref --format='%(refname:short)|%(committerdate:unix)|%(upstream:short)|%(upstream:track)' refs/heads
git branch --merged "origin/<default>"          # ancestry-based merged detection
git worktree list --porcelain                    # machine-readable worktree-pinned detection
```

If `gh` is available and authenticated (`command -v gh && gh auth status`), also catch squash-merges:

```bash
gh pr list --state merged --base "<default>" --limit 200 --json headRefName
```

If `gh` is missing/unauthenticated: note "PR/squash data unavailable," rely on the ancestry check above, and treat uncertain branches as **flag-only** (never pull a maybe-merged branch).

**ACTIVE (eligible to fast-forward)** — a branch qualifies only if **all** hold:
- upstream is exactly `origin/<same-branch-name>` (not a fork/other remote, not a renamed upstream), **and**
- behind-only (`[behind N]`, N>0; not diverged, not ahead, not in-sync), **and**
- is `default_branch` / `dev_branch`, **or** its name matches one of `active_prefixes` (`^(feat|feature|fix|chore)/` by default), **and**
- not merged into the default branch (ancestry or merged-PR), **and**
- recent (commit within `active_window_days`) — `main`/`dev` are always recent enough.

**In-sync** branches (`[behind 0]` / no track marker) need no action — report as "current," not flagged.

Everything else is **FLAG-ONLY**: diverged, ahead-only (unpushed), no-upstream, non-origin upstream, `[gone]` upstream (merged/abandoned), merged-into-default, stale (beyond window), unrecognized-name-but-otherwise-eligible (ask before pulling), worktree-pinned, detached HEAD.

**Fast-forward mechanics (ff-only, never merge/rebase):**
- **Non-current active branches** — update the ref in place *without checkout*, batched, fully-qualified and quoted, **excluding the current branch and any worktree-pinned branch**:
  ```bash
  git fetch --no-tags origin 'refs/heads/main:refs/heads/main' 'refs/heads/fix/login:refs/heads/fix/login'
  ```
  Git **refuses** any refspec that isn't a clean fast-forward and leaves that ref unchanged. **Never** prefix a refspec with `+` or pass `--force`. Only include branches returned by `git for-each-ref` (never invent `dev:dev` if no local `dev` exists — that would *create* a branch). A batched fetch is **not** atomic: one ref can update while another is rejected — parse per-ref, don't assume all-or-nothing.
- **Current branch** — can't be refspec-updated. Only if its upstream is `origin/<current>` **and** the tree is not tracked-dirty (Step 2):
  ```bash
  git merge --ff-only @{u}
  ```
  (`@{u}` is the current branch's upstream. `merge --ff-only` aborts cleanly on divergence and isn't affected by `pull.rebase` config.) Untracked-only is usually fine, but an untracked file colliding with an incoming tracked path will abort — treat *any* non-zero exit as "skipped: could not fast-forward," not as synced.

**Narrate before, verify after.** Before: "main is 3 behind origin — fast-forwarding slides your pointer to match, no merge commit." After, confirm each branch's old→new SHA from the command output (a `! [rejected]` line or non-zero merge = "skipped: diverged," **never** "synced"). Two summaries:
- **SYNCED:** `branch: oldSHA → newSHA`
- **FLAGGED:** table of `branch | state | why not pulled | suggested next step`

For diverged default, load `reference.md → "Diverged default branch"` before recommending. Deeper mechanics: `reference.md → "Auto-sync mechanics: refspec ff vs pull"` and `→ "Active vs stale: the classification table"`.

### Step 5: Open PRs

Gate first: `command -v gh && gh auth status`. If unavailable, note "PR data unavailable (gh not configured)" and skip to Step 6.

```bash
gh pr list --state open --json number,title,author,headRefName,baseRefName,isDraft,reviewDecision,updatedAt,labels
gh pr list --state open --search "review-requested:@me" --json number,title,author,headRefName,updatedAt
```

**Kyle's PRs:** awaiting review / changes requested / approved / draft — with number, title, branch, age, and a brief note on whether it affects today's work. **Review-requested PRs:** surfaced by the second query. Files Kyle's about to touch: only if he's said what he's working on.

Don't be prescriptive about *what* to do — surface state and relevance. **Backlog threshold:** 3+ stalled PRs (>1 week, Kyle's action needed) → flag as worth addressing before new work. Load `reference.md → "Managing your PR backlog"` if Kyle asks.

### Step 6: Branch recommendation for new work

The question Kyle came to answer: "where do I start?" Because Step 4 already synced the active branches, the default base is usually current.

**These are suggestions for Kyle to run — the skill never executes them** (branch switch/create are outside the charter):

```bash
git switch <default>            # already up to date after Step 4
git switch -c <new-branch-name>
```

Use `branch_naming` to suggest a pattern; don't invent a specific name unless Kyle's said what he's building.

**Special cases:**
- **Work builds on an open PR's branch:** suggest branching from that branch (likely synced in Step 4 if active) instead of default, with explanation.
- **Default diverged** (couldn't be fast-forwarded in Step 4): flag — branching now means a stale/forked base. Resolve first.
- **On a feature branch with uncommitted work:** handle it first (commit/stash/finish) before starting something new.

### Step 7: Verdict

```text
REPO: <path>
BRANCH: <current> (<sync status, e.g. "2 behind → up to date" | "up to date" | "diverged">)
DEFAULT: <default> (<sync status>)
SYNCED: <branches fast-forwarded this run, or "none needed">
FLAGGED: <branches not pulled + one-word reason each, or "none">
WORKING TREE: <clean / N modified / N untracked / N stashed>
OPEN PRS: <count>, <breakdown, or "unavailable">

WHAT TO KNOW BEFORE STARTING:
- <things Kyle should be aware of>

RECOMMENDED BASE FOR NEW WORK:
<branch> (<command for Kyle to run>)
```

End with one of:

✅ **Clear to start.** Nothing blocking; active branches synced. Suggest the branch command.

⚠️ **Things worth handling first.** Items that could compound if ignored (flagged branches, PR backlog). Kyle decides priority.

🛑 **Recommend resolving before starting.** Items that will likely cause problems (diverged default, secrets in tree, severely stale backlog). Kyle decides; the skill flags severity.

## When Kyle asks "what would you do?" or "why does this matter?"

**Load `reference.md`** and answer from the relevant section — don't improvise generic git advice. Any command shown there for a risky operation (reset, branch save, tag, delete) is a **suggestion for Kyle to run**; the skill never executes it.

- Auto-sync / refspec / ff vs merge → "Auto-sync mechanics: refspec ff vs pull"
- Which branches get pulled → "Active vs stale: the classification table"
- Config / gitignore behavior → "First-run config & gitignore"
- Rebase vs merge → "Rebase vs merge"
- Diverged branches → "Diverged default branch"
- Stale stashes/branches → "When to clean up vs when to leave it"
- Secrets in tracked files → "Secrets and sensitive files"
- Detached HEAD → "Detached HEAD"
- PR backlog → "Managing your PR backlog"
- Worktrees → "Worktrees and branch safety"

## Known limitations

These are flagged-not-handled by design — when encountered, report and defer to Kyle rather than improvising: submodule dirtiness, sparse/shallow checkouts, case-only branch-name differences, branches squash-merged locally without a PR (no record to detect), and commit-recency based on the local tip date (a behind-only branch with newer *remote* commits may read as stale near the window edge).

## What this skill does NOT do

- **No unsafe writes.** Only fast-forwards and the single-file `.gitignore` commit. No merges, rebases, resets, force-pushes, branch/tag create/switch/delete, or pushes of Kyle's commits.
- **No touching dirty trees or risky branches.** tracked-dirty trees and diverged/ahead/no-upstream/non-origin/stale branches are flagged, never modified.
- **No shipping workflow** (push, PR open, merge). Kyle's PR process lives outside this skill.
- **No history rewriting or secret cleanup.** Those are Martina's.
- **No nagging.** Surface things once, with reasoning. Kyle decides.
