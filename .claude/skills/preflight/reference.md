# preflight Reference

Load sections of this file on demand when the main skill flags a situation that needs deeper reasoning. Pull the specific section relevant to the current question — don't load the whole file at once.

The tone of every section is *teaching*, not lecturing. Kyle is a smart adult learning git through these sessions. Explain the concept, give the reasoning, share the recommendation, and let him decide.

---

## Auto-sync mechanics: refspec ff vs pull

Step 4 brings active branches up to date **without ever leaving the current branch or making a merge commit**. Two mechanics, by branch.

**First, only sync to the real upstream.** A branch is eligible only if its upstream is exactly `origin/<same-name>` (from `%(upstream:short)`). A branch tracking `upstream/foo`, a fork remote, or a differently-named origin branch is **flagged, never synced** — otherwise a "fast-forward" could quietly move it to a *different* ref than the one its status was computed against.

**Non-current branches — fast-forward the ref in place via a fetch refspec:**

```bash
# build each fully-qualified refspec as a SEPARATE argument — never one interpolated string:
refspecs=()
for b in "${active_noncurrent[@]}"; do refspecs+=("refs/heads/$b:refs/heads/$b"); done
git fetch --no-tags origin "${refspecs[@]}"
```

Pass refspecs as **separate quoted arguments** (`refs/heads/x:refs/heads/x`), fully-qualified so there's no tag ambiguity. Quoting alone isn't enough — a branch name can contain `'`, `;`, `|`, or `$`, so treat names as **data**, never splice them into a command string; if a name has characters that can't be passed cleanly, **skip and flag** it. `--no-tags` keeps local tags from being moved (the charter forbids renaming a tag). Build the list **only** from `git for-each-ref` output, **excluding the current branch** (fetching into the checked-out branch is a *fatal* error that aborts the whole batch — `fatal: refusing to fetch into branch ... checked out`) and **excluding worktree-pinned branches** (same error). Never invent `dev:dev` if no local `dev` exists — that *creates* a branch, which the charter forbids.

The critical safety property: **git refuses to update a local branch ref unless the move is a clean fast-forward.** A rejected ref looks like:

```text
 ! [rejected]   main -> main (non-fast-forward)
```

…and that ref is left unchanged. **Never** prefix a refspec with `+` and never pass `--force` — that's what would turn a safe no-op into a destructive overwrite. A batched fetch is **not atomic**: `main` can fast-forward while `dev` is rejected in the same command, so parse per-ref and verify each branch's old→new SHA — never infer "all synced" from one exit code.

Why not check out each branch and `git pull`? Checkout mutates the working tree, fails on uncommitted changes, can conflict, and is slow. Refspec ff touches only the ref pointer.

**Current branch — can't be refspec-updated** (git won't fetch into the branch you're on). Only if its upstream is `origin/<current>` and the tree is not tracked-dirty:

```bash
git merge --ff-only @{u}
```

`@{u}` is the current branch's upstream; `merge --ff-only` aborts (changing nothing) on divergence and — unlike `git pull` — isn't swayed by `pull.rebase` config. Don't pre-screen for untracked-file collisions; just attempt the merge and treat **any** non-zero exit (divergence, or an untracked file colliding with an incoming tracked path) as "skipped: could not fast-forward," not as synced.

**Reading outcomes — never lie about what happened:**
- Ref accepted / merge succeeded → report `branch: oldSHA → newSHA` under SYNCED.
- `! [rejected]`, `fatal:`, or `merge --ff-only` abort → report under FLAGGED as "skipped: diverged," **never** as synced.
- Always parse the actual output/exit code; don't assume success.

---

## Active vs stale: the classification table

Kyle's rule: pull active branches (main, dev, live chore/fix/feature); flag everything else. Operationalized, "active" needs every condition true. Gather once (after `git fetch --prune --no-tags origin`) with:

```bash
# NUL field/record separators so names with | or newlines parse safely:
git for-each-ref --format='%(refname:short)%00%(committerdate:unix)%00%(upstream:short)%00%(upstream:track)%00%00' refs/heads
git branch --merged "origin/<default>"        # ancestry-based merged detection
git worktree list --porcelain                  # machine-readable worktree-pinned detection
# if gh available + authed, also catch squash-merges:
gh pr list --state merged --base "<default>" --limit 200 --json headRefName
```

