---
name: preflight
version: "5.2"
description: >-
  Pre-session safe-sync briefing for git repos. Brings the repo up to date
  before work begins — fast-forwards active branches to origin, flags stale
  ones — then reports local state, open PRs, and where new work should branch
  from. Performs only safe, non-destructive writes (ff-only sync); config is
  stored per-user outside the repo and never committed. Narrates each write
  before it runs. Never rewrites history, never makes a decision that's Kyle's.
  Teaches the reasoning so Kyle learns git.
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
- Create / update the per-user config under `~/.claude/preflight/` (outside the repo — never touches the working tree, never staged, never committed). See Step 3.
- Write the session-start baseline `~/.claude/preflight/<repo-key>.session-start.json` (same location and the same guarantees; read by `/mise-en-place` at closedown). See Step 3.

**NEVER**:
- Non-fast-forward merge, rebase, force-push, reset, cherry-pick.
- Create, switch, delete, or rename a branch or tag. (Branch-switch/create commands shown to Kyle are **suggestions he runs**, never executed by the skill.)
- **Commit anything, ever, to any repo** — not config, not `.gitignore`, not a stray file. The skill makes zero commits. Never `git add -A`/`git add .`; never write any file into the repo working tree. (Config lives outside the repo; see Step 3. The cleanup commit in Step 3 is a **suggestion Kyle runs**, never executed by the skill — same carve-out as the branch-switch commands.)
- Push Kyle's commits.
- Pull or modify a **stale, diverged, ahead-only, or no-upstream** branch, or any branch whose upstream is not `origin/<same-name>` (flag only).
- Fast-forward the **current** branch while the tree is **tracked-dirty** — skip and flag. (Fetching remote-tracking refs and fast-forwarding *non-current* branches don't touch the working tree, so those stay allowed; see Step 2 for the exact rule. Writing the per-user config is always safe — it's outside the repo.)
- Interpolate a branch name into a shell command string. Branch names are **data** — pass them as separate quoted arguments, never concatenated into a command (a name can contain `'`, `|`, `;`, `$`).

If a situation isn't clearly inside "MAY," it's a recommendation, not an action.

## Operating principles

1. **Safe writes only, always narrated.** Before any fast-forward or commit, say what you're about to do and why in plain language. After, confirm what moved. Anything outside the charter stays a recommendation Kyle runs himself.
2. **Teach with every action and recommendation.** Kyle is learning git. Skip the lecture, never skip the reasoning.
3. **Evidence over opinion.** Not "best practices suggest X." Instead "this PR has been open 3 weeks with no review activity — worth deciding before starting new work."
4. **Decisions stay with Kyle.** Risky or judgment calls (merges, divergence, deletions, rotation) end with what Kyle should consider — never "I'll proceed."
5. **Plain-language git terms.** First time per session you use a term Kyle might not know fluently (upstream, HEAD, fast-forward, refspec, ff-only, reflog), parenthetically explain it.
6. **Know what's out of scope.** No conflict resolution, history rewriting, or secret cleanup. Point Kyle to his existing workflow or to Martina.

## Per-repo config

Config is **per-user and lives outside the repo**, at `~/.claude/preflight/<repo-key>.yml`. It is never created in the repo, never staged, never committed — so it can never show up as a tracked file or a "you should gitignore this" nag. The config holds local choices (default branch, naming, window), which are per-machine preferences, not shareable repo state. See Step 3 for how the key is derived and how a legacy in-repo config is migrated.

```yaml
default_branch: main           # main | master | develop
dev_branch: dev                # optional integration branch; omit if none
protected_branches: [main]     # never recommend deleting, even if merged
branch_naming: kebab-feature   # how new branches should be named (descriptive answer)
active_window_days: 14         # branches with commits newer than this are "active"
active_prefixes: [feat, feature, fix, chore]  # branch prefixes eligible for auto-sync
```

`active_window_days` defaults to 14 (a ~two-week window). `main` and `dev_branch` are **always** treated as active regardless of age.

