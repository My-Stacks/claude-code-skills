# preflight Reference

Load sections of this file on demand when the main skill flags a situation that needs deeper reasoning. Pull the specific section relevant to the current question — don't load the whole file at once.

The tone of every section is *teaching*, not lecturing. Kyle is a smart adult learning git through these sessions. Explain the concept, give the reasoning, share the recommendation, and let him decide.

---

## Auto-sync mechanics: refspec ff vs pull

Step 3 brings active branches up to date **without ever leaving the current branch or making a merge commit**. Two mechanics, by branch:

**Non-current branches — fast-forward the ref in place via a fetch refspec:**

```
git fetch origin main:main dev:dev fix/login:fix/login
```

The `origin <src>:<dst>` form says "fetch origin's `main` and move my local `main` to match." The critical safety property: **git refuses to update a local branch ref unless the move is a clean fast-forward.** If the branch has diverged or has local-only commits, you get:

```
 ! [rejected]   main -> main (non-fast-forward)
```

…and nothing changes. That refusal is the whole safety mechanism. So the rule is absolute: **never prefix the refspec with `+` and never pass `--force`** — that's exactly what would turn a safe no-op into a destructive overwrite of local work. Batch all active non-current branches into one `git fetch` call.

Why not just check out each branch and `git pull`? Because checkout mutates the working tree, fails on uncommitted changes, can trigger conflicts, and is slow across many branches. Refspec ff touches only the ref pointer — the working tree of the current branch never moves.

**Current branch — can't be refspec-updated** (git won't let you fetch into the branch you're on). Use:

```
git pull --ff-only
```

`--ff-only` aborts (changes nothing) if the pull isn't a clean fast-forward. Gate it on a **clean working tree**: if `git status --porcelain` shows modified or staged *tracked* files, skip and flag — a pull onto dirty tracked files can fail or surprise. Untracked-only files are fine.

**Reading outcomes — never lie about what happened:**
- Refspec accepted → report `branch: oldSHA → newSHA` under SYNCED.
- Refspec `! [rejected]` or `git pull --ff-only` "Not possible to fast-forward, aborting" → report under FLAGGED as "skipped: diverged," **never** as synced.
- Always parse the actual output/exit code; don't assume success.

**Worktree-pinned branches** (`+` in `git branch -vv`) error if you try to refspec-update them — skip them entirely and flag.

---

## Active vs stale: the classification table

Kyle's rule: pull active branches (main, dev, live chore/fix/feature); flag everything else. Operationalized, "active" needs every condition true. Gather once with:

```
git for-each-ref --format='%(refname:short)|%(committerdate:unix)|%(upstream:short)|%(upstream:track)' refs/heads
gh pr list --state merged --json headRefName
git branch -vv
```

| Branch state | Action | Why |
|---|---|---|
| `main` / `dev_branch`, behind-only, clean | **PULL** (ff) | Integration branches — always kept current regardless of age |
| `^(feat\|feature\|fix\|chore)/…`, has upstream, behind-only, not merged, within window | **PULL** (ff) | Live feature work that's simply behind origin |
| Diverged (ahead **and** behind) | **FLAG** | Fast-forward impossible; needs Kyle's merge/rebase decision |
| Ahead-only (unpushed local commits) | **FLAG** | Nothing to pull; Kyle may want to push |
| No upstream | **FLAG** | Nothing to sync against; never invented |
| Upstream `[gone]` | **FLAG** | Remote branch deleted — merged or abandoned; cleanup is Kyle's call |
| Merged into default (incl. squash) | **FLAG** | Work already landed; candidate for deletion, not syncing |
| Stale (last commit older than `active_window_days`) | **FLAG** | Dormant; pulling it adds noise, not value |
| Worktree-pinned (`+`) | **FLAG / SKIP** | Checked out elsewhere; refspec update errors |
| Detached HEAD | **SKIP all sync** | No branch to sync; re-attach first |

`active_window_days` defaults to 14, matching the skill's existing ">1 week" staleness heuristics. **When a branch is ambiguous, FLAG, don't PULL** — the cost of flagging is a line of output; the cost of a wrong pull is eroded trust.

Squash-merge detection matters: `git branch --merged` misses squash-merged branches because their commits never appear verbatim on the default branch. `gh pr list --state merged` (match on `headRefName`) catches them.

---

## First-run config & gitignore

The per-repo config `.claude/preflight.yml` holds answers (default branch, naming, window) that are **local choices, not shareable repo state** — so it's always gitignored. The `.gitignore` *rule* that protects it, however, belongs in the repo so the protection is permanent and applies to every clone. (Precedent in this very repo: commit `efa9cb9 "chore: ignore .claude/preflight.yml"`.)

