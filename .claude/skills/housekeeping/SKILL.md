---
name: housekeeping
version: "1.2"
description: >-
  Recovery command for when a project is in the weeds. Stops all forward work,
  sweeps every surface the project lives on (tickets, pages, CRM, transcripts,
  git, agent threads, published artifacts), finds where those surfaces now
  contradict each other, harvests everything the current session learned but
  never wrote down, then hands back a short ranked list of the next 3–5 moves.
  All write-backs are gated behind explicit approval. Not a status report —
  it reconciles and repairs. Invoked on a felt state mid-task, never on a
  schedule: for the end-of-day closedown that lands work and hands off, use
  /mise-en-place instead.
trigger: /housekeeping
---

# housekeeping — Stop, Sweep, Reconcile, Re-aim

## What this is

A *recovery* command, not a status command. The operator's framing is the spec:

> "It is like when I was a waiter at a restaurant and you get into the weeds and
> you're basically so behind and you don't know how to get out. The best thing to
> do is to slow down to a crawl, stop, take stock of everything, organize and
> prioritize, and then go back at it with an extremely clear vision of the next
> three to five steps to take."

Four load-bearing requirements fall out of that:

| Phrase | Requirement |
|---|---|
| "slow down to a crawl, stop" | **Suspend** delivery work. Do not try to be efficient. Do not do the work you find. |
| "take stock of everything" | Coverage is **all surfaces**, not the convenient ones. Missing a surface is worse than a slow run. |
| "organize and prioritize" | Output is **ordered**, with exactly one thing at the top. Not a list of equals. |
| "next three to five steps" | Output is **capped at 3–5 actions**. A pass that returns 20 next actions has failed. |

The job: answer **"is the house clean?"** with evidence — and if not, clean it.

## What this is NOT

- **Not a status report.** A status report describes; housekeeping reconciles and repairs.
- **Not a standup.** No "what happened yesterday."
- **Not a re-plan.** Strategic contradictions get filed as decisions for the operator — never resolved by the skill.
- **Not the work.** Never advance a deliverable during the pass. If the deck is wrong, say so and stop. Doing the work is what put you in the weeds.
- **Not a silent mutator.** Nothing is written to any project surface without the explicit approval gate (Phase 5). The single exception: local bookkeeping under `~/.claude/housekeeping/` (config, last-run report), which lives outside every repo and shared surface — narrate those writes, don't ask.
- **Not a completeness ritual.** An unreachable surface is announced loudly, never papered over with a clean-looking report.
- **Not the end-of-day closedown.** This is triggered by a felt state mid-task, not by the clock, and it lands nothing — forward work stops. If you are simply stopping for the day and want the session's work committed, pushed, PR'd, settled tickets closed, processes killed and a handoff written, that is `/mise-en-place`. It acts where this one asks.

## Triggers

Invoked manually — it's a felt state, respect the instinct. But **recommend it**
(don't run it) when you observe:

- More than ~5 items at top priority simultaneously
- A recurring cadence artifact more than one period stale
- A session that surfaced >3 new figures or commitments
- A conversation compacted more than once
- A deliverable pushed while an upstream decision ticket is open
- Operator language: "in the weeds", "messy", "lost track", "what else", "are we clean", "baselined"

**`--quick` mode:** metadata-only. Skip all body/transcript pulls, including
Phase 2's flag-driven pulls; body-dependent detectors (dead-figure,
numeric-drift, done-in-substance, canon-drift, provenance) run only on values
visible in titles/metadata and are listed in COVERAGE as `degraded (quick)`.
Phase 3 runs in full — the session is already in context — but any record it
proposes that carries a figure or commitment is annotated `quick — not
verified against canon`, and the annotation carries into the Phase 5 list.
Title the report `HOUSEKEEPING (QUICK)` so it is never mistaken for a full
baseline.

## Bound surfaces: every agent has three

Currents, Linear, and Agent Mail are **bound surfaces** — swept every run when
the agent has them. A bound surface the agent lacks or cannot reach is a
COVERAGE finding, never a silent skip and never a reason to abort the pass.

- **Linear** — there is always exactly **one bound project** the agent works in.
  All ticket findings, re-ranks, and next steps anchor to that project.
