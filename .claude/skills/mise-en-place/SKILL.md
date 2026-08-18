---
name: mise-en-place
version: "1.0"
description: >-
  End-of-day shutdown ritual for a working repo. Run when you are finished for
  the night, not when you are lost. Lands the session's work up the ladder
  (commit, push, open a PR — never merge), sweeps git, GitHub, Linear, and the
  processes and scratch files the session started, closes tickets that a merge
  or a green build has already settled, harvests the session's traps and dead
  ends into the durable record, then calls /linear handoff. Announces each write
  before it runs and stops to ask before anything risky. Always states what is
  still dirty. For a mid-task re-baseline when you have lost track of where the
  project is, use /housekeeping instead.
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

The load-bearing contract. Three postures; nothing lives outside them.

### Posture A — ANNOUNCE THEN ACT

State the operation and its target in one line, run it, confirm the result with its id (SHA, PR number, ticket id).

- `git commit` of paths this session created, on a non-protected branch, staged by explicit pathspec.
- `git push` of that branch to its own `origin/<same-name>` upstream.
- `gh pr create` for that branch against the resolved default base.
- `git fetch --no-tags origin`, `git remote prune origin`.
- Setting a Linear project's **status enum**; correcting an auto-stamped start date.
- Writing an **empty** Linear project description.
- Closing or retitling a ticket that is unassigned or assigned to the operator, that shipped reality settles, within the 5-mutation cap.
- Filing **one** escalation ticket (or updating today's existing one).
- Writing the harvest and the run ledger.
- Killing a process this run's ledger recorded launching.

### Posture B — STOP AND ASK

Present the proposal and **wait**. Default is no write.

- Anything requiring force-push, history rewrite, `--no-verify`, or a protected/default branch.
- Committing when Phase 0 attribution is UNKNOWN.
- Overwriting a **non-empty** Linear project description (show the diff).
- Posting a **project status update** — always, including health. It is an outward notification.
- Closing a ticket that turns on commercial, client, or strategic context.
- More than **5** ticket-state mutations in one run (present the set; apply none).
- Deleting a local branch.

### Posture C — NEVER

No announcement and no approval makes these allowed. They are outside the skill.

- **Merging.** No `gh pr merge`, no `--auto-merge`, no enabling auto-merge, no local merge. Merging is a decision, never housekeeping. Do not ask — the answer is not yours to seek during a shutdown.
- **Force-push, history rewrite, `reset --hard`, `branch -D`, `rebase`, `cherry-pick`, `--no-verify`.** Never retry a rejected push by any means.
- **Committing a file this session did not create**, or staging with `git add -A` / `git add .` / `git add -u` / `git commit -a` / any glob.
- **Committing to or pushing the default or a protected branch.**
- **Creating, switching, or renaming a branch or tag.**
- **Pushing work the operator called experimental, a spike, throwaway, or said not to push.** One such statement is a permanent veto for the run.
- **Deleting any file outside the session scratchpad**, whoever created it. Never delete a gitignored file — those are local config (`.env`, `settings.local.json`, caches).
- **Killing any process not in this run's ledger**; never `kill -9`, `pkill`, or `killall`.
- **Touching a ticket assigned to or created by anyone other than the operator.**
- **Doing the work you find.** "While cleaning up I noticed X and fixed it" is a new task with no review. Note it; do not do it.
- **Reporting clean** when a surface was unreachable, a mutation failed, a phase was suppressed, or attribution was degraded.

> **If a situation isn't clearly inside Posture A, it's a recommendation, not an action.**

Reporting something that was yours costs one line. Acting on something that was not is unrecoverable.

## Procedure

Six phases, in order — phase 3 needs phase 2's findings, so do not parallelise *across* phases. Within phase 2, sweep independent surfaces in parallel. Announce each phase as you enter it.

Each phase states **Done when**. A phase that finds nothing says so in one line and moves on.

### Phase 0 — Baseline and scope (no writes)

Attribution is a diff against a snapshot, never a judgment call. Read the baseline preflight wrote at session start:

```bash
# same <repo-key> derivation as preflight Step 3
cat "$HOME/.claude/preflight/<repo-key>.session-start.json"
```

**The baseline is valid only if** it is the most recent preflight run for this repo **and** less than 16 hours old. Otherwise treat it as absent.

**A path is yours only if both hold:** it appears in this session's own Write/Edit/Bash write calls, **and** it is absent from the baseline `porcelain`. One signal is not enough. **If the session was compacted**, the first signal is unreliable — attribution is UNKNOWN regardless of the second.

**If the baseline is absent, stale, or attribution is UNKNOWN → REPORT-ONLY ATTRIBUTION.** The run commits nothing, kills nothing, deletes nothing. It may still push and PR commits it made earlier this session and can name by SHA. Say so on its own line: `ATTRIBUTION: baseline absent — commits and kills suppressed.` Never silently degrade.

**Scope is this repo only.** Dirty state detected elsewhere is reported, never written to.

Also read `~/.claude/mise-en-place/<repo-key>-last-run.md`. If it is from today, read what was already landed, harvested and escalated, and do not redo it.

**Done when:** baseline state, attribution mode, repo path and scratchpad path are all stated aloud.

### Phase 1 — Land the work

Nothing may exist in only one place: `uncommitted → committed → pushed → PR'd → merged or explicitly parked`.

```bash
git branch --show-current                       # empty => detached; stop and report
git status --porcelain                          # candidates
git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1 \
  && git log --oneline @{u}..HEAD \
  || echo "NO UPSTREAM — every local commit is unlanded"
```

`@{u}` on a branch with no upstream exits 128. Never run it unguarded — a never-pushed branch is exactly the case this phase exists to catch, and an unguarded failure reads as "nothing unpushed."

- **Yours and uncommitted** → stage by explicit pathspec (`git add -- <path>`), then commit with a real message. Print the path list first. Run `git diff --cached` and refuse if it contains a credential shape; stop and report rather than redacting.
- **Not yours** → never stage it. Report it in Still dirty as pre-existing. Someone else's WIP is not yours to land.
- **Committed but unpushed** → check preconditions, then push. If there is a stated reason not to, the reason goes in the handoff, not in your head.
- **Pushed without a PR** → open one, or record why it is parked.

**Push preconditions** — all must hold: `git fetch --no-tags origin` first; branch is not default or protected; branch is **ahead-only** (behind or diverged → stop and report who else pushed); no experimental/do-not-push veto was spoken this session. A rejected push is a finding, never a retry.

**PR preconditions** — `gh pr list --head <branch> --state all` is empty (else report the existing number); base is the resolved default; **the build gate is stated, not assumed** — run the project's build, and if it fails, is absent, or won't run, open the PR as `--draft` and say which. Never add reviewers, assignees, labels, or auto-merge.

**Done when:** every path in `git status --porcelain` is committed, or named as not-yours, or named in Still dirty — and the branch has a terminal state on the ladder.

### Phase 2 — Sweep the workstation

| Surface | Looking for |
|---|---|
| **Git** | Uncommitted, unpushed, branches tracking a deleted remote, stray worktrees |
| **GitHub** | Open PRs (yours this session vs pre-existing), draft PRs that are done, unresolved review threads, failing or **absent** CI |
| **Linear** | Ticket state vs reality, project status, empty description |
| **Processes** | Dev servers, watchers, tunnels this run's ledger recorded starting |
| **Filesystem** | Untracked non-ignored leftovers, files written outside the scratchpad |
| **Artifacts** | Anything published this session that is now stale |

**Absence is a finding.** "No CI configured" means the local build was the entire gate — that changes what a green build is worth. Say so.

Kill only ledger-recorded processes, verifying the PID is still the same process before signalling; `kill` (TERM) only. Anything you cannot attribute is left running — say what you left.

A surface off this table — CRM, call transcripts, a decision ledger — is `/housekeeping`'s sweep, not this one. Name it in Still dirty and move on.

**Done when:** every row has a status of `clean` / `<finding>` / `skipped — <reason>` / `unreachable`, and the table is emitted. A silent skip reads as a pass.

### Phase 3 — Reconcile

Contradictions are disagreements *between* surfaces, not problems *within* one. Use housekeeping's class names so findings stay comparable across the two skills — id format `<class>/<surface>:<record-id>`:

- **`superseded`** — a ticket's premise is contradicted by a newer merge or ruling ("not pushed" on a branch that merged).
- **`done-in-substance`** — intent already satisfied ("waiting on client" for a thing that shipped).
- **`orphaned-cadence`** — project sits in Backlog while you merged twice this week.
- **`canon-drift`** — a published artifact states a number the code has since changed.
- **`uncaptured-session`** — handled in Phase 4.

The other eight housekeeping detectors need canon, CRM or transcript sweeps this skill does not perform — running them on a partial inventory produces confident wrong findings at the moment nobody is watching.

#### The disposition rule

Apply in order.

1. **Evidence test.** Can you cite a specific artifact *in a system you can read* that settles it — a merge SHA, a passing check, a diff? If yes → **close**, and the close comment must cite it. **No close without a citation.**
2. **Outside-knowledge test.** Does settling it require knowing what a client was told, what was sent, what was promised, or what it costs? If yes → **escalate**.
3. **Default.** Unsure, both, or neither → **escalate**.

Closing someone's tickets changes the record of what was promised and delivered. Escalating wrongly costs the operator two minutes; closing wrongly rewrites history you had no right to.

Escalate **once**, in a single ticket with a disposition table, filed in the same project as the tickets it escalates. Do not file eight tickets; do not leave it only in chat, where it dies with the session.

**Done when:** every contradiction is closed with a citation, or in the escalation table.

### Phase 4 — Harvest

The transcript is about to disappear. Harvest what would cost the next session real time to rediscover:

- **Traps** — a tool that silently did the wrong thing; a build that was green and wrong.
- **Decisions and their reasons** — including what was rejected, which is what stops it being relitigated.
- **Measurements** — the before-state for the next comparison.
- **Dead ends** — so nobody retries them.

**Threshold:** cost more than ten minutes, *or* would have shipped silently. The second class matters more.

**Where it goes** — first that applies:
1. An existing `journal/` directory → `journal/YYYY-MM-DD-<slug>.md`.
2. Otherwise an existing `.linear/` → `.linear/journal/YYYY-MM-DD-<slug>.md`.
3. Otherwise create `journal/` and say that you did.

If the file already exists, **append** under `## Second pass — <time>`. Never overwrite a harvest.

Harvest engineering knowledge only. Commitments, figures and rulings stated in conversation are `/housekeeping`'s harvest and need its provenance classes.

**Done when:** the harvest is written and its path reported — or the run states explicitly that the session produced nothing worth keeping.

### Phase 5 — Hand off, verify, report

Order matters: `/linear handoff` itself writes `.latest-status.md` and `.linear/last-handoff.md` and **commits them**. Running it before the final check is what keeps the report true.

1. Run `/linear handoff` (skip if the repo has no Linear binding; say so and rely on the harvest).
2. Push the commit it just made.
3. Re-run `git status --porcelain` and the guarded `@{u}..HEAD` check.
4. Write `~/.claude/mise-en-place/<repo-key>-last-run.md`.
5. Give the report below. Lead with what is unresolved.

Do not treat `.latest-status.md` or `.linear/last-handoff.md` as Phase 1 leftovers — handoff owns them. Route ticket mutations through `/linear track` + `/linear push` so they reach the session buffer; otherwise handoff's destination resolution cannot see them and the update misroutes.

**Done when:** the tree is verified *after* handoff's commit, and the report is delivered.

## Output format

```markdown
RUN STATUS  <complete | partial (stopped at phase N) | attribution-degraded>
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

**On abort, write the harvest first.** Before surfacing any error that ends the run, dump Phase 4 material and say where it went. It is the only artifact a re-run cannot recover.

## Invocation

```
/mise-en-place              # full closedown
/mise-en-place --dry-run    # no writes anywhere; report what it would do
/mise-en-place --land-only  # skip Phase 3 reconcile; everything else runs
```

`--dry-run` performs **no external writes**: no commits, pushes, PRs, kills, ticket mutations, harvest, or `/linear handoff`. Each action is emitted as `WOULD: <action>`, each guarded action as `WOULD ASK: <action>`. Report titled `MISE EN PLACE (DRY RUN)`.

`--land-only` skips Phase 3 only. Report titled `MISE EN PLACE (LAND ONLY)`, with `Reconciled` reading `not run`. **Phase 4 always runs** — a session that shipped nothing is exactly the session whose only value is the harvest. `--dry-run` wins over `--land-only` on write posture.

Safe to re-run: the second run reads the first run's ledger and will not re-harvest, re-file, or re-post.

## Composition

- Review is not part of the closedown. If this session's work needs review, Phase 1 opens the PR and you run `/ai-router review <pr>` after — outside this skill. If `/ai-router` isn't configured, note that the code went unreviewed; that is a finding, not a blocker.
- Ends by calling `/linear handoff`, which writes and commits the continuity docs.
- The opening bookend is `/preflight`, which writes the session-start baseline Phase 0 reads.

## Load REFERENCE.md when

Before mutating Linear (workspace status names and start-date behaviour will bite you), before filing the escalation ticket (template), or before the process and filesystem sweep.
