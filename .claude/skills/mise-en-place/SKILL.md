---
name: mise-en-place
version: "1.0"
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

If a check does not move that answer toward yes, skip it.

Not a summary of the session — the chat already has that. This is about the gap between what happened and what is *recorded*.

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

The load-bearing contract. **The line is the network boundary, not danger.** A commit is local and reversible and nobody else sees it. A push, a PR, a ticket change and a status update all cross the wire: they notify humans, fire CI, ping CODEOWNERS, and cannot be retracted without someone noticing the retraction. Split there and the postures stop needing judgement.

**Every interpolated value is quoted, always.** Branch names, paths, PIDs, project names, and every field read from the baseline go into commands as `"$var"` — never bare, never inside a string a `$(` or backtick could reopen. Paths may legally contain spaces, newlines, `$` and backticks; project names are written by anyone in the Linear workspace; the baseline is a file on disk. Validate shapes before use: `head_sha` must match `^[0-9a-f]{7,40}$` and `started_at` `^[0-9]{9,11}$`, or the baseline is absent.

### Posture A — ANNOUNCE THEN ACT (stays on this machine)

State the operation and its target in one line, run it, confirm the result.

- `git commit` of paths this session created or modified, on a non-protected branch, staged by **individually named** pathspecs.
- `git fetch --no-tags origin`, `git remote prune origin` — read-only against the remote.
- Writing the harvest, the run ledger, and the per-repo state file under `~/.claude/mise-en-place/`.
- Killing a process whose PID this session captured at launch (Phase 2).

Nothing else. If an action puts bytes on a server someone else can see, it is Posture B.

### Posture B — STOP AND ASK (crosses the wire)

Present the exact operation and **wait**. Default is no write.

- **`git push`** — including the first push that creates `origin/<same-name>` via `git push -u`. Full preconditions are in Phase 1; this bullet is the posture, not the checklist. Creating a remote tracking branch of the same name is landing, not branch creation; it is not what Posture C forbids.
- **`gh pr create`** — a PR requests review from named humans, starts a billed CI run, and often spins a preview deploy. Announce the resolved base repo and branch before asking.
- **Closing or retitling a Linear ticket**, setting a project's status enum, or writing an empty project description.
- **Posting a project status update** — always, including health.
- Deleting a local branch; removing a worktree; anything needing force-push, history rewrite, `--no-verify`, or a protected/default branch.
- Committing when Phase 0 attribution is UNKNOWN.

**Consent is remembered per repo, not per night.** On the first yes for a given repo, record it in `~/.claude/mise-en-place/<key>-consent.yml` as `push: yes`, `pr: yes`, `linear: yes` with the date. A remembered yes downgrades that operation to announce-then-act **for that repo only**, and is void if the repo's `origin` changes, if the run is in REPORT-ONLY attribution, or after 30 days. Re-ask rather than assume. Say which consents are in force at the top of the run.

### Posture C — NEVER

No announcement and no approval makes these allowed.

