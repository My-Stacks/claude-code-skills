---
name: mise-en-place
version: "1.1"
description: >-
  End-of-day shutdown for a working repo — run when you are finished for the
  night, not when you are lost. Lands the session's work (commit, push, open a
  PR — never merge), sweeps git, GitHub, Linear, running processes and scratch
  files, reconciles what they disagree on, and harvests the session's traps into
  the durable record. For a mid-task re-baseline when you have lost track of
  where the project is, use /housekeeping instead.
trigger: /mise-en-place
---

## Version Check
To check for updates: `curl -s https://raw.githubusercontent.com/My-Stacks/claude-code-skills/main/versions.yaml`
Compare against this file's version in frontmatter.

# Mise en Place

*A kitchen's closedown is the next morning's mise en place. Wipe down tonight so tomorrow starts at zero.*

## The test

> **Can the next session start productively in 60 seconds, without asking the operator a single question?**

If a check does not move that answer toward yes, skip it. This is not a summary of the session — the chat has that. It is about the gap between what happened and what is *recorded*.

## When to use this instead of /housekeeping

Pick by **why you're running it**, not by what's messy.

| | `/mise-en-place` | `/housekeeping` |
|---|---|---|
| **You are** | stopping for the day | lost mid-task |
| **You say** | "wrapping up", "shutting down" | "in the weeds", "what am I missing" |
| **Forward work** | lands — commit, push, PR | stops dead |
| **It writes** | acts, announcing each step; asks at the guardrails | nothing until you approve it line by line |
| **You get back** | a clean slate and a handoff | a re-baseline and the next 3–5 moves |

If you know what you did today and just need it put away, this. If you can't say what the project's next move is, that. Running this when you meant housekeeping lands work you may not want landed.

## The charter — what this skill MAY and MAY NEVER do

The load-bearing contract. **The line is the network boundary, not danger.** A commit is local and reversible and nobody else sees it. A push, a PR, a ticket change and a status update cross the wire: they notify humans, fire CI, ping CODEOWNERS, and cannot be retracted without someone noticing. Split there and the postures need no judgement.

**Every interpolated value is quoted, always.** Branch names, paths, PIDs, project names, and every field read from the baseline go into commands as `"$var"` — never bare, never inside a string a `$(` or backtick could reopen. Paths may legally contain spaces, newlines, `$` and backticks; project names are written by anyone in the Linear workspace; the baseline is a file on disk. Validate shapes before use: `head_sha` must match `^[0-9a-f]{7,40}$` and `started_at` `^[0-9]{9,11}$`, or the baseline is absent.

### Posture A — ANNOUNCE THEN ACT (stays on this machine)

State the operation and its target in one line, run it, confirm the result.

- `git commit` of paths this session created or modified, on a **non-default, non-protected** branch, staged by individually named literal pathspecs (Phase 1).
- `git fetch --no-tags origin`, `git remote prune origin` — read-only against the remote.
- Writing the harvest, the run ledger, the consent file and the project map under `~/.claude/mise-en-place/`.
- Killing a process whose PID this session captured at launch (Phase 2).

Nothing else. If an action puts bytes on a server someone else can see, it is Posture B.

### Posture B — STOP AND ASK (crosses the wire)

Present the exact operation and **wait**. Default is no write.

- **`git push`** — including the first push that creates `origin/<same-name>` via `git push -u origin "$branch"`. A same-name remote tracking branch is landing, not the branch creation Posture C forbids. Preconditions are in Phase 1.
- **`gh pr create`** — a PR requests review from named humans, starts a billed CI run, and often spins a preview deploy. Announce the resolved base repo and branch before asking.
- **Closing or retitling a Linear ticket**, setting a project's status enum, or writing an empty project description.
- **Posting a project status update** — always, including health.
- Deleting a local branch, or removing a worktree.