- **Currents** — the agent generally knows the areas it works in. If it does
  not, map its **blast radius** from anchors it can justify — pages it authored
  or edited, pages linked from the bound Linear project, pages the operator
  names — following links at most 2 hops out. Never enter areas owned by other
  agents or marked restricted; note the boundary instead. Confirm the
  discovered radius with the operator before saving it to config; later
  expansions are proposed in Phase 5, never saved silently.
- **Agent Mail** — the agent's own inbox: unread, unanswered outbound, and
  anything read-but-never-replied.

## Config: the surface list

Per-project, at `~/.claude/housekeeping/<project-key>.yml`. Key = the bound
Linear project's name, lowercased, runs of non-alphanumerics collapsed to `-`,
plus `-` and the first 8 hex chars of the sha1 of the UTF-8 bytes of the
project's **stable Linear project ID** (e.g. `Fundraise 2026` →
`fundraise-2026-a1b2c3d4`; hash the raw name only if no ID is available — the
ID keeps same-named projects in different workspaces from colliding). Never
derived from git; the repo is one optional surface and may be absent. On invocation, list `~/.claude/housekeeping/*.yml`
and match this project by the `project:` field: exactly one match → use it;
ambiguous → ask; none → run the first-run interview (ask for the bound Linear
project *first* so the key can be derived), then write the config and read its
path back to the operator.

```yaml
project: <bound Linear project name — the key derives from this>
bound:               # the three per-agent surfaces; always swept
  linear: <the one bound project>
  currents: [<areas/pages this agent works in>]   # discovered by traversal if unknown
  agent_mail: <this agent's inbox>
surfaces:            # everything else the project lives on; sweep ALL every run
  - git: <repo path>   # preflight-style read-only checks (branch, tree, sync, PRs, stale); run /preflight for the actual sync
  - artifacts: <known published-artifact URLs, or "all">   # enumerate via the Artifact tool's list action
  # e.g. attio (incl. call recordings), granola, drive, designsync,
  # visible, carta — whatever this project actually lives on
continuity:          # read in Phase 1; drafts written via the Phase 5 gate
  - .latest-status.md
  - journal/
  - currents: <always-current page, if any>   # shared — always itemised individually
canon: <where the one true set of figures/decisions lives>
stalled_after_hours: 24   # stalled-thread threshold
sweep_window_days: 14     # first-run window for evidence streams
```

**The last-run report** lives at `~/.claude/housekeeping/<project-key>-last-run.md`.
Write it as soon as Phase 2 findings exist, marked `status: in-progress`; update
it at each phase boundary; Phase 6 finalises it. A file left `in-progress` means
the prior run ended early — say so in the next run's COVERAGE and re-propose any
approved-but-unapplied mutations it records. End each report with a `findings:`
list of stable ids, one per finding, formed `<class>/<surface>:<record-id>`
(e.g. `dead-figure/linear:ABC-42`); a finding is a **repeat** iff its id appears
in the previous report's list — repeats signal a systemic problem, not a
tidiness problem. (Lookback is one run by design; a finding resolved and
recurring later reads as new.)

## The phases — strict sequence, each gates the next

Do not parallelise the *phases* into a soup — each gates the next; the feeling
of the command should be deliberate. Within Phase 1, sweep independent surfaces
in parallel.

### Phase 0 — STOP
Announce the pass. Name any in-flight delivery work and confirm it is parked.
**No tool calls in this phase.** It is a mode change and should read like one.

### Phase 1 — INVENTORY (read-only, parallel, exhaustive)

**Baseline first.** Orient on the bound surfaces: the Linear bound project (all
non-closed tickets, milestones, cycle, recent comments), the agent's Currents
blast radius (map it now if unknown, including pending suggestion counts —
unapproved state is invisible state), the agent's own Agent Mail inbox, and the
continuity inputs: `.latest-status.md`, latest `journal/` entry, handoff/context
docs, and the previous run's report (the input for repeat-finding detection).
This is how the agent establishes *where it is* before judging where anything
else is.