**Order of operations matters.** Add the ignore rule *before* creating the config file. If you create the config first, git briefly sees it as an untracked, stageable file — and a careless `git add .` would commit a file full of local preferences.

**The commit, and why not amend.** "Add it to the newest commit" means a **new** commit on top — `git commit -m "chore: ignore .claude/preflight.yml"` — **not** `git commit --amend`. Amend rewrites the last commit's SHA; if that commit is already pushed (and on a repo in sync with origin it is), amending forces a force-push to reconcile. Force-push is the single reflex a git-teaching tool must never model. New commit, always.

**Stage surgically.** `git add .gitignore` only — never `git add -A` or `git add .`. Committing the config file must be structurally impossible, not merely avoided.

**Clean-tree guardrail.** Auto-committing is only appropriate when the working tree is otherwise clean. If Kyle has other staged or modified work, dropping a `chore:` commit into the middle of it is surprising and muddies his history. In that case: write the rule, stage `.gitignore`, and tell him the one command to run when he's ready. Fast-forward pulls run without a prompt; this commit (which touches shared history) is the gated step.

**Idempotency.** `git check-ignore -q .claude/preflight.yml` returns exit 0 when the file is already ignored. If so, do nothing — no duplicate line, no empty commit. Steady-state runs (the common case) stay completely write-free for the gitignore concern.

**Already-tracked edge case.** If `git ls-files` shows the config is already tracked, adding it to `.gitignore` will **not** untrack it — gitignore only affects untracked files. Flag this to Kyle (`git rm --cached .claude/preflight.yml` removes it from tracking while keeping the local file), but don't run it silently; it's a state he should understand.

---

## Files that look out of place

When `git status` shows untracked files, classify each before mentioning. Some categories are unambiguous and worth flagging actively; others are routine and don't need a recommendation.

**Worth flagging actively (potentially harmful or definitely accidental):**

- **Secrets and env files** (`.env`, `.env.local`, `.env.production`, `credentials.json`, `*.pem`, `*.key`): Never commit these. If one shows up untracked, it's probably fine — gitignore is doing its job. If one is *tracked* (caught in Step 6 of the workflow), that's a different problem entirely. See "Secrets and sensitive files" below.

- **Zero-byte files with weird names** (single characters like `-`, names with unprintable characters): Almost always from an accidental shell redirect (`command > -`) or typo. Recommend deletion. To delete a file named `-`, use `rm ./-` (the `./` prevents `rm` from treating the dash as a flag).

- **Files in unexpected locations** (e.g., a `.bak` file in source code, a screenshot in the project root): Worth asking Kyle if intentional.

**Routine, don't need recommendations:**

- Build artifacts and dependencies (`node_modules/`, `dist/`, `build/`, `.next/`): Should be in `.gitignore`. If they're untracked, gitignore is working.
- OS cruft (`.DS_Store`, `Thumbs.db`): Should be in a global gitignore. If they show up here, mention briefly.
- Editor files (`.vscode/`, `.idea/`): Team convention — some teams commit shared settings, some don't. Not preflight's call.

The skill is observational, not janitorial. Surface what's notable; let Kyle decide what to clean.

---

## Diverged default branch

When `git rev-list --left-right --count <default>...origin/<default>` returns `N M` with both numbers > 0, the default branch has split. This matters more than divergence on a feature branch because the default is the base for new work.

**Why it usually happens:**
1. Someone (often Claude Code in a previous session) committed directly to local default and never pushed. Meanwhile, teammates merged PRs to remote default.
2. History was rewritten on remote (force-push). Rare on protected branches but possible.

**Step 1: Get the data.**

```
git log @{u}..HEAD --oneline       # local-only commits on default
git log HEAD..@{u} --oneline       # remote-only commits on default
```

**Step 2: Characterize the local-only commits.**

- **Small commits with generic messages** ("fix", "wip", session handoff files, README typos): likely accidental commits to the wrong branch. Should probably not be on default.
- **Substantive commits with meaningful messages**: real work that escaped the PR process somehow. Needs care.
- **Commits Kyle doesn't recognize**: investigation needed before any action.