**Consent — only `push` is remembered.** On the first yes to a push in a repo, record `push: yes` with the date in `~/.claude/mise-en-place/<key>-consent.yml`. From then on push is announce-then-act **for that repo only**; the consent is void if `origin` changes, if the run is REPORT-ONLY (Phase 0), or after 30 days — re-ask rather than assume, and say at the top of the run whether it is in force. **`gh pr create` is asked every night, never remembered:** a PR pulls named humans into review and bills CI, and a 30-day yes would be a month of unattended PRs. **Linear has no consent key:** every ticket mutation goes through `/linear track` → `/linear push`, which previews and waits on each write (Phase 3), and that preview *is* the gate — nothing here overrides it.

**First contact is a dry run — enforced, not advised.** If the repo has neither a consent file nor a run ledger, this skill has never closed it down: run as `--dry-run` whatever flags were passed, say so, and tell the operator to re-run once the report reads right. The build gate and the PR are both side effects on a repo whose shape nobody has checked.

### Posture C — NEVER

No announcement and no approval makes these allowed.

- **Merging.** No `gh pr merge`, no `--auto-merge`, no enabling auto-merge, no local merge. Merging is a decision, never housekeeping. Do not ask — the answer is not yours to seek during a shutdown.
- **Force-push, history rewrite, `reset --hard`, `branch -D`, `rebase`, `cherry-pick`, `--no-verify`.** Never retry a rejected push by any means.
- **Committing a file this session did not touch** — any path already dirty in the baseline, or one you cannot tie to an edit you made. Editing a pre-existing tracked file is normal work and *is* committable; inheriting someone else's uncommitted change is not.
- **Staging a directory or a glob.** `git add -- src/` is `git add -A` with extra steps. Never a directory, `.`, `:/`, `*`, `-A`, `-u`, or `git commit -a`.
- **Staging a deletion.** A porcelain entry whose status contains `D` is never yours, whatever the attribution test says.
- **Committing to or pushing the default or a protected branch.**
- **Creating, switching, or renaming a branch or tag.**
- **Pushing work the operator called experimental, a spike, throwaway, or said not to push.** One such statement is a permanent veto for the run.
- **Filing any Linear ticket other than the single escalation ticket**, and **rewriting any ticket body**. Both are claims about what was planned, and both notify the team.
- **Touching a ticket assigned to, or created by, anyone but the resolved current user** (Phase 0). Unassigned is *not* the same as yours.
- **Deleting any file outside the session scratchpad**, whoever created it. Never delete a gitignored file — those are local config (`.env`, `settings.local.json`, caches).
- **Killing any process whose PID this session did not capture at launch**; never `kill -9`, `pkill`, or `killall`.
- **Acting on another person's open PR.** Report it as pre-existing; never push to it, close it, or re-target it.
- **Doing the work you find.** "While cleaning up I noticed X and fixed it" is a new task with no review. Note it; do not do it.
- **Reporting clean** when a surface was unreachable, a mutation failed, a phase was suppressed, or attribution was degraded.

> **If a situation isn't clearly inside Posture A, it's a recommendation or a question, not an action.**

Reporting something that was yours costs one line. Acting on something that was not is unrecoverable.

## Invocation

```
/mise-en-place              # full closedown
/mise-en-place --dry-run    # no writes; report what it would do
/mise-en-place --land-only  # skip Phase 3 reconcile; everything else runs
```

`--dry-run` performs no commits, pushes, PRs, kills, ticket mutations, harvest, consent write, or `/linear handoff`. Each action is emitted as `WOULD: <action>`, each gated one as `WOULD ASK: <action>`. Report titled `MISE EN PLACE (DRY RUN)`. It writes exactly one thing — the run ledger, with `run_status: dry-run` and nothing landed — so the next run is no longer first contact.

`--land-only` skips Phase 3 only; report titled `MISE EN PLACE (LAND ONLY)`, with `Reconciled` reading `not run`. **Phase 4 always runs** — a session that shipped nothing is exactly the session whose only value is the harvest. `--dry-run` wins over `--land-only`.

**Requires `/preflight` to have run at the start of the same session.** Its baseline is the only way to tell your work from what was already in the tree; without it every commit is suppressed (Phase 0).

## Procedure

Six phases, in order — Phase 3 needs Phase 2's findings, so never parallelise *across* phases; within Phase 2, sweep independent surfaces in parallel. Announce each phase as you enter it. Each states **Done when**; a phase that finds nothing says so in one line and moves on.