Then sweep every surface in the `surfaces:` list. Per surface capture: id,
title, state, priority, owner, dates, last-updated. Evidence streams (calls,
transcripts, notes, mail) are swept from the previous run's timestamp; on a
first run, sweep the last `sweep_window_days`. Go deeper into history only when
a Phase 2 finding requires it. Prefer metadata sweeps — but the body-dependent
detectors (dead-figure, numeric-drift, done-in-substance, provenance) pull
full bodies up front for open or since-last-run-changed records in the bound
project and for canon sources, since a stale figure living only in a body is
otherwise invisible; everything else pulls bodies only when a Phase 2 finding
requires it. Delegate bulk reading to subagents, but **require
verbatim quotes with attribution in return** — a subagent's paraphrase is not
evidence.

**Report coverage explicitly.** M = the 3 bound surfaces + every `surfaces:`
entry + each configured `continuity:` input; a missing or unreadable
continuity input is named in COVERAGE like any other miss. A surface that
errors or returns partial data after one retry is
unreachable — say which part was missing. "Swept 9 of 10 surfaces; X
unreachable" is a valid and required output; an unreachable surface is a
*finding*, never a silent omission.

### Phase 2 — RECONCILE (the core value)
Run the thirteen detectors across the inventory:

1. **priority-inflation** — count open items at top priority; above ~5, force a re-rank rather than reporting.
2. **dead-figure** — extract numeric claims from records; diff against canon; flag figures that disagree with or don't exist in canon.
3. **numeric-drift** — build a figure ledger keyed by metric name; any metric with >1 distinct value across surfaces is a conflict, ranked by whether it was stated externally.
4. **superseded** — records whose stated premise is contradicted by a newer ruling or ticket; propose close/cancel/merge with the superseding reference.
5. **advisor-conflict** — contested claims from different people; build a decision ledger row (`claim | who | when | verbatim | provenance | status`, provenance from detector 11's classes). Present both sides verbatim with credentials and recency — **recency is not authority**. Make the conflict visible and force a decision record; never resolve it.
6. **uncaptured-session** — handled in Phase 3; reports under UNCAPTURED, not FINDINGS.
7. **orphaned-cadence** — any recurring artifact whose latest instance is older than its period.
8. **stalled-thread** — outbound requests to agents/people older than `stalled_after_hours` (config; default 24) with no reply, joined against what they block.
9. **done-in-substance** — ticket intent already satisfied per transcript evidence; propose closure with the citation.
10. **manufactured-urgency** — for every overdue item, ask whether the deadline has an external source; flag self-imposed deadlines as such.
11. **provenance** — every claim carried into a record needs a source class: `verbatim-transcript` / `operator-ruling` / `agent-analysis` / `simulation`. Anything not verbatim or operator **cannot be a constraint**.
12. **canon-drift** — compare shipped artifacts (decks, sites, published pages) against current canon; list divergences.
13. **duplicate-artifact** — enumerate artifacts per class; identify the canonical one; flag the rest.

Each finding:

```
finding: <one line>
class:   <detector name above>
evidence: <surface + id + quote/value + timestamp>
conflicts-with: <the other surface + id + value>
severity: blocks-external-send | blocks-decision | misleads-tomorrow | cosmetic
proposed-action: close | cancel | merge | re-date | correct-figure | file-decision | ask-operator
```

**Severity ladder:** "would we send something wrong to an outsider?" outranks
"is the board tidy."

### Phase 3 — CAPTURE (the session harvest)
Re-read the current session with one question: **what did we learn or decide
here that exists nowhere but this conversation?** Look for: commitments to/by
named people with dates · rulings the operator gave in passing · figures stated
(especially externally) · named opportunities (intros, leads, discovered assets)
· risks noticed but not filed · corrections of prior beliefs. For each, propose
a record with a draft body and priority. **Create nothing silently** — feeds the
Phase 5 gate. If this session has been compacted, say so at the top of
UNCAPTURED — the harvest covers only the surviving window, and anything known
only from a compaction summary is a paraphrase: source it `agent-analysis`, a
lead to verify, never a constraint. This phase is why housekeeping is worth
running even when the board *is* clean.

### Phase 4 — PRIORITIZE

**The prioritization round (Q&A gate).** If the findings say a re-rank is
needed — priority inflation, conflicting priorities, a stale board, or the
skill simply can't tell what the ball is — do **not** re-rank unilaterally.
Enter a structured Q&A with the operator to rebaseline. Ask in order, one at a
time, each grounded in evidence from the sweep:

1. **The ball** — "Is `<X>` still the one thing this project is trying to do?" (state your best inference from the sweep; let the operator correct it)
2. **Dead or alive** — one batched question listing every suspect ticket: "Evidence says these are done/superseded — close which?"
3. **Real deadlines** — one batched question listing every overdue item: "Which of these dates are externally imposed?"
4. **The cut** — "Of the N items at top priority, which ≤3 actually matter this week?"
5. **Blockers** — "Anything blocking that I can't see in these surfaces?"

Skip questions the evidence already answers unambiguously; never exceed ~6
questions — the cap counts questions asked, so batching keeps every item
covered. The answers are operator rulings — record them with `operator-ruling`
provenance.

**Then the baseline readout.** Collapse everything into one ordered list:

1. **One thing is first.** Name it and say why.
2. **Cap actionable at 3–5**; the rest goes to "parked, with reasons."
3. **Every item anchors to a Linear ticket** in the bound project — existing, or proposed for creation in Phase 5. No free-floating actions.
4. Every item: **exactly one owner** (operator / this agent / a named peer agent / external).
5. Every item: a **doneness test**.
6. Distinguish **blocked** from **not started**; name the blocker and its owner.
7. **Re-rank the existing board** — don't append to it. If nine things are top-priority, at most a couple survive; demotions get a stated reason, citing the operator's Q&A rulings where they apply.

### Phase 5 — WRITE BACK (gated)
Present the full proposed mutation set — closures, cancellations, re-dates,
figure corrections, new tickets, decision records, **and the continuity-surface
drafts** (`.latest-status.md`, journal entry, any always-current page; flag the
local ones low-risk so the operator can batch-approve) — as a reviewable list,
and **wait**. Default is no writes. Offer "apply all" and selective approval —
but "apply all" covers only the non-destructive, non-externally-visible items.
These always itemise individually, each needing its own explicit yes — the
list is exhaustive, not judgment-based: closing or cancelling a ticket,
editing any shared or published page, correcting a figure anywhere an outsider
could see it, sending any message, and anything else that leaves the
operator's own local surfaces. Say this scope when offering "apply all."
Continuity drafts are **approved** here but **written only in Phase 6** —
exactly once. After applying the rest of the approved set, verify and report
what actually landed, including partial failures. No mutation class is safe to
auto-apply; start fully gated.

### Phase 6 — THE WAY OUT
The payload everything above earns: **the next 3–5 steps, in order, the first
one unambiguous.** Short. No hedging. Then write the continuity updates
approved in Phase 5 — this is the sole phase that writes them, and nothing
else. The only ungated write here is finalising
this run's report at `~/.claude/housekeeping/<project-key>-last-run.md` (see
Config); narrate the save.