- **Merging.** No `gh pr merge`, no `--auto-merge`, no enabling auto-merge, no local merge. Merging is a decision, never housekeeping. Do not ask — the answer is not yours to seek during a shutdown.
- **Force-push, history rewrite, `reset --hard`, `branch -D`, `rebase`, `cherry-pick`, `--no-verify`.** Never retry a rejected push by any means.
- **Committing a file this session did not touch** — any path already dirty in the baseline, or one you cannot tie to an edit you made. Editing a pre-existing tracked file is normal work and *is* committable; inheriting someone else's uncommitted change is not.
- **Staging a directory or a glob.** `git add -- src/` stages every dirty file beneath it — that is `git add -A` with extra steps. Never a directory, `.`, `:/`, `*`, `-A`, `-u`, or `git commit -a`.
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
/mise-en-place --dry-run    # no writes anywhere; report what it would do
/mise-en-place --land-only  # skip Phase 3 reconcile; everything else runs
```

**Run `--dry-run` first on any repo you have not closed down before.** It performs **no external writes**: no commits, pushes, PRs, kills, ticket mutations, harvest, or `/linear handoff`. Each action is emitted as `WOULD: <action>`, each gated action as `WOULD ASK: <action>`. Report titled `MISE EN PLACE (DRY RUN)`.

`--land-only` skips Phase 3 only. Report titled `MISE EN PLACE (LAND ONLY)`, with `Reconciled` reading `not run`. **Phase 4 always runs** — a session that shipped nothing is exactly the session whose only value is the harvest. `--dry-run` wins over `--land-only` on write posture.

**This skill requires `/preflight` to have run at the start of the same session.** Without its baseline it cannot tell your work from what was already in the tree, and it will suppress every commit rather than guess.

## Procedure

Six phases, in order — phase 3 needs phase 2's findings, so do not parallelise *across* phases. Within phase 2, sweep independent surfaces in parallel. Announce each phase as you enter it.

Each phase states **Done when**. A phase that finds nothing says so in one line and moves on.

### Phase 0 — Baseline and scope (no writes)

Attribution is a diff against a snapshot, never a judgment call. Read the baseline preflight wrote at session start:

```bash
# Derive the key HERE — never reconstruct it from memory. It is a 12-char sha1 of a
# canonicalised remote; any deviation reads as "baseline absent" and silently suppresses
# every commit this skill would make. Byte-identical to preflight Step 3.
root=$(git rev-parse --show-toplevel) || exit 1
raw=$(git remote get-url origin 2>/dev/null | head -1); [ -z "$raw" ] && raw=$root
canon=$(printf '%s' "$raw" | tr 'A-Z' 'a-z' \
  | sed -E 's#^[a-z]+://##; s#^[^@/]+@##; s#:#/#; s#\.git$##; s#/+$##')
stem=$(printf '%s' "$canon" | tr -c 'a-z0-9._-' '-' | sed -E 's#-+#-#g; s#^[-.]+##; s#[-.]+$##')
hash=$(printf '%s' "$canon" | { shasum 2>/dev/null || sha1sum 2>/dev/null; } | cut -c1-12)
key="${stem:-repo}-${hash}"
cat "$HOME/.claude/preflight/${key}.session-start.json"