### Phase 0 — Baseline and scope (no writes)

Attribution is a diff against a snapshot, never a judgment call. Read the baseline preflight wrote at session start:

```bash
# Derive key and tree hash HERE, byte-identical to preflight Step 3 — never from memory.
# Any deviation reads as "baseline absent" and silently suppresses every commit.
root=$(git rev-parse --show-toplevel) || exit 1
raw=$(git remote get-url origin 2>/dev/null | head -1); [ -z "$raw" ] && raw=$root
canon=$(printf '%s' "$raw" | tr 'A-Z' 'a-z' \
  | sed -E 's#^([a-z]+://([^/@]+@)?[^/:]+):[0-9]+/#\1/#; s#^[a-z]+://##; s#^[^@/]+@##; s#:#/#; s#/+$##; s#\.git$##; s#/+$##')
stem=$(printf '%s' "$canon" | tr -c 'a-z0-9._-' '-' | sed -E 's#-+#-#g; s#^[-.]+##; s#[-.]+$##')
hash=$(printf '%s' "$canon" | { shasum 2>/dev/null || sha1sum 2>/dev/null; } | cut -c1-12)
key="${stem:-repo}-${hash}"
tree=$(printf '%s' "$root" | { shasum 2>/dev/null || sha1sum 2>/dev/null; } | cut -c1-12)
base="$HOME/.claude/preflight/${key}.${tree}.session-start.json"
cat "$base"

# Fallback lookup by ROOT, never by grep: `worktrees` lists every sibling path, so a
# text match confirms a sibling's baseline. Compare the top-level "root" field.
python3 - "$root" "$HOME/.claude/preflight" <<'PY'
import json, glob, os, sys
root, d = sys.argv[1], sys.argv[2]
for f in sorted(glob.glob(os.path.join(d, "*.session-start.json"))):
    try:
        if json.load(open(f)).get("root") == root: print(f)
    except Exception: pass
PY
```

Reuse `$key` for the run ledger and the consent file. If `$base` is missing but the fallback finds a file whose `root` matches, use it and report `ATTRIBUTION: key mismatch — used <filename>`.

**Validity — all required:** `schema` equal to `1` (anything else is a payload you do not understand: **absent**, not best-effort parsed); `started_at` under 16 hours old; `root` byte-equal to this run's `git rev-parse --show-toplevel` (a baseline from another root describes a different tree); parseable; `head_sha` non-empty and passing `git rev-parse --verify "<head_sha>^{commit}"` — an empty `head_sha` makes `git log ..HEAD` mean `HEAD..HEAD`, which returns nothing with exit 0 and reads as "no unlanded commits" while the day's work sits unpushed.

**A path is yours only if both hold:** it appears in this session's own Write/Edit/Bash write calls, **and** it is absent from the baseline `porcelain`. Creating a file and editing an existing tracked one both qualify; being dirty *before* the session started disqualifies. One signal is not enough.

**Parsing `porcelain`.** Entries are raw `git --no-optional-locks status --porcelain -z -uall` records — **read the live tree with those exact flags** (a default read collapses `newdir/sub/b.txt` to `?? newdir/`, and the two sides never compare equal). Split on NUL, never newline; there is no trailing newline. A record is `XY <path>` — two status characters, a space, the path — **except** that a record whose `X` or `Y` is `R` or `C` is followed by one extra record holding the **bare source path, no prefix** (`['R  new.txt', 'old.txt']`). Strip the three-character prefix from status records only, and compare **whole paths, never substrings** (`src/app.ts` is not pre-existing because the baseline holds `src/app.test.ts`). A parse you are unsure of is UNKNOWN, not a pass.

**Never yours, whatever the test says:** a **deleted path** (status contains `D` — a session's `rm -rf generated/` satisfies both limbs, and a landed deletion removes content from every future clone; report it as `deleted by a session command — restore or commit deliberately`) and **build output** (the Phase 1 build gate writes files absent from the baseline through this session's own Bash call; name untracked, non-ignored build paths in Still dirty).