| Branch state | Action | Why |
|---|---|---|
| `main` / `dev_branch`, upstream `origin/same`, behind-only | **PULL** (ff) | Integration branches — always kept current regardless of age |
| Matches `active_prefixes`, upstream `origin/same`, behind-only, not merged, within window | **PULL** (ff) | Live feature work that's simply behind origin |
| In sync (`[behind 0]` / no track marker) | **none** | Already current — report as "current," not flagged |
| Diverged (ahead **and** behind) | **FLAG** | Fast-forward impossible; needs Kyle's merge/rebase decision |
| Ahead-only (unpushed local commits) | **FLAG** | Nothing to pull; Kyle may want to push |
| No upstream / upstream not `origin/<same>` | **FLAG** | Nothing safe to sync against; never auto-pull a fork/renamed upstream |
| Upstream `[gone]` | **FLAG** | Remote branch deleted — merged or abandoned; cleanup is Kyle's call |
| Merged into default (ancestry or merged-PR) | **FLAG** | Work already landed; candidate for deletion, not syncing |
| Stale (last commit older than `active_window_days`) | **FLAG** | Dormant; pulling it adds noise, not value |
| Eligible but name not in `active_prefixes` | **FLAG** | All other criteria met, but a single-pass briefing can't pause to ask mid-run — surface it and offer to add the prefix to config for next time; don't pull this run |
| Worktree-pinned (in `git worktree list`, path ≠ this worktree) | **SKIP** | Checked out elsewhere; refspec update errors |
| Detached HEAD | **SKIP all sync** | No branch to sync; re-attach first |

`active_window_days` defaults to 14 (~two-week window); note this is wider than the 7-day PR-backlog threshold — they measure different things. A name is "in `active_prefixes`" only if it begins with `<prefix>/` (the `/` boundary is required — `feature-x` does not match `feat`). **When a branch is ambiguous, FLAG, don't PULL** — the cost of flagging is a line of output; the cost of a wrong pull is eroded trust.

Two merged-detection passes, because each misses cases the other catches: `git branch --merged origin/<default>` finds normally-merged branches via ancestry but **misses squash-merges** (their commits never appear verbatim on default); `gh pr list --state merged --base <default>` catches squash-merges that went through a PR. A branch squash-merged *locally* with no PR is detectable by neither — a known limitation; when in doubt, flag.

---

## Per-user config & migration

**Why the config lives outside the repo.** The config (default branch, naming, window) holds **local, per-machine choices, not shareable repo state.** Earlier versions (≤4.2) kept it at `.claude/preflight.yml` *inside* the repo and tried to protect it with a committed `.gitignore` rule. That created a recurring failure mode: in repos where the file got committed before the rule existed, every run re-flagged "your config is committed, you should untrack it." From v5.0 the config lives at `~/.claude/preflight/<repo-key>.yml` — outside every repo. Nothing is written into the working tree, so there is no rule to add, nothing to stage, and **nothing to commit, ever**. The nag is structurally impossible.

**The repo key** is a readable `stem` plus a 12-char (48-bit) hash: `<stem>-<hash12>`. Both come from a *canonical* identity — the origin URL lowercased with protocol, `user@`, trailing `.git`, and trailing slash stripped (so `git@github.com:Foo/bar.git`, `https://github.com/foo/bar`, and `…/bar/` all canonicalize to `github.com/foo/bar`). The stem is that canonical string with non-`[a-z0-9._-]` collapsed to `-`; the hash is `shasum` of the canonical string (`sha1sum` fallback — same SHA-1, so the key is stable whichever tool the machine has). Example: `git@github.com:My-Stacks/claude-code-skills.git` → `github.com-my-stacks-claude-code-skills-<hash12>`. **Why the hash:** the stem alone is lossy — `org/repo` and `org-repo` both collapse to `org-repo`, which would silently share one config; the hash of the canonical form keeps genuinely different remotes apart. The key never contains `/`, so it always names a single file directly under `~/.claude/preflight/`. No origin → the canonical is the repo's absolute path. Worktrees and clones of one origin share a key — intended; per-repo settings shouldn't differ between them.

**Steady state is read-only.** If `~/.claude/preflight/<key>.yml` exists, read it and move on. Once it exists, **never look at any in-repo `.claude/preflight.yml` again** — that single rule is what guarantees the legacy message appears at most once per repo, then never returns.