**Resolving the real default branch** (don't blindly trust the config — the remote is authoritative): try in order, stop at the first that resolves to an existing `origin/<name>`:
1. `git symbolic-ref -q --short refs/remotes/origin/HEAD` (strip the `origin/` prefix),
2. the configured `default_branch` if `origin/<default_branch>` exists,
3. `main`, then `master`, then `develop`.
If none resolve, skip default-based merged detection and report "remote default unknown."

## The workflow

Run these steps in order. Writes happen only where the charter allows, only after narrating, and only after the preconditions in Steps 1–2 pass.

### Step 1: Location & preconditions

```bash
git rev-parse --is-inside-work-tree
git rev-parse --show-toplevel          # remember this — "this worktree" for Step 4
git remote -v
git symbolic-ref -q HEAD               # non-zero exit => detached HEAD (works on all git)
git branch --show-current              # branch name (empty => detached); needs git ≥ 2.22
```

Report which repo, remote, branch, attached or detached. Use `symbolic-ref` for the detached check (`git branch --show-current` predates git 2.22 and is silently absent on old git, which would make every state look detached). This step gates **all later writes**:

- **Not in a repo** (`--is-inside-work-tree` non-zero): stop. Tell Kyle to cd into a repo and re-run. **No writes.**
- **No `origin` remote** (`git remote | grep -qx origin` fails): no git-side writes — skip all of Step 4's syncing and report "no `origin` — nothing to sync against." Step 3 still runs (the per-user config is keyed on the repo path when there's no origin, and lives outside the repo).
- **Detached HEAD** (`git symbolic-ref -q HEAD` non-zero): explain in one sentence ("you're viewing a specific commit, not attached to any branch — work here won't automatically belong anywhere"), recommend re-attaching. **Do not switch, do not sync.**
- **Unborn/empty repo** (no commits yet): report it; skip Step 4 sync.

### Step 2: Working tree state

```bash
git status --porcelain
git stash list --format='%gd|%cr|%s'
```

Report modified / staged / untracked / stashes, one line each. **Define cleanliness once and reuse it:**