## Output format

One report, fixed shape, comparable across runs:

```
HOUSEKEEPING — <project> — <timestamp> [— QUICK]

COVERAGE      swept N of M surfaces; <any misses, named>; <detectors degraded/not run>
VERDICT       clean | drifting | in the weeds
              <one sentence of why>
              a run with any unreachable surface cannot report clean —
              cap at drifting and name the hole

THE BALL      <what this project is actually trying to do, one line>
              <is current activity pointed at it? yes/no + evidence>

FINDINGS      by severity, most severe first
              each: finding / evidence / conflict / proposed action
              repeat findings from the last run marked as such

UNCAPTURED    session learnings with no record; each: proposed record + priority

CONFLICTS     decision ledger — contested claims, who said what, status
              (for the operator to rule on, not the skill to resolve)

RULINGS       operator answers from the prioritization round, verbatim
              (each becomes operator-ruling provenance for the re-rank)

RE-RANK       the bound Linear project's board, reordered, demotions explained

NEXT 3–5      ordered, one owner each, doneness test each,
              each anchored to a Linear ticket (existing or proposed)
              #1 stated so plainly it can be started without another question

PARKED        deliberately not being done, with reasons
```

**Tone:** plain, no cheerleading, never pad. If the state is bad, say so in one
sentence and move to the fix. The operator is already stressed; the report's job
is to reduce load, not perform thoroughness.

## Acceptance test

Run it twice in a row, applying the first run's approved write-backs in
between: the second report should be near-empty. (Declined write-backs
correctly reappear as repeat findings — never suppress them to look clean.)
And the real test — the operator reads NEXT 3–5, knows exactly what to do, and
stops feeling behind.