**Step 3: Recommend (but don't act).**

For accidental commits to default:
> "Your local main has <N> commits that look like they shouldn't be on main — most teams keep main for merged PRs only, and these look like session-handoff or work-in-progress commits. Most likely path: reset local main to match origin (`git reset --hard origin/main`), then if any of those commits are worth keeping, redo them as a proper PR. Tag a safety anchor first (`git tag preflight-safe-<timestamp>`) so you can rewind if needed. **You'd run that — I won't.**"

For substantive work that escaped PR process:
> "Your local main has <N> commits of real work that aren't on origin. Two paths: (a) move them to a feature branch first (`git branch save-work main` then reset and redo as PR), or (b) push directly to main if your team allows that (most don't). Worth deciding which and talking to Martina if you're not sure. **Don't reset until the work is preserved somewhere.**"

For matching commit messages but different SHAs (suggests force-push on remote):
> "I see suspicious patterns — commits with the same messages but different IDs on each side. That usually means history was rewritten on the remote. **Stop here and ask Martina.** Fixing this wrong can lose work or create a tangle."

---

## Rebase vs merge

When integrating commits from one branch into another (e.g., catching up a feature branch with main), there are two strategies. They produce different history shapes.

**Rebase** replays your branch's commits on top of the target. Result: linear history, your branch looks like it started from the latest target.

```
Before:
  main:    A---B---C
                \
  feature:       D---E

After rebasing feature onto main:
  main:    A---B---C
                    \
  feature:           D'---E'
```

`D'` and `E'` are *new* commits with new SHAs. They're copies of the originals.

**Merge** creates a merge commit that ties two branches together. Result: history shows the branching and reconvergence.

```
Before:
  main:    A---B---C
                \
  feature:       D---E

After merging main into feature:
  main:    A---B---C
                \   \
  feature:       D---E---M
```

`M` is a merge commit with two parents.

**When to use which:**

| Situation | Recommendation |
|---|---|
| Solo feature branch, prepping for PR | Rebase (cleaner PR review) |
| Branch where multiple people commit | Merge (rebase rewrites SHAs and breaks their clones) |
| Catching up feature branch mid-work | Team convention — ask Martina if you don't know |
| Integrating feature back into main | Use GitHub's PR merge button, choose the team's convention there |

**The golden rule:** never rebase commits that have been pushed and that others might have based work on. Rebasing rewrites SHAs; if someone else has the originals, you'll create conflicts for them.

---

## When to clean up vs when to leave it

Preflight surfaces things that *could* be cleaned up: merged branches that are still around, old stashes, files that probably shouldn't be tracked. The skill doesn't recommend cleanup as a blocker — it surfaces them and lets Kyle decide.

**Clean up before starting new work if:**
- The clutter is actively in your way (e.g., a stale stash on the current branch confuses git status).
- The clutter is a security risk (tracked secrets, exposed env files).
- The default branch state is wrong (diverged, behind) and would affect new branches.

**Leave it for later if:**
- It's just bookkeeping (old merged branches taking up no real space).
- The cleanup is risky and you're not in a careful headspace.
- You came here to start coding, not to garden the repo.

A useful question: "If I ignore this for two more weeks, does it get worse, stay the same, or fix itself?"
- Gets worse: handle now (security issues, growing PR backlog, default branch divergence).
- Stays the same: defer (old stashes, merged branches without PRs).
- Fixes itself: leave entirely.

---

## Managing your PR backlog

Open PRs are commitments. Each one represents work that needs to either land or be closed. Carrying a large backlog has costs:

- Mental overhead — every PR is a thing to remember.
- Merge conflicts grow as the PR ages relative to main.
- Reviewers lose context the longer they wait.
- Team trust erodes when PRs sit ignored.

**Healthy patterns:**
- 1-3 of your own PRs open at a time.
- No PR sitting >1 week without action from your side when your action is needed.
- Stalled PRs get a decision (push forward, close, or convert to draft) within 2 weeks.

**Warning signs preflight might flag:**
- 4+ open PRs by Kyle simultaneously.
- A PR with "changes requested" sitting >1 week.
- A PR with no review activity >2 weeks (might need to nudge the reviewer or scope it down).
- A draft PR >3 weeks old (probably forgotten — close or commit to finishing).

**The skill's job:** surface the backlog state. Recommend addressing it before adding more work. **Kyle's job:** decide what to do.

If the backlog is genuinely large (5+ stalled PRs), preflight should suggest a "PR triage" session before more new work. Not enforce, just flag.

---

## Detached HEAD

Normal state: HEAD → branch → commit. You make commits; the branch pointer moves forward.

Detached state: HEAD → commit directly, no branch in between. You make commits, but nothing points to them after HEAD moves elsewhere.

**Causes:**
- `git checkout <sha>` — looking at an old commit
- `git checkout <tag>` — looking at a tagged release
- `git checkout origin/main` — checking out a remote branch reference directly
- Some clone options

**Why it matters:** commits made in detached state become unreachable when you switch branches. Unreachable commits are eventually garbage-collected (typically 30-90 days, depending on git's gc settings — don't rely on the window).

**How to recover:**
- If you haven't committed anything yet: just `git switch <branch>` to attach to a normal branch.
- If you've made commits and want to keep them: `git switch -c <new-branch-name>` to create a branch at your current position. The commits become safe.

**For preflight:** if Kyle is in detached state at session start, it's almost always accidental. Explain what it means in one sentence, recommend re-attaching, let him do it.

---

## Secrets and sensitive files

If preflight finds a tracked file (not just untracked) that contains secrets — API keys, database URLs, tokens, private keys, credentials — this is serious.

**Important:** removing the file and committing doesn't remove it from history. The secret is still retrievable by anyone with repo access. Anyone who has cloned the repo since the secret was committed has it.

**The skill's role:**

1. Flag the file clearly. Don't echo the secret itself in chat output.
2. Tell Kyle what kind of secret it appears to contain (API key, DB URL, etc.).
3. Tell Kyle the immediate priority: **rotate the secret now.** Whatever it is, it must be considered compromised. Change it in the provider's dashboard before doing anything else.
4. Tell Kyle that history cleanup is a separate, harder problem that needs Martina (or `git-filter-repo` / BFG with care). Don't attempt it.

**Never:**
- Run `git filter-branch`, `git filter-repo`, or BFG yourself.
- Force-push.
- Pretend the problem is smaller than it is.

If you find this in a preflight session, the verdict moves to 🛑 — not because new work is technically blocked, but because secret rotation is more urgent than coding.

---

## Common confusions worth explaining once

When Kyle hits these for the first time in a session, take 1-2 sentences to explain. Don't lecture, but don't skip:

**`origin/main` vs `main`:** `main` is your local branch. `origin/main` is your last-fetched view of GitHub's main. They can differ — that's what `fetch` updates. They diverge if either side gets new commits without syncing.

**`HEAD`:** A pointer to "where you are right now." Usually points to a branch, which points to a commit. Sometimes points directly to a commit (detached HEAD).

**`@{u}` (upstream):** Shorthand for "the remote branch this local branch is tracking." So `HEAD...@{u}` means "current branch vs its remote tracking branch."

**Fast-forward (`--ff-only`):** A fast-forward is when your branch is strictly behind the target — you can just slide your pointer forward without making any merge commit. `--ff-only` means "only do this if it's a clean fast-forward; refuse otherwise." Refusing is good — it prevents surprise merge commits.

**Reflog:** A local log of where HEAD has been recently. If you reset or rebase and lose track of a commit, `git reflog` can find it. Retention is typically 30-90 days, set by `gc.reflogExpire`.

**Worktree:** A separate working directory for the same repository, with its own checked-out branch. Useful for working on multiple branches in parallel without constantly switching. Kyle uses these for his multi-agent setup. Branches checked out in another worktree show up with `+` in `git branch -vv` output.

---

## Worktrees and branch safety

Kyle uses git worktrees for his multi-agent setup (Beacon, Blueprint, Folio, Scout, Scribe, Ledger). Each worktree is a separate directory with its own checked-out branch, sharing the same `.git` database.

**For preflight:**

- `git branch -vv` shows worktree-checked-out branches with a `+` prefix:
  ```
    main                  abc123 [origin/main]
  + feat/beacon-updates   def456 [origin/feat/beacon-updates]
    feat/old-stuff        xyz789 [gone]
  ```

- **Never recommend deleting a branch with `+`.** It's actively checked out in another directory. Deleting would break that worktree.

- `git worktree list` shows all worktrees. Useful context if Kyle wants to see what's where.

When recommending branch cleanup (which preflight rarely does), filter:
```
git branch --merged <default> | grep -vE '^\*|^\+'
```
The `^\*` excludes the currently checked-out branch. The `^\+` excludes worktree-checked-out branches.

---

## When to escalate to Martina

Preflight is a teaching tool, not a fix-everything tool. Some situations need someone who knows the team's history and conventions deeply. Tell Kyle to bring Martina in when:

1. **History has been rewritten on remote.** Matching commit messages with different SHAs.
2. **Secrets are in committed history.** Rotation is Kyle's immediate job. Cleanup is Martina's.
3. **Branches or commits exist that Kyle doesn't recognize.** Investigation needed before action.
4. **Kyle wants to force-push.** Preflight never recommends this.
5. **Conflicts span many commits or many files.** Preflight doesn't do conflict resolution.
6. **The repo state is weird in ways the skill can't explain.** When in doubt, stop.

How to escalate:

> "This one is past what I should help with directly. Here's what I see: <summary>. Here's why I'm flagging it: <reason>. Worth bringing to Martina with this summary. I'll wait."