**The other fields.** `head_sha` is the session's starting commit, recorded *before* preflight's fast-forward — bound it as `git log --oneline "<head_sha>"..HEAD --since=@<started_at>` (`@` marks a Unix timestamp; without `--since`, commits preflight *pulled* read as this session's). It is the report's `oldSHA` and the only attribution signal that survives a compaction. `stashes` is a count — more now than then means this session stashed work, and Phase 1's ladder applies. `worktrees` defines "stray" in Phase 2: present now, absent there. `listening_ports` were the operator's before you started. **If the session was compacted**, the edit-call signal is unreliable and attribution is UNKNOWN.

**Baseline absent, stale, or attribution UNKNOWN → REPORT-ONLY.** The run commits nothing (the Phase 4 harvest is written, left uncommitted, reported local-only), kills nothing, deletes nothing, mutates no tickets, and suppresses `/linear handoff` (which also commits). It may push and PR only commits it can bound with `git log <head_sha>..HEAD` — with the baseline absent or the session compacted that bound does not exist, so push and PR are suppressed too. Say so on its own line, with the real cause and the remedy (without the remedy a first run reads as a broken skill rather than a missing prerequisite):

`ATTRIBUTION: <baseline absent | baseline stale (Nh) | wrong worktree | session compacted> — <actions suppressed>. Run /preflight at the start of your next session and this will land normally.`

**Scope is this repo only.** Dirty state elsewhere is reported, never written to.

**Two records, never conflated.** The **run ledger** `~/.claude/mise-en-place/<key>-last-run.md` is written at the end of a run and read at the start of the next — if today's exists, do not redo what it says was landed, harvested and escalated. It never records process launches: **kill authority comes only from this session's transcript** — a `run_in_background` Bash call you can point to. No such call → no kill, whatever the port scan shows.

**Resolve the operator** — never infer it: `gh api user --jq .login` for GitHub, the Linear viewer for tickets. State both; a surface whose identity cannot be resolved is report-only.

**Resolve the GitHub repo once** — `repo=$(gh repo view "$(git remote get-url origin)" --json nameWithOwner -q .nameWithOwner)` — and pin it on **every** call: `--repo "$repo"` for `gh pr`, `GH_REPO="$repo"` for `gh api`. On a clone that also has an `upstream` remote, unpinned `gh` resolves to the parent, and a fork's PR would open against someone else's project.

**The session scratchpad** is the directory this session's harness context names. State the path; with no scratchpad, this run deletes nothing at all — say so.

**Done when:** baseline state, attribution mode, consent in force, `$repo`, operator and scratchpad path are all stated aloud.

### Phase 1 — Land the work

Nothing may exist in only one place: `uncommitted → committed → pushed → PR'd → merged or explicitly parked`. The ladder stops at PR'd; merging is Posture C.

```bash
branch=$(git branch --show-current)              # empty => detached HEAD
git --no-optional-locks status --porcelain -z -uall \
  | python3 -c 'import sys; [print(repr(e)) for e in sys.stdin.buffer.read().decode("utf-8","replace").split("\0") if e]'
git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1 \
  && git log --oneline @{u}..HEAD \
  || echo "NO UPSTREAM — every local commit is unlanded"
```

Candidates print as `repr()` so a newline inside a filename shows as `\n` instead of splitting into two entries. `@{u}` exits 128 on a branch with no upstream — the never-pushed branch is exactly the case this phase exists to catch, and unguarded it reads as "nothing unpushed". **This guarded form is the only upstream check used anywhere in the run.**

**Detached HEAD** (on a commit, not a branch — anything committed here belongs to nothing) ends Phase 1 and disables every commit and push for the whole run, Phase 4's and `/linear handoff`'s included; Phases 2–4 run report-only. Report `RUN STATUS partial` and name the SHA. **No `origin`** → the ladder terminates at `committed`; a coverage finding, not a parked branch; skip `git fetch`.

- **Yours and uncommitted** → print the path list, then stage each path **individually and literally**: `git --literal-pathspecs add -- "<path1>" "<path2>" …`. The flag matters — git expands globs *inside* a quoted pathspec, so plain `git add -- "star*.txt"` also stages `star1.txt`. Then `git diff --cached --name-only` must equal the printed list set-for-set; any extra path aborts — `git restore --staged -- <the printed list>` (never bare `git reset`, which would also unstage whatever the operator had staged before the run) and report. Run `git diff --cached` and refuse if it contains a credential shape — stop and report, never redact. Commit with a real message.
- **Not yours** → never stage it; report in Still dirty as pre-existing.
- **Committed but unpushed** → push preconditions, then Posture B. A stated reason not to push goes in the handoff, not in your head.
- **Pushed without a PR** → PR preconditions, then Posture B — or record why it is parked.

**`ahead-only`**: `git rev-list --left-right --count @{u}...HEAD` prints `behind<TAB>ahead`; ahead-only is `0` on the left and more than `0` on the right.

**`protected`** is a server-side setting you cannot see from git, and this probe is **fail-closed**: anything short of a positive "not protected" from *both* endpoints counts as protected.

```bash
b=$(python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$branch")
# classic protection: 200 → protected; the specific 404 body → not; anything else → unknown
err=$(GH_REPO="$repo" gh api "repos/{owner}/{repo}/branches/$b/protection" 2>&1 >/dev/null); rc=$?
if   [ "$rc" -eq 0 ]; then classic=protected
elif printf '%s' "$err" | grep -q 'Branch not protected'; then classic=no
else classic=unknown; fi
# rulesets: a ruleset-protected branch is 404 from the classic endpoint, so ask both
rules=$(GH_REPO="$repo" gh api "repos/{owner}/{repo}/rules/branches/$b" --jq length 2>/dev/null) || rules=unknown
case "$classic/$rules" in no/0) echo NOT-PROTECTED ;; *) echo "PROTECTED-OR-UNKNOWN ($classic/$rules)" ;; esac
```

Encode the branch name — `feature/x` unencoded becomes extra path segments. Report an `unknown` outcome as such: "could not confirm unprotected" is a finding, and the server's own rejection is the last line of defence, not the first.

**Push preconditions** — all must hold: `git fetch --no-tags origin` first (a stale picture of origin is how you push over someone's work); branch is not the default and not protected; branch is **ahead-only**, or has no upstream (then `git push -u origin "$branch"` creates it — the explicit remote and name are required under `push.default=simple`); no other worktree has this branch checked out (`git worktree list --porcelain`); no experimental/do-not-push veto was spoken this session. Behind or diverged → stop and report who else pushed. A rejected push is a finding, never a retry.

**PR preconditions** — `gh pr list --repo "$repo" --head "$branch" --state all --json number,state` decides the ladder's terminal state, and the three states differ: **open** → report the number and stop; **closed-unmerged** → rejected before, so neither reopen nor file a second — report `branch pushed, PR #<n> closed unmerged — needs a decision`; **merged** with commits after the merge SHA → open a new PR for the remainder. Base is the resolved default (REFERENCE §1); the PR targets `$repo` via `gh pr create --repo "$repo"` — on a fork (`gh repo view --json isFork`) the unpinned default is the **parent**, and a deliberate cross-fork PR is its own Posture B question. **The build gate is stated, not assumed:** run the project's build; if it fails, is absent, or won't run, open as `--draft` and say which. Never add reviewers, assignees, labels, or auto-merge.

**Done when:** every live porcelain path is committed, named as not-yours, or named in Still dirty — and the branch has a terminal state on the ladder.

### Phase 2 — Sweep the workstation

| Surface | Looking for |
|---|---|
| **Git** | Uncommitted, unpushed, branches tracking a deleted remote, stray worktrees |
| **GitHub** | Open PRs (yours this session vs pre-existing), draft PRs that are done, unresolved review threads, failing or **absent** CI |
| **Linear** | Ticket state vs reality, project status, empty description — **only if bound** (below) |
| **Processes** | Dev servers, watchers, tunnels this session's transcript shows this session starting |
| **Filesystem** | Untracked non-ignored leftovers, files written outside the scratchpad |
| **Artifacts** | Anything published this session that is now stale |

**Binding test, before any Linear read or write:** a binding exists only if the repo has `.linear/` carrying a project id, or `/linear` reports a bound project for this path. **A fuzzy name match against `list_projects` is not a binding.** Unbound → the whole Linear surface is `skipped — repo not bound to a Linear project`: no reads, no closes, no escalation ticket, no handoff. A coverage finding, not a clean row.

**Absence is a finding.** "No CI configured" means the local build was the entire gate — that changes what a green build is worth. Say so.

Kill only a PID **this session's transcript shows this session launching**, re-verifying with `ps -o pid=,lstart=,command= -p <pid>` that the command still matches; `kill` (TERM) only. A port in the baseline's `listening_ports` was the operator's, whatever is on it now. Anything you cannot attribute is left running — say what you left.

A surface off this table — CRM, call transcripts, a decision ledger — is `/housekeeping`'s sweep. Name it in Still dirty and move on.

**Done when:** every row reads `clean` / `<finding>` / `skipped — <reason>` / `unreachable`, and the table is emitted. A silent skip reads as a pass.

### Phase 3 — Reconcile

Contradictions are disagreements *between* surfaces, not problems *within* one. Use housekeeping's class names so findings stay comparable across the two skills — id format `<class>/<surface>:<record-id>`:

- **`superseded`** — a ticket's premise is contradicted by a newer merge or ruling ("not pushed" on a branch that merged). A project sitting in Backlog while you merged into it is `superseded` at project scope.
- **`done-in-substance`** — intent already satisfied by something you can cite in a system you can read ("blocked on the migration script" for a script that merged). Where it turns on a client, a promise or a price, the outside-knowledge test applies and it escalates.
- **`orphaned-cadence`** — a recurring artifact past its period: no project update since the last two merges, a weekly status that stopped.
- **`canon-drift`** — a published artifact states a number the code has since changed. **Narrower than housekeeping's:** the reference is the code, not the project's canon, and only artifacts this session published — a housekeeping run must not read a clean result here as a canon check.
- **`uncaptured-session`** — Phase 4.

The other eight housekeeping detectors need canon, CRM or transcript sweeps this skill does not perform; on a partial inventory they produce confident wrong findings at the moment nobody is watching.

#### The disposition rule

Apply in order.

1. **Evidence test.** Can you cite a specific artifact *in a system you can read* that settles it — a merge SHA, a passing check, a diff? Yes → **close**, and the close comment must cite it. **No close without a citation.**
2. **Outside-knowledge test.** Does settling it require knowing what a client was told, sent, promised, or charged? Yes → **escalate**.
3. **Default.** Unsure, both, or neither → **escalate**.

Escalating wrongly costs the operator two minutes; closing wrongly rewrites the record of what was promised and delivered.

**Close only tickets assigned to the resolved current user.** Unassigned is *not* yours — on a shared board it is the default state of everything nobody has picked up yet, including work a teammate is halfway through. Unassigned and other-owned tickets go in the escalation table.

**Every ticket mutation goes through `/linear track` then `/linear push`** — never a direct `save_issue` or `save_comment`. `push` runs the drift check that catches a ticket someone else moved since you read it, and the session buffer is the only thing `/linear handoff` can see — a closure written directly leaves the tally empty, and an empty tally routes the session update to the bound project by default.

**The cap: 5 ticket-state mutations per day, cumulative across runs** — a mutation is a state or title change to an existing ticket; a re-run reads the prior ledger's count and continues from it. Above the cap, apply none and escalate the whole set. **Only two writes are exempt: the single escalation ticket, and the project status enum.** Nothing else (Posture C).

Escalate **once**, in a single ticket with a disposition table, filed in the same project as the tickets it escalates. Not eight tickets, and not only in chat, where it dies with the session.

**Done when:** every contradiction is closed with a citation, or in the escalation table.

### Phase 4 — Harvest

The transcript is about to disappear. Harvest what would cost the next session real time to rediscover:

- **Traps** — a tool that silently did the wrong thing; a build that was green and wrong.
- **Decisions and their reasons** — including what was rejected, which is what stops it being relitigated.
- **Measurements** — the before-state for the next comparison.
- **Dead ends** — so nobody retries them.

**Threshold:** cost more than ten minutes, *or* would have shipped silently. The second class matters more. Engineering knowledge only — commitments, figures and rulings stated in conversation are `/housekeeping`'s harvest and need its provenance classes.

**Where it goes.** Resolve `root=$(git rev-parse --show-toplevel)` and make every rung absolute — the shell's working directory persists between calls and may be a subdirectory. Take the first that applies:

1. An existing `$root/journal` **real directory** → `$root/journal/YYYY-MM-DD-<slug>.md`.
2. Otherwise an existing `$root/.linear` **real directory** → `$root/.linear/journal/YYYY-MM-DD-<slug>.md`.
3. Otherwise `~/.claude/mise-en-place/<key>/journal/YYYY-MM-DD-<slug>.md` — **outside the repo, never committed.** Say so plainly: `HARVEST: written outside the repo to <path> — this repo has no journal/ or .linear/.`

Test each in-repo rung with `[ -d "$path" ] && [ ! -L "$path" ]` — `[ -d ]` alone is true for a symlink, and a `journal` symlinked outside the repo passes `git check-ignore` while nothing lands in the tree. **This skill never creates `journal/` in a repo that lacks one** — an existing `journal/` or `.linear/` is the repo opting in; creating one decides on someone else's behalf that their history is a good place for your engineering notes.

**Test the destination with `git check-ignore -q <path>` every run** — `.linear/` is gitignored in some repos and tracked in others, and an ignored destination is local-only while looking like success. Ignored → fall through to the next rung. If **every** rung is ignored, write to `journal/` anyway and report: `HARVEST: written to <path>, which is gitignored — local-only, not durable. Track it or move it to keep it.` Never report a harvest as durable when git will not carry it.

If the file already exists, **append** under `## Second pass — <time>`. Never overwrite a harvest.

**Then land it — rungs 1 and 2 only.** The harvest is a file this run created, so committing it is Posture A and pushing it is Posture B, under the same preconditions as Phase 1 — **including the branch rule: on the default or a protected branch do not commit** (Posture C outranks this step) and report `HARVEST: written to <path>, uncommitted — <branch> is the default/protected branch.` Re-run the credential check on the staged diff first: the harvest is transcript-derived and the likeliest file in the run to carry a token or a client figure. If the branch has an open PR, it lands there; say which commit carried it.

**Track it as well as writing it.** Log the traps and dead ends to the session buffer with `/linear track` — handoff's Traps section reads the buffer, not the journal, and skipping this ships the update with that section empty on the day it mattered.

**Done when:** the harvest is written and its path reported — or, under `--dry-run`, its intended path and content are printed — or the run states explicitly that the session produced nothing worth keeping.

### Phase 5 — Hand off, verify, report

Order matters: `/linear handoff` writes `.latest-status.md` and `.linear/last-handoff.md` and **commits them**. Running it before the final check is what keeps the report true; those two files are handoff's, never Phase 1 leftovers.

1. Resolve the destination (below), then run `/linear handoff --to <project>`. Handoff previews the update and waits for approval — **that preview is this skill's Posture B gate** for the outward status update. Surface it; never approve it on the operator's behalf. Skip entirely if the repo has no Linear binding (Phase 2); say so and rely on the harvest.
2. Push the commit handoff made — **if it made one.** Record `HEAD` before calling handoff and compare with `git log <saved>..HEAD`; `@{u}..HEAD` would show every unpushed commit and silently re-push Phase 1 work on a branch Phase 1 could not push. Where the two files are gitignored, handoff's commit is a no-op and there is nothing to push. Phase 1's push preconditions apply. Pushing nothing is fine; reporting a push that did not happen is not.
3. Re-run `git --no-optional-locks status --porcelain -z -uall` and the guarded upstream check.
4. Write the run ledger `~/.claude/mise-en-place/<key>-last-run.md` (`mkdir -p` first). Minimum fields: `root: <toplevel>` on its own line (preflight reads it to tell this tree's closedown from a sibling's), `date`, `run_status`, `landed` (branch, old→new SHAs, PR numbers), `ticket_mutations` as a **count** so tomorrow's cap continues from it, `escalation_ticket` id if filed, `harvest` path, and `findings:` as `<class>/<surface>:<record-id>` ids. Prose alone silently resets the daily cap to zero.
5. Give the report below. Lead with what is unresolved.

#### Where the handoff posts

Resolve this **here**, before handoff runs, and pass it as `--to`. Handoff infers from the session buffer (the local record `/linear track` writes); a code-only day leaves it empty, and empty falls back to the *bound* project — right when you were working **on** the tool (its own source changed), wrong when you were working **with** it on client, prospect or internal work. The binding records which directory you typed in, not whose work it was. **The tally** is the list of projects this session's tickets belong to, with a count each; empty means no tickets touched, not no work done. Resolve in order, stop at the first that fires:

1. **A remembered binding** for this repo in `~/.claude/mise-en-place/project-map.yml` → use it, state it. This is how a repo whose name does not resemble its project (`pvp-website` → *People v. Profit*) stops costing a question every night.
2. **One project in the tally** → that project. State it, do not ask.
3. **Two or more** → **STOP AND ASK.** Name each with its ticket count, propose the highest as primary, ask: primary only, or both. Never pick silently and never fan out silently — each post is a separate outward notification.
4. **Tally empty, every changed path inside the tool's own tree** → the bound project. State it: `DESTINATION: <project> (bound; this session was on the tool itself).`
5. **Tally empty, anything changed outside that tree** → **STOP AND ASK.** Do not fall back. Lead with your best inference and its evidence — the repo's `org/repo`, the branch name, the client named in the session goal or this session's commit messages — and offer the bound project as the alternative.

**When you ask, record the answer** in `project-map.yml` as `<org/repo>: <project>` so rung 1 catches it next time. Ask once per repo, not once per night; re-ask only if the answer stops matching the tally.

**Done when:** the destination is stated, the tree is verified *after* handoff's commit, and the report is delivered.

## Output format

```markdown
RUN STATUS  <complete | partial (stopped at phase N) | attribution-degraded — combine if more than one applies>
SWEPT       <N of M surfaces; name every one skipped or unreachable and why>

## Landed
<branch: oldSHA → newSHA, PR numbers. Or "nothing to land.">

## Reconciled
<surfaces that disagreed and now do not. Be specific: "project was Backlog while shipping — now Active">

## Escalated
<what needs the operator's judgment, with your recommendation. One line each.>

## Still dirty
<anything not clean, including things you did not create — name those as
 pre-existing. Never omit this section. If genuinely nothing, say "nothing" —
 do not delete the heading.>

## Next session starts with
<the single first action, specific enough to execute cold>
```

Close with one of: ✅ **next session is clear to start** · ⚠️ **things worth handling first** · 🛑 **resolve before starting tomorrow**.

A run with any unreachable surface, failed mutation, or suppressed phase **may not report clean**. If nothing needed doing, say that in one line rather than staging a checklist. A partial run still prints every heading, marking unreached ones `NOT RUN — phase N did not execute`.

**On abort, write the harvest first.** Before surfacing any error that ends the run, dump Phase 4 material and say where it went — it is the only artifact a re-run cannot recover. **Under `--dry-run` this stays a non-write:** print it inline under `## Harvest (dry run — not written)` and emit `WOULD: write <path>`.

## Composition

- Review is not part of the closedown. If this session's work needs review, Phase 1 opens the PR and you run `/ai-router review <pr>` after — outside this skill. If `/ai-router` isn't configured, note that the code went unreviewed; that is a finding, not a blocker.
- Ends by calling `/linear handoff`, which writes and commits the continuity docs.
- The opening bookend is `/preflight`, which writes the session-start baseline Phase 0 reads.

## Load REFERENCE.md when

Before the Phase 1 push/PR preconditions (§1 holds the default-branch resolution they depend on), before mutating Linear (workspace status names and start-date behaviour will bite you), before filing the escalation ticket (template), or before the process and filesystem sweep.