# Verify rather than trust — a wrong key and a missing baseline look identical:
grep -l -F -- "$root" "$HOME"/.claude/preflight/*.session-start.json 2>/dev/null
```

Reuse `$key` for the run ledger and the consent file; deriving it twice by two routes is how they land in different files each run. If the derived key names no file but one exists whose `root` matches this repo, use that file and report `ATTRIBUTION: key mismatch — used <filename>`. Never use a baseline whose `root` is not this repo.

It carries `root`, `started_at`, `head_sha`, `porcelain`, `stashes`, `worktrees` and `listening_ports`.

**Two validity tests, both required:** `started_at` under 16 hours old, **and** `root` equal byte-for-byte to this run's `git rev-parse --show-toplevel`. The key is derived from `origin`, so **every worktree and every clone of one remote shares a single baseline file** — a baseline written from a sibling worktree describes a *different tree* and is as unusable as a missing one. Do not use `grep -F -- "$root"` over the baselines as the identity test: `worktrees` lists every sibling path, so it matches a sibling's file and confirms the wrong one.

A baseline that is older, missing, unparseable, written from another `root`, or whose `head_sha` is empty or fails `git rev-parse --verify "<head_sha>^{commit}"` → treat it as **absent**. (An empty `head_sha` matters: `git log ..HEAD` with an empty left side silently means `HEAD..HEAD` and returns nothing with exit 0, which reads identically to "no unlanded commits" — and would close the run ✅ with the day's work unpushed.)

**A path is yours only if both hold:** it appears in this session's own Write/Edit/Bash write calls, **and** it is absent from the baseline `porcelain`. Creating a file and editing an existing tracked one both qualify — what disqualifies a path is having been dirty *before* the session started. One signal is not enough.

`porcelain` entries are raw `git status --porcelain -z` records, **separated by NUL bytes, not newlines** (split on `\0`; there is no trailing newline). Each is `XY <path>` — two status characters then a space then the path — **not** a bare path, and a rename contributes a second entry holding the source path. Strip the leading three characters and compare **whole paths, never substrings**: `src/app.ts` must not read as pre-existing because the baseline holds `src/app.test.ts`. A parse you are unsure of is UNKNOWN, not a pass.

**A deleted path is never yours.** A porcelain entry whose status contains `D` is reported in Still dirty as `deleted by a session command — restore or commit deliberately`, never staged. A session script (`rm -rf generated/`, a codegen or migration step) satisfies both attribution limbs, and landing a deletion removes content from every future clone.

**Build output is never yours,** however the test scores it — a build run by the Phase 1 PR gate writes files absent from the baseline through this session's own Bash call, satisfying both limbs. Name untracked, non-ignored build paths in Still dirty.

Use the other fields, don't just read them. **`head_sha`** is the session's starting commit — recorded *before* preflight's fast-forward, so bound it as `git log --oneline "<head_sha>"..HEAD --since=@<started_at>` (the `@` before the number tells git it is a Unix timestamp, not a date string). Without `--since`, commits preflight *pulled* fall inside the range and read as this session's work. It is the report's `oldSHA` and the only attribution signal that survives a compaction. **`stashes`** is a count — more now than at baseline means this session stashed work, which exists in exactly one place, so Phase 1's ladder applies. **`worktrees`** defines "stray" in Phase 2: present now, absent there. **If the session was compacted**, the first signal is unreliable — attribution is UNKNOWN regardless of the second.

**If the baseline is absent, stale, or attribution is UNKNOWN → REPORT-ONLY ATTRIBUTION.** The run commits nothing — **including the Phase 4 harvest, which is written but left uncommitted and reported local-only** — kills nothing, deletes nothing, mutates no tickets, and suppresses `/linear handoff` (which also commits). It may push and PR only commits it can bound with `git log <baseline head_sha>..HEAD`; **if the baseline is absent or the session was compacted that bound does not exist, so push and PR are suppressed too.**

Say so on its own line, naming the cause that actually fired **and the remedy**:

`ATTRIBUTION: <baseline absent | baseline stale (Nh) | wrong worktree | session compacted> — <actions suppressed>. Run /preflight at the start of your next session and this will land normally.`

Never print a cause that isn't the real one, and never print the cause without the remedy — a first run with no baseline lands nothing, and without that sentence it reads as a broken skill rather than a missing prerequisite.

**Scope is this repo only.** Dirty state detected elsewhere is reported, never written to.

Also read `~/.claude/mise-en-place/<key>-last-run.md`. If it is from today, read what was already landed, harvested and escalated, and do not redo it.

**Two records, never conflated.** The **run ledger** (`~/.claude/mise-en-place/<key>-last-run.md`, `mkdir -p` its directory first) is written at the end of a run and read at the start of the next; it records what a run landed, harvested and escalated, and never records process launches. **Kill authority is separate and comes only from this session's transcript** — a `run_in_background` Bash call you can point to. No such call → no kill, whatever the port scan shows.

**Resolve who "the operator" is** — every ownership rule depends on it and it is never safe to infer. `gh api user --jq .login` for GitHub, the Linear viewer for tickets. State both. If either cannot be resolved, that surface becomes report-only: ownership rules built on a guessed identity are decoration.

**The session scratchpad** is the scratchpad directory this session's harness context names. Resolve it here and state the path. If the session has no scratchpad, this run deletes nothing at all — say so.

**Done when:** baseline state, attribution mode, repo path and scratchpad path are all stated aloud.

### Phase 1 — Land the work

Nothing may exist in only one place: `uncommitted → committed → pushed → PR'd → merged or explicitly parked`.

```bash
git branch --show-current                       # empty => detached HEAD; see below
git status --porcelain                          # candidates
git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1 \
  && git log --oneline @{u}..HEAD \
  || echo "NO UPSTREAM — every local commit is unlanded"
```

**Detached HEAD** means you are on a specific commit rather than on a branch, so anything committed here would belong to nothing and be easy to lose. It **ends Phase 1 and disables every commit and push for the whole run** — Phase 4's and `/linear handoff`'s included. Phases 2–4 still run in report-only form; the harvest is written and reported uncommitted. Report `RUN STATUS partial` and name the detached SHA.

**No `origin`** → the ladder terminates at `committed`. That is a coverage finding, not a parked branch, and `git fetch origin` is skipped rather than errored.

`@{u}` on a branch with no upstream exits 128. Never run it unguarded — a never-pushed branch is exactly the case this phase exists to catch, and an unguarded failure reads as "nothing unpushed."

- **Yours and uncommitted** (created or modified this session) → stage each path **individually and literally**: `git add -- "<path1>" "<path2>" …`, one quoted argument per file. A directory is never a pathspec here — `git add -- src/` stages every dirty file beneath it, including paths the baseline classed not-yours. After staging, run `git diff --cached --name-only` and compare it set-for-set against the list you printed; **any staged path not on that list aborts the commit** — `git reset` and report it. Then commit with a real message. Print the path list first. Run `git diff --cached` and refuse if it contains a credential shape; stop and report rather than redacting.
- **Not yours** → never stage it. Report it in Still dirty as pre-existing. Someone else's WIP is not yours to land.
- **Committed but unpushed** → check preconditions, then push. If there is a stated reason not to, the reason goes in the handoff, not in your head.
- **Pushed without a PR** → open one, or record why it is parked.

**`ahead-only`** means your branch has commits origin doesn't, and origin has none you don't. Test it: `git rev-list --left-right --count @{u}...HEAD` prints `behind<TAB>ahead` — ahead-only is a left number of `0` and a right number above it. **`protected`** is a GitHub server-side setting you cannot see from git: `gh api "repos/:owner/:repo/branches/<branch>/protection" --silent 2>/dev/null && echo PROTECTED`; a 404 means unprotected, and if `gh` cannot answer, treat it as protected and report it.

**Push preconditions** — all must hold: `git fetch --no-tags origin` first (this updates your picture of what is on GitHub without touching your files — "is this branch safe to push" is a question about origin, and a stale answer is how you push over someone's work); branch is not the default and not protected; branch is **ahead-only**, or has no upstream at all (then `git push -u` creates it); no other worktree has this branch checked out (`git worktree list --porcelain`); no experimental/do-not-push veto was spoken this session. Behind or diverged → stop and report who else pushed. A rejected push is a finding, never a retry.

**PR preconditions** — `gh pr list --head <branch> --state all --json number,state` decides the ladder's terminal state, and the three states differ: an **open** PR → report its number and stop; a **closed-unmerged** PR → the branch was rejected before, so do not reopen and do not file a second — report it in Still dirty as `branch pushed, PR #<n> closed unmerged — needs a decision`; a **merged** PR with commits after its merge SHA → the ladder is incomplete, open a new PR for the remainder. Base is the resolved default, and **the PR must target `origin`** — check `gh repo view --json isFork -q .isFork` first, because on a fork `gh pr create` defaults its base to the **parent** repo and would open a public PR against someone else's project; pass `--repo "$(gh repo view --json nameWithOwner -q .nameWithOwner)"` explicitly, or treat a deliberate cross-fork PR as Posture B. **the build gate is stated, not assumed** — run the project's build (it dirties the tree, and its output is never attributable to the session — see Phase 0), and if it fails, is absent, or won't run, open the PR as `--draft` and say which. Never add reviewers, assignees, labels, or auto-merge.

**Done when:** every path in `git status --porcelain` is committed, or named as not-yours, or named in Still dirty — and the branch has a terminal state on the ladder.

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

Kill only a PID **this session's transcript shows this session launching**, re-verifying with `ps -o pid=,lstart=,command= -p <pid>` that the command still matches before signalling; `kill` (TERM) only. A port already in the baseline's `listening_ports` was the operator's, whatever is on it now. Anything you cannot attribute is left running — say what you left.

A surface off this table — CRM, call transcripts, a decision ledger — is `/housekeeping`'s sweep, not this one. Name it in Still dirty and move on.

**Done when:** every row has a status of `clean` / `<finding>` / `skipped — <reason>` / `unreachable`, and the table is emitted. A silent skip reads as a pass.

### Phase 3 — Reconcile

Contradictions are disagreements *between* surfaces, not problems *within* one. Use housekeeping's class names so findings stay comparable across the two skills — id format `<class>/<surface>:<record-id>`:

- **`superseded`** — a ticket's premise is contradicted by a newer merge or ruling ("not pushed" on a branch that merged).
- **`done-in-substance`** — intent already satisfied by something you can cite in a system you can read ("blocked on the migration script" for a script that merged). Where it turns on a client, a promise or a price, the outside-knowledge test applies and it escalates.
- **`orphaned-cadence`** — a recurring artifact past its period: no project update since the last two merges, a weekly status that stopped. (A project sitting in Backlog while you merged into it is `superseded` at project scope, not this.)
- **`canon-drift`** — a published artifact states a number the code has since changed. **Narrower than housekeeping's:** the reference here is the code, not the project's canon, and only artifacts this session published. A housekeeping run must not read a clean result here as a canon check.
- **`uncaptured-session`** — handled in Phase 4.

The other eight housekeeping detectors need canon, CRM or transcript sweeps this skill does not perform — running them on a partial inventory produces confident wrong findings at the moment nobody is watching.

#### The disposition rule

Apply in order.

1. **Evidence test.** Can you cite a specific artifact *in a system you can read* that settles it — a merge SHA, a passing check, a diff? If yes → **close**, and the close comment must cite it. **No close without a citation.**
2. **Outside-knowledge test.** Does settling it require knowing what a client was told, what was sent, what was promised, or what it costs? If yes → **escalate**.
3. **Default.** Unsure, both, or neither → **escalate**.

Closing someone's tickets changes the record of what was promised and delivered. Escalating wrongly costs the operator two minutes; closing wrongly rewrites history you had no right to.

**Close only tickets assigned to the resolved current user.** Unassigned is *not* yours — on a shared board it is the default state of everything nobody has picked up yet, including work a teammate is halfway through. Unassigned and other-owned tickets go in the escalation table.

**Every ticket mutation goes through `/linear track` then `/linear push`** — never a direct `save_issue` or `save_comment`. Two reasons, both bite: `push` runs the drift check that catches a ticket someone else moved since you read it, and the session buffer is the only thing `/linear handoff` can see. A closure written directly leaves the tally empty, and an empty tally routes the session update to the bound project by default.

**Counting the cap:** a mutation is a state or title change to an existing ticket. **Only two writes are exempt: the single escalation ticket, and the project status enum. Nothing else** — this skill files no other tickets and rewrites no ticket bodies (Posture C). The cap is per **day**, not per run; a re-run reads the prior ledger's count and continues from it.

Escalate **once**, in a single ticket with a disposition table, filed in the same project as the tickets it escalates. Do not file eight tickets; do not leave it only in chat, where it dies with the session.

**Done when:** every contradiction is closed with a citation, or in the escalation table.

### Phase 4 — Harvest

The transcript is about to disappear. Harvest what would cost the next session real time to rediscover:

- **Traps** — a tool that silently did the wrong thing; a build that was green and wrong.
- **Decisions and their reasons** — including what was rejected, which is what stops it being relitigated.
- **Measurements** — the before-state for the next comparison.
- **Dead ends** — so nobody retries them.

**Threshold:** cost more than ten minutes, *or* would have shipped silently. The second class matters more.

**Where it goes.** Resolve `root=$(git rev-parse --show-toplevel)` first and make every rung absolute — the shell's working directory persists between calls and may be a subdirectory. Take the first that applies:

1. An existing `$root/journal` **real directory** → `$root/journal/YYYY-MM-DD-<slug>.md`.
2. Otherwise an existing `$root/.linear` **real directory** → `$root/.linear/journal/YYYY-MM-DD-<slug>.md`.
3. Otherwise `~/.claude/mise-en-place/<key>/journal/YYYY-MM-DD-<slug>.md` — **outside the repo, never committed.**

Test each in-repo rung with `[ -d "$path" ] && [ ! -L "$path" ]`. `[ -d ]` alone is true for a symlink, and a `journal` symlinked outside the repo puts transcript-derived material out of the tree, where `git check-ignore` reports "not ignored" and the run would wrongly call it durable.

**This skill never creates `journal/` in a repo that does not have one.** An existing `journal/` or `.linear/` is the repo opting in; creating one is deciding on someone else's behalf that their history is a good place for your engineering notes. On rung 3 say so plainly: `HARVEST: written outside the repo to <path> — this repo has no journal/ or .linear/.`

**Test the destination before writing** — `git check-ignore -q <path>`. A harvest written to a gitignored path is local-only: it never commits, never reaches the next clone, and looks like success. `.linear/` in particular **is gitignored in some repos and tracked in others**, so this is repo-dependent and must be checked every run, not assumed.

If the chosen destination is ignored, fall through to the next rung. If **every** rung is ignored, write to `journal/` anyway and report on its own line: `HARVEST: written to <path>, which is gitignored — local-only, not durable. Track it or move it to keep it.` Never report a harvest as durable when git will not carry it.

If the file already exists, **append** under `## Second pass — <time>`. Never overwrite a harvest.

**Then land it — only on rungs 1 and 2.** A rung-3 harvest lives outside the repo and is never committed; say where it went and move on. For rungs 1 and 2 the harvest is a file this run created, so committing it is Posture A and pushing it is Posture B — but nothing else will do it: Phase 1 already ran, and leaving it uncommitted means the final check reports a dirty tree and the "durable record" exists only on this machine. Commit it by explicit pathspec and push, subject to the same **commit and push** preconditions as Phase 1 — **including the branch rule. If the current branch is the default or protected, do not commit: Posture C outranks this step.** Report `HARVEST: written to <path>, uncommitted — <branch> is the default/protected branch.` Re-run the Phase 1 credential check on the staged diff first: the harvest is transcript-derived and is the likeliest file in the run to carry a token or a client figure.

**Track it as well as writing it.** Log the traps and dead ends to the session buffer with `/linear track`. Handoff's Traps section reads the buffer, not the journal — skip this and the update ships with that section empty on the day it mattered. If the branch has an open PR, it lands there; say which commit carried it. If the destination turned out to be gitignored, there is nothing to commit — report it as local-only instead.

Harvest engineering knowledge only. Commitments, figures and rulings stated in conversation are `/housekeeping`'s harvest and need its provenance classes.

**Done when:** the harvest is written and its path reported — or, under `--dry-run`, its intended path and content are printed — or the run states explicitly that the session produced nothing worth keeping.

### Phase 5 — Hand off, verify, report

Order matters: `/linear handoff` itself writes `.latest-status.md` and `.linear/last-handoff.md` and **commits them**. Running it before the final check is what keeps the report true.

1. Resolve the destination (below), then run `/linear handoff --to <project>`. Handoff previews the update and waits for approval before posting — **that preview is this skill's Posture B gate** for the outward status update. Surface it; never approve it on the operator's behalf. Skip entirely if the repo has no Linear binding (Phase 2's test); say so and rely on the harvest.
2. Push the commit it made — **if it made one.** Record `HEAD` *before* calling handoff and compare against it (`git log <saved>..HEAD`); `@{u}..HEAD` shows every unpushed commit, not just handoff's, and would silently re-push Phase 1 work on a branch Phase 1 could not push. `.latest-status.md` and `.linear/last-handoff.md` are gitignored in some repos, in which case handoff's commit step is a no-op and there is nothing to push. Check with the **guarded** upstream form from Phase 1 — never bare `@{u}`, which exits 128 with no upstream; a branch with no upstream means everything is unpushed and the Phase 1 push preconditions apply. Pushing nothing is fine; reporting a push that did not happen is not.
3. Re-run `git status --porcelain` and the guarded upstream check from Phase 1.
4. Write the run ledger `~/.claude/mise-en-place/<key>-last-run.md` (`mkdir -p` first). It must carry at minimum `date`, `run_status`, `landed` (branch, old→new SHAs, PR numbers), `ticket_mutations` as a **count** so tomorrow's cap continues from it, `escalation_ticket` id if filed, `harvest` path, and `findings:` as `<class>/<surface>:<record-id>` ids. Prose alone silently resets the daily cap to zero.
5. Give the report below. Lead with what is unresolved.

Do not treat `.latest-status.md` or `.linear/last-handoff.md` as Phase 1 leftovers — handoff owns them.

#### Where the handoff posts

Resolve this **here**, before handoff runs, and pass it as `--to`. Handoff infers from the session buffer; a code-only day leaves that buffer empty, and empty falls back to the *bound* project — which in a tool's own repo is the tool's own project. That fallback is right when you were working **on** the tool and wrong every other time.

Two cases, and they are not the same:

- **On the tool** — the session changed the tool's own source. Destination is the tool's own project.
- **With the tool** — the session did client, prospect, or internal work. The destination is that project. The binding records which directory you typed in, not whose work it was.

Resolve in order, stop at the first that fires:

**The buffer** is the session's local record of Linear activity, written by `/linear track`. **The tally** is derived from it: the list of projects this session's tickets actually belong to, with a count each. They are not the same object — an empty tally means the session touched no tickets, not that it did no work.

1. **A remembered binding** for this repo in `~/.claude/mise-en-place/project-map.yml` → use it, state it. This is how a repo whose name does not resemble its project (`pvp-website` → *People v. Profit*) stops costing a question every night.
2. **One project in the tally** (linear's referenced-project tally) → that project. State it, do not ask.
3. **Two or more in the tally** → **STOP AND ASK.** Name each with its ticket count, propose the highest as primary, ask: primary only, or both. Never pick silently and never fan out silently — each post is a separate outward notification.
4. **Tally empty, every changed path inside the tool's own tree** → the bound project. State it: `DESTINATION: <project> (bound; this session was on the tool itself).`
5. **Tally empty, anything changed outside that tree** → **STOP AND ASK.** Do not fall back. Lead with your best inference and its evidence — the repo's `org/repo`, the branch name, the client named in the session goal or this session's commit messages — and offer the bound project as the alternative.

**When you ask, record the answer** in `~/.claude/mise-en-place/project-map.yml` as `<org/repo>: <project>` so rung 1 catches it next time. Ask once per repo, not once per night. Re-ask only if the answer stops matching the tally.

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

**On abort, write the harvest first.** Before surfacing any error that ends the run, dump Phase 4 material and say where it went. It is the only artifact a re-run cannot recover. **Under `--dry-run` this stays a non-write:** print the material inline under `## Harvest (dry run — not written)` so the operator can save it, and emit `WOULD: write <path>`.

## Composition

- Review is not part of the closedown. If this session's work needs review, Phase 1 opens the PR and you run `/ai-router review <pr>` after — outside this skill. If `/ai-router` isn't configured, note that the code went unreviewed; that is a finding, not a blocker.
- Ends by calling `/linear handoff`, which writes and commits the continuity docs.
- The opening bookend is `/preflight`, which writes the session-start baseline Phase 0 reads.

## Load REFERENCE.md when

Before mutating Linear (workspace status names and start-date behaviour will bite you), before filing the escalation ticket (template), or before the process and filesystem sweep.