**Migration (one time per repo).** On the first v5.0 run, if `$cfg` doesn't exist yet but a legacy `.claude/preflight.yml` is present in the repo, copy it **byte-for-byte** (`cp --`, not a parse-and-rewrite) to `$cfg` and tell Kyle once that the config has moved — but first sanity-check the source (anchored at `$root`, since preflight may run from a subdirectory): treat it as absent unless it is non-empty and has a `default_branch:` key *with a value*, allowing leading indentation (`grep -Eq '^[[:space:]]*default_branch:[[:space:]]*[^[:space:]#]'`). A truncated or valueless file never becomes the permanent source of truth. Migration is **one-way**: once `$cfg` exists it's authoritative and the in-repo file is never read again, so post-migration edits belong in `$cfg`. If that in-repo file is **tracked** (`git ls-files --error-unmatch .claude/preflight.yml` exits 0), add a one-time *optional* cleanup note — framed as housekeeping, never a blocker, never run by the skill — and run it from an otherwise-clean tree, scoped by pathspec so nothing unrelated rides along:

```bash
git rm --cached .claude/preflight.yml          # stop tracking; keeps your local copy
grep -qxF '.claude/preflight.yml' .gitignore 2>/dev/null || echo '.claude/preflight.yml' >> .gitignore
git add .gitignore
git commit -m "chore: stop tracking .claude/preflight.yml" -- .claude/preflight.yml .gitignore
```

Whether or not Kyle runs them, the next run finds `$cfg` and skips the in-repo file entirely — so the note never repeats. `git rm --cached` only removes the file from git's index; the on-disk copy stays (and is now ignored, harmless). **The skill never runs these itself** — removing a tracked file and making a commit are Kyle's call. The skill's own writes are confined to `~/.claude/preflight/`.

---

## Files that look out of place

When `git status` shows untracked files, classify each before mentioning. Some categories are unambiguous and worth flagging actively; others are routine and don't need a recommendation.

**Worth flagging actively (potentially harmful or definitely accidental):**

- **Secrets and env files** (`.env`, `.env.local`, `.env.production`, `credentials.json`, `*.pem`, `*.key`): Never commit these. Preflight only *sees* these when they appear as untracked files in Step 2 — distinguish: untracked **and** ignored is fine (gitignore doing its job); untracked **and not** ignored is worth flagging. Preflight does **not** actively scan *tracked* files for secret content (out of scope) — but if Kyle points one out, see "Secrets and sensitive files" below. The verdict's 🛑 "secrets in tree" applies when such a file is surfaced, not from an automated scan.

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

```bash
git log @{u}..HEAD --oneline       # local-only commits on default
git log HEAD..@{u} --oneline       # remote-only commits on default
```

**Step 2: Characterize the local-only commits.**

- **Small commits with generic messages** ("fix", "wip", session handoff files, README typos): likely accidental commits to the wrong branch. Should probably not be on default.
- **Substantive commits with meaningful messages**: real work that escaped the PR process somehow. Needs care.
- **Commits Kyle doesn't recognize**: investigation needed before any action.

**Step 3: Recommend (but don't act).**

> Every command in this section is a **suggestion for Kyle to run**. The charter forbids the skill from running `reset`, `tag`, branch creation, or any history rewrite — show the commands and the reasoning; Kyle types them.

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

```text
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

```text
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

**How to recover** (these are commands for **Kyle to run** — branch switch/create are charter-forbidden for the skill; show them, don't execute them):
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

- **Detect worktree-pinned branches from machine-readable output**, not by parsing `git branch -vv`. The `+` marker is real but column/spacing parsing is fragile; use:

  ```bash
  git worktree list --porcelain   # records: 'worktree <path>' then 'branch refs/heads/<name>'
  ```

  `--porcelain` emits a record for **every** worktree, including the one preflight is running in. A branch is pinned *elsewhere* only when its `branch` line belongs to a `worktree <path>` that is **not** this run's `git rev-parse --show-toplevel` (Step 1). Don't treat every `branch` line as pinned — that would wrongly mark the current branch as pinned and skip its own sync.

  For a quick human glance, `git branch -vv` shows the pinned ones with a `+`:

  ```text
    main                  abc123 [origin/main]
  + feat/beacon-updates   def456 [origin/feat/beacon-updates]
    feat/old-stuff        xyz789 [gone]
  ```

- **Never refspec-sync or recommend deleting a worktree-pinned branch.** It's actively checked out elsewhere — a refspec update errors, and deleting breaks that worktree.

When *recommending* branch cleanup (a suggestion for Kyle to run — the skill never deletes), filter the current and pinned branches out:

```bash
git branch --merged <default> | grep -vE '^[*+]'
```

The leading `*` (current) and `+` (worktree-pinned) markers both sit at the start of the line, so `^[*+]` drops both. Deletion itself (`git branch -d`) is Kyle's command, never the skill's.

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