- **tracked-dirty** = any `git status --porcelain` line NOT beginning with `??` (staged or modified tracked files). This blocks exactly one write: the **current-branch fast-forward** (Step 4), which touches the working tree. It does **not** block `git fetch` (remote-tracking refs only), fast-forwarding *non-current* branches (their refs move; your working tree doesn't), or writing the per-user config (it lives outside the repo). The skill never stages or commits anything, so a dirty tree is never at risk of being swept into a commit.
- **untracked-only** = output is empty or every line begins with `??`. Writes may proceed (but see the untracked-collision note in Step 4).

Also: flag untracked files matching "shouldn't be here" patterns (`.env`, zero-byte odd names, accidental redirects) — load `reference.md → "Files that look out of place"`. Stashes older than 8 weeks: mention as a future cleanup pass, not a blocker.

### Step 3: Per-user state — config + session baseline (outside the repo)

Config lives at `~/.claude/preflight/<repo-key>.yml` — **never in the repo**. Because nothing is written into the working tree, there is no `.gitignore` rule to add, nothing to stage, and nothing to commit. The skill makes **zero** commits. This is what stops the recurring "your config is committed / should be gitignored" message: there is no in-repo file to track.

**1. Derive the repo key** (stable per repo, shared across that repo's worktrees):

```bash
: "${HOME:?preflight: HOME is unset — refusing to write to /}"
mkdir -p "$HOME/.claude/preflight"
root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "preflight: not in a git repo"; exit 1; }
raw=$(git remote get-url origin 2>/dev/null | head -1)   # origin identity (1st line only)
[ -z "$raw" ] && raw=$root                               # no origin → repo path
# canon: lowercase, strip protocol / user@ / trailing .git / trailing slash; ssh and https
# forms of one repo converge here, while org/repo vs org-repo stay distinct.
canon=$(printf '%s' "$raw" | tr 'A-Z' 'a-z' \
  | sed -E 's#^[a-z]+://##; s#^[^@/]+@##; s#:#/#; s#/+$##; s#\.git$##; s#/+$##')
stem=$(printf '%s' "$canon" | tr -c 'a-z0-9._-' '-' | sed -E 's#-+#-#g; s#^[-.]+##; s#[-.]+$##')
hash=$(printf '%s' "$canon" | { shasum 2>/dev/null || sha1sum 2>/dev/null; } | cut -c1-12)
case "$hash" in [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
  *) echo "preflight: no working shasum/sha1sum — cannot key config safely"; exit 1 ;; esac
key="${stem:-repo}-${hash}"          # readable stem + collision-resistant hash; stem may be empty
cfg="$HOME/.claude/preflight/${key}.yml"
```

Origin `git@github.com:My-Stacks/claude-code-skills.git` → key `github.com-my-stacks-claude-code-skills-<hash12>`. No origin → keyed on the repo's absolute path (`$root`). The readable `stem` is **lossy** (slashes, colons, and other characters all collapse to `-`, so `org/repo` and `org-repo` would otherwise share a file) — the 12-char (48-bit) hash of the *canonical* identity is the real key, so two genuinely different remotes effectively never collide. Because the hash is computed from `canon`, the ssh and https URLs of the same repo (and a trailing-slash variant) all resolve to the **same** config; worktrees and clones of one origin share it too — all intended. (The key never contains `/` — `tr` maps every separator to `-` — so it always names a single file directly under `~/.claude/preflight/`, never a path that could escape it.)

**2. If `$cfg` exists → read it, skip sub-step 3, and continue to sub-step 4.** Steady-state runs do exactly this: read the per-user config, leave the session-start baseline, and move on. **Do not stop here** — sub-step 4 runs on every preflight, and skipping it is what silently disables tonight's closedown. **Never inspect the in-repo `.claude/preflight.yml`** once `$cfg` exists — that's what guarantees the legacy nag fires at most once, ever. **Migration is one-way:** once `$cfg` exists it is the *only* source of truth, so edits made to a leftover in-repo file afterward are silently ignored. To change settings, edit `$cfg` directly (tell Kyle its path).

**3. If `$cfg` does NOT exist, migrate or create:**

   - **Legacy in-repo config present** (`$root/.claude/preflight.yml` exists from an older version — anchor to `$root`, not a relative path, since preflight may be invoked from a subdirectory): copy it **byte-for-byte** to `$cfg` — `cp -- "$root/.claude/preflight.yml" "$cfg"`, don't parse or re-serialize it (that would drop comments, ordering, and any field this version doesn't recognize). **But first sanity-check it:** treat it as absent (and fall through to the first-run questions) unless it contains at least one **recognized preflight key** — `grep -Eq '^[[:space:]]*(default_branch|dev_branch|protected_branches|branch_naming|active_window_days|active_prefixes):' "$root/.claude/preflight.yml"` (allows leading indentation; a leading `#` excludes commented lines). Keying on the known schema rejects an empty / whitespace-only / comment-only / unrelated file — any of which would otherwise become the permanent source of truth — while still preserving a valid config that uses only a subset of keys (e.g. one omitting `default_branch`, which the remote is authoritative for anyway). On a successful copy, tell Kyle once, plainly: *"Moved your preflight config to a local-only file outside the repo (`$cfg`). Future runs read it from there — the in-repo copy is no longer used."* Then, **only if** that in-repo file is **tracked** (`git ls-files --error-unmatch "$root/.claude/preflight.yml"` exits 0), add a one-time optional-cleanup note (Kyle runs it, the skill never does):

     ```bash
     # ── SUGGESTION FOR KYLE TO RUN — preflight NEVER executes this block ──
     # optional tidy-up — run from the repo root on an otherwise-clean tree. Stops tracking the
     # now-unused in-repo copy (your local file stays); the pathspec keeps the commit to just these two:
     cd "$(git rev-parse --show-toplevel)"
     git rm --cached .claude/preflight.yml
     if ! grep -qxF '.claude/preflight.yml' .gitignore 2>/dev/null; then
       [ -s .gitignore ] && [ -n "$(tail -c1 .gitignore)" ] && echo >> .gitignore   # ensure trailing newline
       echo '.claude/preflight.yml' >> .gitignore
     fi
     git add .gitignore
     git commit -m "chore: stop tracking .claude/preflight.yml" -- .claude/preflight.yml .gitignore
     ```

     Frame it as optional housekeeping, not a blocker — once `$cfg` exists, the skill won't mention the in-repo file again whether or not Kyle cleans it up. Never run these for him.
   - **No legacy file** (genuine first run): ask the config questions (explain each; for `branch_naming` save Kyle's plain-language answer verbatim), then write `$cfg`. No repo writes, nothing to commit.

Load `reference.md → "Per-user config & migration"` for the reasoning and edge cases.

**4. Leave the session-start baseline** *(still Step 3 — not "Step 4: Sync" below; runs on every preflight, first-run and steady-state alike, including when there is no `origin`)* (per-user, outside the repo — same key as `$cfg`):

Write `$HOME/.claude/preflight/${key}.session-start.json` — the snapshot `/mise-en-place` diffs against at closedown to tell work *this session created* from work that was already there. Without it, closedown cannot attribute safely and suppresses its commits, so this write is what makes the day's bookends work.

**Do not clobber a fresh one.** If a baseline exists and is less than 16 hours old, leave it alone and say so. Running preflight again at 2pm must not overwrite the 9am snapshot — that would re-label the morning's work as "already there", and closedown would then refuse to commit the very work the session produced. The oldest baseline of the session is the correct one.

```bash
base="$HOME/.claude/preflight/${key}.session-start.json"
now=$(date +%s)
# keep only a baseline that is BOTH fresh AND for this same worktree — the key is
# derived from origin, so a sibling worktree's fresh baseline would otherwise be kept
# here and then rejected by closedown, suppressing the whole night's landing.
prev=$(python3 -c 'import json,sys
d=json.load(open(sys.argv[1]))
print(d.get("started_at",0) if d.get("root")==sys.argv[2] else 0)' "$base" "$root" 2>/dev/null || echo 0)
if [ "${prev:-0}" -gt 0 ] && [ $(( now - ${prev:-0} )) -lt 57600 ]; then
  echo "baseline from $(( (now - prev) / 3600 ))h ago kept — session start is already recorded"
else
  # .porcelain.tmp holds every dirty path — never leave it lying around
  trap 'rm -f "$base".*.tmp "$base.new"' EXIT
  # -uall: without it a new file inside a new directory collapses to "?? newdir/",
  # so the baseline cannot tell an empty new directory from one already holding
  # someone else's files, and closedown attributes everything beneath it to this
  # session. --no-optional-locks: this runs unattended and must never take
  # .git/index.lock out from under an in-flight rebase or commit.
  git --no-optional-locks status --porcelain -z -uall 2>/dev/null > "$base.porcelain.tmp"
  git worktree list --porcelain        2>/dev/null > "$base.wt.tmp"
  lsof -nP -iTCP -sTCP:LISTEN          2>/dev/null > "$base.lsof.tmp"
  python3 - "$base" "$now" \
    "$(git rev-parse --verify HEAD 2>/dev/null || echo '')" \
    "$(git stash list 2>/dev/null | wc -l | tr -d ' ')" \
    "$root" <<'PY'
import json, sys, re
base, now, head, stashes, root = sys.argv[1], int(sys.argv[2]), sys.argv[3], int(sys.argv[4]), sys.argv[5]
def rd(p):
    try: return open(p, encoding='utf-8', errors='replace').read()
    except OSError: return ''
# NUL-split, never newline-split: a filename may legally contain a newline.
porcelain = [e for e in rd(base + '.porcelain.tmp').split('\0') if e]
worktrees = [l.split(' ', 1)[1] for l in rd(base + '.wt.tmp').splitlines() if l.startswith('worktree ')]
# real listening PORTS, not the PIDs that `lsof -t` would give
ports = sorted({int(m.group(1)) for m in re.finditer(r':(\d+)\s*\(LISTEN\)', rd(base + '.lsof.tmp'))})
# atomic: a truncated baseline is indistinguishable from a stale one, and would
# silently force closedown into report-only for the rest of the repo's life.
json.dump({'schema': 1, 'writer': 'preflight 5.1', 'root': root,
           'started_at': now, 'head_sha': head, 'porcelain': porcelain,
           'stashes': stashes, 'worktrees': worktrees, 'listening_ports': ports},
          open(base + '.new', 'w'), indent=2)
PY
  if [ -s "$base.new" ] && mv -f "$base.new" "$base" && [ -s "$base" ]; then :
  else echo "preflight: baseline write FAILED — tonight's closedown will be report-only"; fi
  rm -f "$base".*.tmp "$base.new"
fi
```

`root` is what makes the file identifiable: the key is derived from `origin`, so **all worktrees and clones of one remote share this single file**. A reader must compare `root` against its own toplevel and treat a mismatch as no baseline at all — `worktrees` cannot serve as that test, since it lists every sibling. `schema` lets a reader refuse a payload it does not understand rather than misread a renamed field.

`head_sha` is recorded here, *before* Step 4's fast-forward, so on a behind branch it is the pre-sync tip. That is the correct anchor for "what this session started from" and is what closedown reports as `oldSHA`.

Python builds the JSON rather than a `sed`/`paste` pipeline, for three reasons that all bit earlier drafts: a filename may legally contain a newline (so the porcelain list must be split on NUL, never on newline); quotes and backslashes in paths need real JSON escaping; and `lsof -t` returns **PIDs**, not ports, so the port list has to be parsed from the `(LISTEN)` column or the field lies about what it holds.

Narrate it in one line ("noting the tree's starting state so tonight's closedown can tell your work from what was already here"), the same as any other write. It contains no repo content — only paths, counts and PIDs — and lives outside every repo, so it is never staged and never committed.

`/mise-en-place` treats the baseline as **absent** if it is older than 16 hours, and degrades to report-only attribution rather than guessing. That is the intended failure mode: a stale baseline must never license a commit.

### Step 4: Sync — classify, fast-forward active, flag the rest

Classify every local branch, fast-forward only the *active* ones, flag everything else with reasoning. Skip this whole step if Step 1 found no `origin`, detached HEAD, or an unborn repo.

**Gather (one cheap pass, no checkout, stay on the current branch):**

```bash
git fetch --prune --no-tags origin
# NUL (%00) field + record separators so branch names containing | or newlines can't break parsing:
git for-each-ref --format='%(refname:short)%00%(committerdate:unix)%00%(upstream:short)%00%(upstream:track)%00%00' refs/heads
git branch --merged "origin/<default>"          # ancestry-based merged detection
git worktree list --porcelain                    # machine-readable worktree-pinned detection
```

For worktree-pinned detection, parse `git worktree list --porcelain` records: a branch is pinned **elsewhere** only when its `branch refs/heads/<name>` line belongs to a `worktree <path>` whose path is **not** this run's `git rev-parse --show-toplevel` (from Step 1). Don't blindly treat every `branch` line as pinned — that would wrongly skip the current branch's own sync.

If `gh` is available and authenticated (`command -v gh && gh auth status`), also catch squash-merges:

```bash
gh pr list --state merged --base "<default>" --limit 200 --json headRefName
```

If `gh` is missing/unauthenticated: note "PR/squash data unavailable," rely on the ancestry check above, and treat uncertain branches as **flag-only** (never pull a maybe-merged branch).

**ACTIVE (eligible to fast-forward)** — a branch qualifies only if **all** hold:
- upstream is exactly `origin/<same-branch-name>` (`%(upstream:short)` equals `origin/` + the branch's own short name — not a fork/other remote, not a renamed upstream), **and**
- behind-only (`%(upstream:track)` is `[behind N]`, N>0; not diverged, not ahead, not in-sync), **and**
- is `default_branch` / `dev_branch`, **or** its name begins with one of the configured `active_prefixes` followed by `/` — build the test from config, e.g. `^(feat|feature|fix|chore)/` for the defaults. A bare `feature-x` does **not** match the prefix `feat` (the `/` boundary is required), **and**
- not merged into the default branch (ancestry or merged-PR), **and**
- recent (commit within `active_window_days`) — `main`/`dev` are always recent enough.

**In-sync** = upstream is present **and** `%(upstream:track)` is empty → no action, report as "current," not flagged. (Don't confuse with **no-upstream**, where `%(upstream:short)` itself is empty — that's flag-only.)

Everything else is **FLAG-ONLY**: diverged, ahead-only (unpushed), no-upstream, non-origin upstream, `[gone]` upstream (merged/abandoned), merged-into-default, stale (beyond window), worktree-pinned, detached HEAD. A branch that meets every criterion **except** the name prefix is also **FLAG-ONLY** this run — surface it and offer to add its prefix to `active_prefixes` for next time; do not pull it now (a single-pass briefing can't pause to ask mid-run).

**Fast-forward mechanics (ff-only, never merge/rebase):**
- **Non-current active branches** — update the ref in place *without checkout*, batched, fully-qualified and quoted, **excluding the current branch and any worktree-pinned branch**:

  ```bash
  # build each refspec as a SEPARATE argument; never concatenate names into one string:
  refspecs=()
  for b in "${active_noncurrent[@]}"; do refspecs+=("refs/heads/$b:refs/heads/$b"); done
  git fetch --no-tags origin "${refspecs[@]}"
  ```

  Pass refspecs as **separate quoted arguments** (array elements), never interpolated into a command string — a branch name can contain `'`, `;`, or `$`. If a name contains shell-special characters that can't be passed cleanly, **skip and flag it** rather than risk a malformed command. Git **refuses** any refspec that isn't a clean fast-forward and leaves that ref unchanged (this is also what protects against a force-pushed remote — never "fix" it by adding `+` or `--force`). Only include branches returned by `git for-each-ref` (never invent `dev:dev` if no local `dev` exists — that would *create* a branch). A batched fetch is **not** atomic: one ref can update while another is rejected — parse per-ref, don't assume all-or-nothing.
- **Current branch** — can't be refspec-updated. Only if its upstream is `origin/<current>` **and** the tree is not tracked-dirty (Step 2):

  ```bash
  git merge --ff-only @{u}
  ```

  (`@{u}` is the current branch's upstream. `merge --ff-only` aborts cleanly on divergence and isn't affected by `pull.rebase` config.) Don't pre-screen for untracked-file collisions — just **attempt the merge** and treat *any* non-zero exit (divergence, or an untracked file colliding with an incoming tracked path) as "skipped: could not fast-forward," never as synced.

**Narrate before, verify after.** Before: "main is 3 behind origin — fast-forwarding slides your pointer to match, no merge commit." After, confirm each branch's old→new SHA from the command output (a `! [rejected]` line or non-zero merge = "skipped: diverged," **never** "synced"). Two summaries:
- **SYNCED:** `branch: oldSHA → newSHA`
- **FLAGGED:** table of `branch | state | why not pulled | suggested next step`

In the FLAGGED "suggested next step," **never suggest deleting a `protected_branches` branch** (or a worktree-pinned one) even when it reads as merged — suggest investigation or leave it alone.

For diverged default, load `reference.md → "Diverged default branch"` before recommending. Deeper mechanics: `reference.md → "Auto-sync mechanics: refspec ff vs pull"` and `→ "Active vs stale: the classification table"`.

### Step 5: Open PRs

Gate first: `command -v gh && gh auth status`. If unavailable, note "PR data unavailable (gh not configured)" and skip to Step 6. Resolve Kyle's login once (`gh api user --jq .login`) so "Kyle's PRs" is identified by author, not guessed.

```bash
gh pr list --state open --json number,title,author,headRefName,baseRefName,isDraft,reviewDecision,updatedAt,labels
gh pr list --state open --search "review-requested:@me" --json number,title,author,headRefName,updatedAt
```

**Kyle's PRs:** filter the first query to `author.login == <resolved login>` — awaiting review / changes requested / approved / draft — with number, title, branch, age, and a brief note on whether it affects today's work. **Review-requested PRs:** surfaced by the second query. Files Kyle's about to touch: only if he's said what he's working on.

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
- Config storage / migration behavior → "Per-user config & migration"
- Rebase vs merge → "Rebase vs merge"
- Diverged branches → "Diverged default branch"
- Stale stashes/branches → "When to clean up vs when to leave it"
- Secrets in tracked files → "Secrets and sensitive files"
- Detached HEAD → "Detached HEAD"
- PR backlog → "Managing your PR backlog"
- Worktrees → "Worktrees and branch safety"

## Known limitations

These are flagged-not-handled by design — when encountered, report and defer to Kyle rather than improvising: submodule dirtiness, sparse/shallow checkouts, case-only branch-name differences, branches squash-merged locally without a PR (no record to detect), commit-recency based on the local tip date (a behind-only branch with newer *remote* commits may read as stale near the window edge), squash-merged branches beyond the `gh pr list --limit 200` cap on very busy repos (may read as not-merged), and `--no-tags` not fully neutralising tag pruning if `fetch.pruneTags`/`remote.origin.pruneTags` is enabled in git config (if so, flag rather than fetch).

## What this skill does NOT do

- **No unsafe writes.** Only fast-forwards. The skill makes **zero commits** — config lives outside the repo. No merges, rebases, resets, force-pushes, branch/tag create/switch/delete, or pushes of Kyle's commits.
- **No touching dirty trees or risky branches.** tracked-dirty trees and diverged/ahead/no-upstream/non-origin/stale branches are flagged, never modified.
- **No shipping workflow** (push, PR open, merge). Kyle's PR process lives outside this skill.
- **No history rewriting or secret cleanup.** Those are Martina's.
- **No nagging.** Surface things once, with reasoning. Kyle decides.
