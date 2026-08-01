---
name: housekeeping
version: "1.0"
description: >-
  Recovery command for when a project is in the weeds. Stops all forward work,
  sweeps every surface the project lives on (tickets, pages, CRM, transcripts,
  git, agent threads, published artifacts), finds where those surfaces now
  contradict each other, harvests everything the current session learned but
  never wrote down, then hands back a short ranked list of the next 3–5 moves.
  All write-backs are gated behind explicit approval. Not a status report —
  it reconciles and repairs.
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
- **Not a silent mutator.** Nothing is written back without the explicit approval gate (Phase 5).
- **Not a completeness ritual.** An unreachable surface is announced loudly, never papered over with a clean-looking report.

## Triggers

Invoked manually — it's a felt state, respect the instinct. But **recommend it**
(don't run it) when you observe:

- More than ~5 items at top priority simultaneously
- A recurring cadence artifact more than one period stale
- A session that surfaced >3 new figures or commitments
- A conversation compacted more than once
- A deliverable pushed while an upstream decision ticket is open
- Operator language: "in the weeds", "messy", "lost track", "are we clean", "baselined"

Accepts `--quick` for a metadata-only sweep (no transcript/page-body pulls).

## Bound surfaces: every agent has three

Currents, Linear, and Agent Mail are **bound surfaces** — every agent that runs
housekeeping has all three, and they are swept every run, no exceptions:

- **Linear** — there is always exactly **one bound project** the agent works in.
  All ticket findings, re-ranks, and next steps anchor to that project.
- **Currents** — the agent generally knows the areas it works in. If it does
  not, it must **traverse Currents and map its blast radius** — the pages,
  sections, and suggestion queues its work touches — before sweeping. Save the
  discovered radius to config so the next run starts oriented.
- **Agent Mail** — the agent's own inbox: unread, unanswered outbound, and
  anything read-but-never-replied.

## Config: the surface list

Per-project, stored outside the repo at `~/.claude/housekeeping/<project-key>.yml`
(key derived the same way as preflight's). The value of the skill is knowing
*which* surfaces matter for *this* project — first run, interview the operator:

```yaml
project: <name>
bound:               # the three per-agent surfaces; always swept
  linear: <the one bound project>
  currents: [<areas/pages this agent works in>]   # discovered by traversal if unknown
  agent_mail: <this agent's inbox>
surfaces:            # everything else the project lives on; sweep ALL every run
  - git: <repo path>          # uses preflight-style read-only checks
  - artifacts: list
  # e.g. attio (incl. call recordings), granola, drive, designsync,
  # visible, carta — whatever this project actually lives on
continuity:          # baseline inputs (Phase 1) and updated at end of run (Phase 6)
  - .latest-status.md
  - journal/ and any handoff docs
canon: <where the one true set of figures/decisions lives>
```

Also store each run's report at `~/.claude/housekeeping/<project-key>-last-run.md`
and **diff against it**: findings unresolved since the previous run are flagged as
repeat findings — a repeat signals a systemic problem, not a tidiness problem.

## The phases — strict sequence, each gates the next

Do not parallelise into a soup. The *feeling* of the command should be deliberate.

### Phase 0 — STOP
Announce the pass. Name any in-flight delivery work and confirm it is parked.
**No tool calls in this phase.** It is a mode change and should read like one.

### Phase 1 — INVENTORY (read-only, exhaustive)

**Baseline first.** Before the wide sweep, orient on the bound surfaces: the
Linear bound project (all non-closed tickets, milestones, cycle, recent
comments), the agent's Currents blast radius (traverse and map it now if
unknown, including pending suggestion counts — unapproved state is invisible
state), the agent's own Agent Mail inbox, and any recent knowledge or handoff
files (`.latest-status.md`, latest `journal/` entry, handoff/context docs).
This is how the agent establishes *where it is* before judging where anything
else is.

Then sweep every configured surface. Per surface capture: id, title, state, priority,
owner, dates, last-updated. Include invisible state (e.g. pending unapproved
suggestions on a page). Prefer metadata sweeps; pull full bodies only for items
Phase 2 flags. Delegate bulk reading to subagents, but **require verbatim quotes
with attribution in return** — a subagent's paraphrase is not evidence.

**Report coverage explicitly.** "Swept 9 of 10 surfaces; X unreachable" is a
valid and required output. An unreachable surface is a *finding*, never a
silent omission.

### Phase 2 — RECONCILE (the core value)
Run the thirteen detectors across the inventory:

1. **priority-inflation** — count open items at top priority; above ~5, force a re-rank rather than reporting.
2. **dead-figure** — extract numeric claims from records; diff against canon; flag figures that disagree with or don't exist in canon.
3. **numeric-drift** — build a figure ledger keyed by metric name; any metric with >1 distinct value across surfaces is a conflict, ranked by whether it was stated externally.
4. **superseded** — records whose stated premise is contradicted by a newer ruling or ticket; propose close/cancel/merge with the superseding reference.
5. **advisor-conflict** — contested claims from different people; build a decision ledger row (`claim | who | when | verbatim | evidence class | status`). Make the conflict visible and force a decision record; never resolve it.
6. **uncaptured-session** — handled in Phase 3.
7. **orphaned-cadence** — any recurring artifact whose latest instance is older than its period.
8. **stalled-thread** — outbound requests to agents/people older than N hours with no reply, joined against what they block.
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
Phase 5 gate. This phase is why housekeeping is worth running even when the
board *is* clean.

### Phase 4 — PRIORITIZE

**The prioritization round (Q&A gate).** If the findings say a re-rank is
needed — priority inflation, conflicting priorities, a stale board, or the
skill simply can't tell what the ball is — do **not** re-rank unilaterally.
Enter a structured Q&A with the operator to rebaseline. Ask in order, one at a
time, each grounded in evidence from the sweep:

1. **The ball** — "Is <X> still the one thing this project is trying to do?" (state your best inference from the sweep; let the operator correct it)
2. **Dead or alive** — per suspect ticket: "Evidence says <id> is done/superseded — close it?"
3. **Real deadlines** — per overdue item: "Is this date externally imposed, or ours?"
4. **The cut** — "Of the N items at top priority, which ≤3 actually matter this week?"
5. **Blockers** — "Anything blocking that I can't see in these surfaces?"

Skip questions the evidence already answers unambiguously; never exceed ~6.
The answers are operator rulings — record them with `operator-ruling`
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
figure corrections, new tickets, decision records — as a reviewable list, and
**wait**. Default is no writes. Offer "apply all" and selective approval, but
destructive or externally-visible actions always itemise individually. After
applying, verify and report what actually landed, including partial failures.
No mutation class is safe to auto-apply; start fully gated.

### Phase 6 — THE WAY OUT
The payload everything above earns: **the next 3–5 steps, in order, the first
one unambiguous.** Short. No hedging. Then update the continuity surfaces from
config (`.latest-status.md`, journal, any always-current page) so tomorrow
starts here — and save this run's report for next run's diff.

## Output format

One report, fixed shape, comparable across runs:

```
HOUSEKEEPING — <project> — <timestamp>

COVERAGE      swept N of M surfaces; <any misses, named>
VERDICT       clean | drifting | in the weeds
              <one sentence of why>

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

## Design rulings

- **Authority:** when two advisors conflict, the skill does **not** rank them — both presented verbatim with credentials and recency; recency is explicitly *not* authority. Operator rules.
- **Scope:** per-project, surfaces configurable.
- **Preflight:** the git surface reuses preflight's read-only checks (branch, tree, sync, PRs, stale branches); run `/preflight` separately for the actual sync.
- **Cadence:** purely invoked, but self-recommends on the trigger signals above.

## Acceptance test

Run it twice in a row: the second report should be near-empty. And the real
test — the operator reads NEXT 3–5, knows exactly what to do, and stops
feeling behind.
