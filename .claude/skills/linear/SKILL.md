---
name: linear
description: |
  Linear project management with integrated session continuity.
  Session tracking, board management, ticket creation, project updates,
  and structured handoffs persisted to Linear.
  Syncs project description, dependencies, and metadata from repo state.
  Auto-maintains .latest-status.md for cross-session resume.
trigger: /linear
version: "0.7.0"
---

## Version Check
To check for updates: `curl -s https://raw.githubusercontent.com/My-Stacks/claude-code-skills/refs/heads/main/versions.yaml`
Compare against this file's version in frontmatter.

# Linear Skill

Manage Linear issues, track session work, and maintain continuity across sessions.
Buffer changes locally, push in one batch. Linear is the single source of truth
for project state and session history.

## Non-Negotiables

These rules override everything else. Check before every write.

1. **Preview before every Linear write.** Show it, wait for explicit approval. After any change request, re-show full preview. Never write immediately after changes.
2. **Cycle assignment requires a UUID.** Query `list_cycles(type="current")` to resolve. Never pass "current" or "next" as strings.
3. **Drift check before push.** Fetch `updatedAt` for every referenced issue. If mismatch with buffer expectations, surface the conflict before writing.
4. **Creates before dependents.** New issues must be created before any comments, status changes, or relations that reference them.
5. **Labels are arrays.** `["Bug"]` not `"Bug"`. Always.
6. **No empty sections.** Never include template sections with placeholder text. Omit entirely.
7. **Buffer is append-only until push.** `/linear track` never calls the Linear API.
8. **Destination is resolved from the work, not fixed to the binding.** `/linear handoff` and `/linear update` post to the project the session's tickets belong to. The bound `active_project` is the *fallback* when the session touched nothing off-project — never the automatic target when it did. See Destination Resolution.

## Verbosity Control

Every output competes for context window space. These targets are hard limits, not suggestions.

**Handoff updates (posted to Linear):** 150-300 words.
- Resume block: 4 lines (Goal, State, Next, Do not repeat). This is the payload.
- Key Changes: issue keys + 2-3 word outcomes. Max 5 items.
- Traps: top 1-2 failed approaches, 1 line each (tried + cause).
- Full session details go to `.linear/last-handoff.md`, not Linear.

**Standalone project updates:** 100-200 words.
- Health indicator + 3-5 bullets max.
- Issue keys, not descriptions. Outcomes, not process.

**Ticket descriptions:** Minimal viable context.
- Default: title + problem (2-3 sentences) + solution (2-3 sentences).
- Implementation/technical notes: only if critical AND explicit in source.
- Acceptance criteria: simple checklist (3-5 items). Not Given/When/Then unless source uses it.
- Reference docs instead of copying content. "See [link]" + 2-sentence summary.

**Resume context:** Load lean, expand on demand.
- Parse Resume block only (4 lines, ~50 words) + board state.
- Full handoff available in `.linear/last-handoff.md` if agent needs more.

**The test:** For every line in an output, ask: "Would removing this cause the next session to make a mistake?" If no, cut it.

## Status File

When the linear skill is active, it maintains `.latest-status.md` at project root. This enables cross-session resume.

**On plan start** (entering execution after plan approval):
- Light update: date, branch, status → `in_progress`, goal from plan.

**On plan completion:**
- Full update with Linear section populated from session buffer.

**Template** (100-300 words):

```markdown
---
date: YYYY-MM-DD HH:MM
branch: <current git branch>
status: in_progress | paused | blocked | complete
---

# Status: [Brief Title]

## Resume
**Goal:** [one line]
**State:** [1-2 sentences]
**Next:** [action + file + done-when]

## Next
1. [Action] — `path` — done when: [condition]

## Traps
- **[What]:** [signal] — [cause]. Retry if: [condition]

## Linear
- [Project](url) — ENG-142 (done), ENG-156 (in progress)
```

**Sections:** Resume + Next always present. Omit Traps if none. Populate Linear from session buffer and cache.

## Commands

| Command | Purpose | Writes to Linear |
|---------|---------|:---:|
| `/linear` | Setup if first run. Otherwise show command menu. | No |
| `/linear help` | Show command menu (same as bare `/linear` after setup) | No |
| `/linear board` | Current sprint state, what's next | No |
| `/linear search <query>` | Find existing issues before creating duplicates | No |
| `/linear track` | Log work this session (buffered locally) | No |
| `/linear push` | Batch-push buffered changes to Linear | Yes |
| `/linear handoff` | End-of-session: push + write session summary. `--to <project>` overrides destination. | Yes |
| `/linear resume` | Start-of-session: pull context, initialize buffer | No |
| `/linear update` | Post a project status update. `--to <project>` overrides destination. | Yes |
| `/linear sync-project` | Sync project description, dependencies, metadata from repo state | Yes |
| `/linear create` | Create a single ticket now (not buffered) | Yes |
| `/linear buffer` | View/edit/remove buffered items | No |
| `/linear context` | Show current loaded state (no API calls) | No |
| `/linear refresh` | Force-refresh cache | No |

### `/linear` and `/linear help`

After setup, bare `/linear` or `/linear help` shows the command menu:

> **Linear: [Project Name]** ([n] buffered changes)
>
> `/linear board` — see current issues
> `/linear track` — log work this session
> `/linear create` — create a ticket
> `/linear resume` — pick up from last session
> `/linear push` — push buffered changes to Linear
> `/linear handoff` — end session + write summary
> `/linear update` — post a project status update
> `/linear sync-project` — write project description + dependencies to Linear
> `/linear search <query>` — find existing issues
> `/linear buffer` — view/edit buffered items
> `/linear context` — show loaded state

Include the buffered changes count if session buffer exists and has pending items.
No API calls. Just read local state and show the menu.

---

## First Run: Setup + Project Binding

On first invocation, detect whether `.linear/cache.yaml` exists.

If not, run full setup:

**Step 1: Connect and cache workspace.**
1. Fetch teams. If multiple, ask user to pick default.
2. Fetch for that team: users, projects, labels, cycles, workflow states.
3. Write to `.linear/cache.yaml`.

**Step 2: Bind to a project.**
1. Compare current repo/directory name against cached project names.
2. If clear match, propose it: "This looks like it maps to [Project Name] in Linear. Use that?"
3. If no match, show project list and ask user to pick.
4. If no project exists, offer to create one: "No matching project in Linear. Create one called [repo-name]?"
5. Store binding in cache as `active_project`.

**Step 3: Confirm.**
> "Linear connected. Team: Engineering. Project: Auth Service.
> 12 users, 8 labels, 5 workflow states cached.
> Current cycle: Sprint 26 (ends Feb 28)."

**Project binding persists.** Every subsequent command reads `active_project`
from cache. No re-asking. Override with `/linear project <n>` if needed.

**Re-cache on error:** If any lookup fails with "not found", re-fetch that
entity type silently. Only surface if entity genuinely doesn't exist.

## Cache

Location: `.linear/cache.yaml`

```yaml
updated: 2026-02-21T10:00:00Z
default_team:
  id: "abc-123"
  name: "Engineering"
  key: "ENG"
active_project:
  id: "proj-789"
  name: "Auth Service"
  matched_by: "user_selected"
  synced: 2026-02-21        # last /linear sync-project write; absent until first sync
teams: [...]
users: [...]           # id, name, email
projects: [...]        # id, name
labels: [...]          # id, name
cycles: [...]          # id, number, startsAt, endsAt
workflow_states: [...]  # id, name, type (triage|backlog|unstarted|started|completed|canceled)
```

**Resolution rules:**
- Always resolve names to IDs from cache before API calls.
- Map status strings ("In Progress", "Done") to workflow state IDs via cache.
- Auto-refresh cycles when cached current cycle's `endsAt` is past.
- Auto-refresh workflow states during `/linear refresh`.

## Session Buffer

Location: `.linear/session.yaml`

```yaml
started: 2026-02-21T10:00:00Z
goal: "Refactor auth module and fix token refresh edge case"
changes:
  - id: "c1a2b3"
    type: status_change
    issue: "ENG-142"
    expected_updated_at: "2026-02-21T09:00:00Z"
    to_state: "Done"
    note: "Completed refactor"
    status: pending

  - id: "c4d5e6"
    type: new_issue
    title: "Fix edge case in token refresh"
    labels: ["Bug"]
    priority: 3
    status: pending

  - id: "c7f8g9"
    type: comment
    issue: "ENG-140"
    depends_on: null
    body: "Discovered during work on ENG-142..."
    status: pending

notes:
  - "JWT_SECRET was missing from .env.example, added it"

failed_approaches:
  - tried: "jsonwebtoken verify() with clock tolerance"
    signal: "TokenExpiredError persists with 30s tolerance"
    cause: "Token expired by 3+ hours in test fixture"
    retry_only_if: "Test fixtures updated with fresh tokens"
```

**Buffer schema rules:**
- Every change gets a unique `id` (short random string).
- Every change has `status: pending | applied | failed`.
- Changes referencing existing issues store `expected_updated_at` (captured at track time or from last board fetch).
- Changes that depend on a new issue being created first use `depends_on: <change_id>` of the create.
- On successful push: mark `applied`, store returned Linear IDs.
- On failed push: mark `failed`, keep in buffer for retry.
- `goal`, `notes`, `failed_approaches` persist until `/linear handoff` consumes them.

---

## Commands: Detail

### `/linear board`

Show current work state. One read, structured display.

1. Resolve current cycle from cache (fetch if stale).
2. `list_issues`: team + current cycle + assignee=me.
3. Group by workflow state type: `started` first, then `unstarted`, then `backlog`.
4. Display compact table with issue key, title, estimate, assignee.
5. Store `updatedAt` for each displayed issue (used by track for drift detection).

Then: "Want to pull something into progress, or track work on an existing issue?"

If team doesn't use cycles: fall back to `list_issues` filtered by project + assignee,
sorted by updatedAt descending, limited to 20.

### `/linear search <query>`

Find existing issues before creating duplicates.

1. `list_issues(query=<search term>, team=default_team)`.
2. Show results: key, title, status, assignee.
3. "Found [n] matches. Want to track work on one of these, or create a new issue?"

### `/linear track`

Log work to the local buffer. Never touches the Linear API.

**Verb-to-action mapping:**

| User says | Buffer action | Key signal words |
|-----------|--------------|-----------------|
| "finished ENG-142" / "done with ENG-142" | `status_change` to Done (completed state) | finished, done, completed, shipped, merged |
| "started ENG-150" / "working on ENG-150" | `status_change` to In Progress (started state) | started, working on, picked up, beginning |
| "found a bug in X, need a ticket" | `new_issue` | need a ticket, new issue, found a bug, should track |
| "ENG-145 is a 3-pointer" / "update estimate" | `update` field change | update, change, actually, turns out |
| "note on ENG-140: retry logic..." | `comment` on issue | note on, comment on, FYI on |
| "tried X, failed because Y" | `failed_approaches` entry | tried, attempted, failed, didn't work, broke |
| "note: JWT_SECRET was missing" | `notes` entry | note:, remember:, heads up:, gotcha: |

**When ambiguous:** Ask. "Should I log that as a comment on ENG-140, or as a general session note?"

**After each track:** Confirm what was buffered and show running count.
> "Buffered: ENG-142 -> Done. (5 changes, 1 trap, 2 notes pending)"

### `/linear buffer`

View and manage the session buffer.

- `/linear buffer` (no args): show all pending items, numbered.
- `/linear buffer rm <n>`: remove item by number.
- `/linear buffer edit <n>`: modify an item (show current, ask what to change).
- `/linear buffer clear`: clear entire buffer (confirm first).

### `/linear push`

Batch-push all buffered ticket changes to Linear.

**Procedure:**
1. Load buffer. Filter to `status: pending` items only.
2. **Drift check:** For every change referencing an existing issue, fetch current
   `updatedAt` from Linear. Compare against `expected_updated_at` in buffer.
   - If match: proceed.
   - If mismatch: show diff. "ENG-142 was updated since you tracked it. Current state: [state], assignee: [name]. Your change: move to Done. Apply anyway, skip, or update buffer?"
3. **Show push summary** (preview before write):
   ```
   ## Push Summary (4 changes)

   1. ENG-142: In Progress -> Done
   2. NEW: "Fix token refresh edge case" [Bug, P3]
   3. ENG-140: Add comment (retry logic)
   4. ENG-145: Update estimate to 3pt

   ⚠ ENG-142 was modified externally (see above)

   Push all? Remove/edit items first? (/linear buffer rm 1)
   ```
4. Wait for approval.
5. **Execute in dependency order:**
   - First: all `new_issue` creates (capture returned IDs).
   - Second: resolve `depends_on` references (replace change_id with real issue ID).
   - Third: `status_change` operations (resolve state names to workflow state IDs via cache).
   - Fourth: `update` operations.
   - Fifth: `comment` operations.
6. Mark each: `applied` (with returned IDs) or `failed` (with error).
7. Report results. Clear applied items. Failed items stay for retry.

**Push does NOT clear `goal`, `notes`, or `failed_approaches`.** Those persist
until `/linear handoff`.

### Destination Resolution (handoff + update)

Both `/linear handoff` and `/linear update` post a project update. **The destination is
resolved from what the session actually touched. `active_project` is the fallback, not the
automatic target.** The binding is not proof the work belonged to it: an agent bound to its
own project (a ledger, a core service) routinely does work that feeds a *different* project
— a client delivery, an internal initiative. The update belongs where the work lives, so
the bound project only wins when it's where the tickets are, or when nothing off-project
was touched.

**Explicit override.** `--to <project>` pins the destination up front and skips
inference and the selector — but **not** the write preview; Non-Negotiable #1 still
applies. Resolve `<project>` to **exactly one** project: an exact **project ID** resolves
directly; any **name** is matched **across teams** via `list_projects` (not just cache —
names are not unique across teams), and if more than one matches, do not guess: list the
matches and ask, or accept an ID / `Team/Project` form.

**Inference procedure (no override):**

1. **Build the referenced-project tally.** From the buffer — for handoff, its **pre-push
   snapshot** (the live buffer is cleared by push); for update, the live buffer (update runs
   no push) — take every distinct issue key across status_changes and comments, plus the
   target project of every `new_issue`. Resolve each to its project — reuse project data
   already fetched this session; `get_issue` for any unknown. The tally is referenced-count
   per project. Keep each lookup's `updatedAt` for the tie-break (these values are
   authoritative — no separate refresh).
2. **Decide from the tally.**
   - The tally contains **any** project other than `active_project` → **off-project signal.**
     Show the selector.
   - The tally is empty, **or** every entry is `active_project` → **no off-project signal.**
     Fall back to `active_project`, no selector. Continue to the command's preview step.
     (A deliberate fallback, not an assumption — nothing in the tally points elsewhere.)
3. **Selector.** Recommend the non-`active_project` project with the highest count in the
   tally. **Ties:** the project whose newest referenced ticket has the latest `updatedAt`
   (from step 1's lookups — no refresh); if still tied, project name A–Z — so the
   recommendation is deterministic. List `active_project` as the alternative, then an
   "Other project…" entry that opens a full picker (`list_projects`, **across teams** —
   client work usually lives on another team). Show a preview panel for each **concrete**
   project option (the "Other project…" picker previews a project only once one is picked):

   ```
   Project: Financial Modeling (North Star)
   Team: Operations (OPE2)
   Referenced this session:
     OPE2-182 assumptions grid (In Progress)
     OPE2-183 projection grid (Backlog)
   → status update posts here
   ```
4. **Resolve the chosen project's id.** The update attaches to the project; its team comes
   along, so cross-team needs no separate team arg.

**The destination is a one-off routing choice. It never changes `active_project`** — that's
`/linear project <n>`'s job. Do not write the chosen project back to cache.

### `/linear handoff`

End-of-session. Push remaining changes, write lean session summary to Linear.

**Procedure:**
1. **Snapshot the session buffer first — before any push.** Capture the full set of changes (status_changes, comments, new_issues), notes, and failed_approaches. Every step below reads this snapshot, not the live buffer, because push (step 3) clears applied items — reading the live buffer afterward would omit the very activity being handed off.
2. **Resolve the destination project** from the snapshot (see Destination Resolution). If off-project, show the selector and get the pick. Hold the destination through the rest of the flow.
3. If the buffer has pending ticket changes, run the push flow. (Push writes ticket changes only — it has no destination logic and never re-resolves the destination.)
4. Write full session details to `.linear/last-handoff.md` from the snapshot (see Full Handoff format below).
5. Update `.latest-status.md` using Status File template (status `paused` or `complete`). Populate `## Linear` from the snapshot.
6. Draft the **lean update** for Linear from the snapshot (see Lean Update format below).
7. Show preview — headed with **Destination: [project] ([team])**. Wait for approval.
8. Post as a **project update** on the resolved destination via `save_status_update`.
9. Clear entire session buffer.
10. Commit `.latest-status.md` and `.linear/last-handoff.md` to git.
11. Confirm with link to the update in Linear.

**Lean Update format (posted to Linear, 150-300 words max):**

```markdown
## Session: [Date] [Brief Title]

### Resume
**Goal:** [What we were building/fixing]
**State:** [Where things stand now]
**Next:** [Single most important next action with file path]
**Do not repeat:** [Biggest trap for next session]

### Key Changes
- ENG-142: Done (auth refactor)
- Created ENG-156: token refresh fix
- ENG-145: estimate -> 3pt

### Traps
- **clock tolerance on verify()**: Token expired by 3hr, tolerance only handles seconds. Retry only if test fixtures refreshed.
```

**Full Handoff format (saved to `.linear/last-handoff.md`):**

```markdown
---
date: 2026-02-21
project: Auth Service
goal: "Refactor auth module and fix token refresh edge case"
---

## Resume
Goal: [What we were building/fixing]
State: [Where things stand now]
Next: [Single most important next action with file path]
Do not repeat: [Biggest trap for next session]

## Changes
- ENG-142: Done (auth module refactor, touched 8 files)
- Created ENG-156: Fix token refresh edge case
- ENG-145: Updated estimate to 3pt
- ENG-140: Added comment about retry logic

## Failed Approaches
- **Tried:** jsonwebtoken verify() with clock tolerance
  **Signal:** TokenExpiredError persists with 30s tolerance
  **Cause:** Token expired by 3+ hours in test fixture
  **Retry only if:** Test fixtures updated with fresh tokens

## Notes
- JWT_SECRET was missing from .env.example, added it
- Auth middleware ordering matters: cors -> auth -> routes

## Next Steps
1. Update test fixtures with fresh tokens (files: tests/auth/*.test.ts)
   Done when: All auth tests pass without clock tolerance hack
2. Add token refresh retry logic to middleware (files: src/middleware/auth.ts)
   Done when: Expired token triggers refresh, not 401
```

**Handoff rules:**
- **Delta, not snapshot.** What changed this session only.
- **Resume block is the payload.** Everything else is reference material.
- **Three destinations:** `.latest-status.md` (universal, 100-300 words), `.linear/last-handoff.md` (full detail), Linear project update (lean, 150-300 words).
- **Failed approaches are mandatory.** Highest value per token.
- **Cut aggressively.** If removing a line wouldn't cause the next session to make a mistake, remove it.

### `/linear resume`

Start-of-session. Pull context from Linear, orient, begin. Loads lean, expands on demand.

**Procedure:**
1. Check for existing `.linear/session.yaml`. If it has pending changes from a
   crashed/interrupted session, flag it: "Found unpushed buffer from [date] with
   [n] pending changes. Push these first, or discard?"
2. Check for `.latest-status.md`. If present, read Resume block (Goal, State, Next) and Traps section. This is the primary resume source.
3. Check for `.linear/last-handoff.md`. If present and more recent, prefer its Resume block. Use for expanded detail (full changes, detailed traps, notes) regardless.
4. If neither local file exists, fetch most recent project update for `active_project` via `get_status_updates`. Parse the Resume block only (Goal, State, Next, Do not repeat).
5. Fetch current board state (same as `/linear board`).
6. **Store full update** in `.linear/last-handoff.md` for on-demand access.
7. Synthesize and confirm:
   > "Picking up from [date]. Goal: [goal].
   > Starting with: [next action].
   > Board: [n] in progress, [n] todo, [n] blocked."
8. If board contradicts handoff (issue done that handoff says in-progress,
   new issues appeared), flag drift before proceeding.
9. Initialize new session buffer with goal carried forward.
10. **Do not retry failed approaches** unless explicitly asked or
   "retry only if" condition is met. If agent needs trap details, read from `.linear/last-handoff.md`.

### `/linear context`

Show current loaded state. No API calls. Reads from local files only.

**Output:**
```
Linear: [Project Name] ([n] buffered changes)
Last handoff: [date] "[brief title]"
Resume: Goal: [goal] | Next: [next action]
Board: [n] in progress, [n] todo, [n] blocked
Traps: [n] failed approaches on file

Need more? /linear board (live) | /linear resume (full reload)
```

**Sources:** `.linear/cache.yaml` for project/team, `.linear/session.yaml` for buffer,
`.latest-status.md` for resume context, `.linear/last-handoff.md` for full session detail.

### `/linear update`

Post a project status update. Standalone or auto-generated from session data.

If session buffer has content, offer:
> "Draft from your session data, or write from scratch?"

**Drafting from buffer:**
- "What shipped" from applied status changes and created issues.
- "What's next" from remaining todo items on the board.
- "Blockers" from blocked issues on the board.
- Session notes fill the narrative.

**Format (100-200 words max):**
```markdown
## What shipped
- [issue key]: [2-3 word outcome]

## What's next
- [issue key]: [2-3 word description]

## Blockers
- [issue key]: [what's blocking]
```

Omit sections with no content. **Resolve the destination project** (see Destination
Resolution) before previewing — same inference and selector as handoff, with `--to <project>`
as the explicit override. Preview headed with **Destination: [project] ([team])**, approve,
post via `save_status_update` on the resolved destination.

### `/linear sync-project`

Bring the bound project's description, dependencies, and metadata in line with what the
repo actually is. Refreshes a drifted project; fills out a new or empty one. Writes
directly via `save_project` — no copy-paste step.

`/linear update` reports what happened this session. `sync-project` corrects what the
project *is*. Different jobs, different cadence.

Don't confuse it with the two similarly-named commands: `/linear refresh` pulls Linear
data *into* the local cache and writes nothing; `/linear project <n>` switches which
project is bound. `sync-project` is the only one of the three that writes to Linear.

**When to run:**

| Trigger | Run? |
|---|---|
| Project newly created, or description empty/stub | Yes |
| Status transition (e.g. scaffolded → in-development → active) | Yes |
| Major capability, runtime, or dependency change | Yes |
| Repo move, ownership change, initiative or team change | Yes |
| User asks | Yes |
| Routine session work, ticket updates, journal entries | No — that's `/linear handoff` |

**Step 1: Resolve the binding.**

Read `active_project` from cache. Three cases, in this order — they are mutually
exclusive, so resolve which one applies before doing anything else:

| Cache state | `get_project` result | Mode | Do |
|---|---|---|---|
| **No `active_project`** | — | — | Run First Run binding (Setup Step 2). It resolves to either an existing project (→ **update**) or a decision to create a new one (→ **create**). It does **not** call `save_project` itself. Continue to Step 2 carrying that mode. |
| **Bound** | resolves | **update** | Normal path — continue to Step 2. |
| **Bound** | not found, **or** cached `default_team` is absent from the project's team list | — | **Stop. Report. Write nothing.** |

Carry **update** or **create** through to Step 5 — it selects which single `save_project`
call is made there, and nothing before Step 5 writes. There is **at most one** write per
run in either mode, so a create can't duplicate or double-fire. Zero writes is also a
valid outcome: if Step 4's diff comes back empty in update mode, report "already in
sync" and stop — never call `save_project` with an `id` and no changed fields.

`synced:` is informational only. Nothing in this step reads it, and a recent value never
skips a run.

The third row is a *broken binding*, not a missing project: the cache names a specific
project ID and Linear disagrees. Creating a new project here would silently orphan the
real one and split its history. Say which of the two it is — stale ID or team mismatch —
and let the user re-bind with `/linear project <n>`.

**The team check is membership, not equality.** A Linear project can belong to several
teams — that is why Step 3 uses append-only `addTeams`. It is a mismatch only when the
cached `default_team` is *absent* from the project's teams; a project carrying
`default_team` plus others is valid, and halting on it would refuse a legitimate sync.

**Step 2: Detect source mode.**

| Detect | Mode | Sources, in order |
|---|---|---|
| `agent.yaml` at repo root | **agent** | `agent.yaml` (codename, status, runtime, repo, mcps, pipeline, linear block) → `CLAUDE.md` (identity, what it does) → `.latest-status.md` → newest `journal/*.md` |
| otherwise | **generic** | `README.md` → `CLAUDE.md` → manifest (`package.json` / `pyproject.toml` / `Cargo.toml` / `go.mod`) → `git remote get-url origin` → `git log -20 --oneline` → `.latest-status.md` |

Agent mode: if the `linear` block in `agent.yaml` holds unresolved `{{placeholder}}`
values, stop. "Linear binding incomplete in agent.yaml. Fix that first, then re-run."

Read only the newest journal entry, not the whole directory. "Newest" = the highest
`YYYY-MM-DD` filename prefix; if the filenames aren't date-prefixed, the most recently
modified file. Don't take the alphabetically-last name as newest — for undated filenames
that silently feeds stale context into the description.

**Sanitize the remote before it reaches a field.** `git remote get-url origin` can carry
embedded credentials. Reduce it to bare `org/repo` *before* composing or previewing — a
Linear project description is visible to the whole workspace, so a token written there is
a leaked secret, and the Step 4 preview would expose it too. Both remote forms:

| Form | Example | Reduce by |
|---|---|---|
| URL | `https://TOKEN@github.com/org/repo.git` | strip `.git`; take the **last two `/`-separated segments** (`org/repo`). Never assemble the result from the host or userinfo — discard everything before those two segments. |
| SCP-style | `git@github.com:org/repo.git` | strip `.git`; take the substring after the **first `:`** (`org/repo`) |

Both rules land on the same two segments, so a token in the userinfo can't survive either
path.

SCP-style is the common case and is *not* a URL — `git@github.com` is user+host and the
`:` is the separator, not a port. Don't apply URL parsing to it. If the result isn't a
clean `org/repo`, omit the repo field rather than emit something you couldn't reduce.

**Step 3: Compose fields.**

Set only what you can source from the repo. Omit rather than guess — an omitted field
is left untouched, an invented one is drift you just wrote.

| Field | Source | Notes |
|---|---|---|
| `summary` | one-line what-it-is | **≤255 chars** — trim here, before the preview; don't let the API reject it |
| `description` | body template below | Markdown, literal newlines |
| `lead` | `agent.yaml` owner or CODEOWNERS | explicit owner signals only — never infer from commit history |
| `addTeams` | cached `default_team` | append-only; never `setTeams` here |
| `addInitiatives` | parent program, if explicit | omit if unknown |
| `state`, `priority`, `startDate`, `targetDate` | explicit source only | omit rather than infer |
| `labels` | — | skip; it replaces the full set |

**Description body.** Include only sections with real content — omit the rest entirely
(Non-Negotiable #6). Never emit a heading with placeholder text under it.

```markdown
{One paragraph: what this is, what surface it runs on, how it's used.
Operational, not aspirational.}

## Where it lives
- **Repo:** `{org}/{name}`
- **Runtime:** {one sentence — service, CLI, workflow-only, static site}
- **Output:** {path or surface, if any}

## Dependencies
- **Upstream:** {what feeds this}
- **Downstream:** {what consumes it}
- **Services/MCPs:** {name — one-line role}
- **Canon:** {source of truth it reads, with link}

## Status
{current state + one-sentence interpretation, dated}
```

Dependencies sourcing — agent mode: `agent.yaml` `mcps` (required + optional) and
`pipeline` (upstream/downstream). Generic mode: manifest dependencies (direct only,
not transitive), CI config, and any services named in README.

**Step 4: Diff, preview, approve.**

Show old → new for changed fields only. List unchanged fields by name so it's clear
what's being left alone.

```
## Project sync: Auth Service

summary      "Auth service"  →  "Token issuance and session validation for..."
description  2 sections changed: Dependencies (+3 services), Status (in-dev → active)
lead            unset  →  Kyle Hudson
addInitiatives  + Platform

Unchanged: teams, priority, dates, labels

Apply?
```

Wait for explicit approval. After any requested change, re-show the full preview
before writing (Non-Negotiable #1).

**This gate applies to create mode too** — a create is a write. Preview it the same way,
with every field reading `unset → <value>`, and head the block `## Create project: <name>`
so it's unmistakable that approving makes a new project rather than editing one.

**Step 5: Write.** One `save_project` call, per the mode carried from Step 1:

- **update** — pass `id: active_project.id` and only the changed fields. If there are
  none, make no call at all (see Step 1).
- **create** — pass no `id`. Pass `name`, `addTeams`, and **every field Step 3 sourced
  and Step 4 got approved** — `summary`, `description`, and any of `lead`,
  `addInitiatives`, `state`, `priority`, `startDate`, `targetDate` that were previewed.
  Dropping an approved field here would silently discard something the user signed off on.
  If Step 4 ended with nothing approved, abort — "Nothing approved; project not created."
  Never create a bare project from `name` + `addTeams` alone.

Report the project URL.

**Create mode must then seed the cache before anything else.** `active_project` does not
exist yet — its absence is what selected create mode — so there is no entry to update.
Write a complete one into `.linear/cache.yaml`:

```yaml
active_project:
  id: "<id returned by save_project>"
  name: "<project name>"
  matched_by: "created"
  synced: <today>
```

Skip this and the next run sees no `active_project`, takes the create path again, and
makes a **duplicate project** — the exact failure the binding rules exist to prevent.

**Step 6: Update cache — update mode only.** Stamp `synced:` on the existing
`active_project` entry as an unquoted ISO 8601 date (`YYYY-MM-DD`) — not a quoted string,
not a full timestamp. **Create mode skips this step entirely:** Step 5 already wrote the
complete entry, `synced:` included. There is exactly one cache write per run.

**Follow-ups this command does not do:** it never creates or closes tickets, never
moves the project between teams, and never writes milestones. If the repo has a roadmap
and the project has no milestones, offer `save_milestone` as a separate opt-in pass.

**Failure modes:**

| Symptom | Cause | Fix |
|---|---|---|
| "Linear binding incomplete" | `{{placeholder}}` in `agent.yaml` linear block | Fill the binding, then re-run |
| "Project not found" | Stale `active_project.id` | Re-bind via `/linear project <n>`, or create a new project |
| Team mismatch | Project moved teams, or binding points elsewhere | Confirm which is right before writing |
| Summary rejected | Over 255 chars | Trim to the one-line form; detail belongs in `description` |
| Description renders escaped `\n` | Escape sequences passed instead of literal newlines | Re-send with real newlines |

### `/linear create`

Create a single ticket immediately (not buffered).

1. **Search first:** Quick `list_issues(query=<title keywords>)` to check for duplicates.
   If matches found: "Found similar issues: [list]. Still want to create, or track on one of these?"
2. Gather: title (required), description, labels, project, cycle, assignee, priority, estimate.
3. If given a plan/report, extract content per REFERENCE.md.
4. Show proposal with metadata reasoning. Wait for approval.
5. Resolve all names to IDs: team, assignee, labels, project, cycle (UUID), state.
6. Create issue, return URL.

See REFERENCE.md for content extraction rules, metadata inference, and templates.

### `/linear refresh`

Force-refresh all cached data: teams, users, projects, labels, cycles, workflow states.
Preserves `active_project` binding.

### `/linear project <n>`

Switch active project binding. Use when working across multiple projects
from the same repo.

---

## Sharp Edges

**Workflow state resolution:** Teams use custom states ("In Review", "QA", "Deployed"),
not just "Todo"/"Done". Always resolve status strings to workflow state IDs via cache.
If a state name isn't in cache, refresh before failing.

**Team/project names are case-sensitive.** Must match exactly. On error, re-fetch and match.

**Priority values:** 0=None, 1=Urgent, 2=High, 3=Medium, 4=Low. (Linear's own label for
3 is "Medium"; don't surface it as "Normal".)

**Required fields on state transitions:** Some teams require PR links, time estimates, or
custom fields before allowing status changes. If push gets a validation error on a state
transition, surface the required fields and ask the user to provide them.

**Rate limits:** Linear allows 5,000 requests/hour. Batching keeps us well under, but
if push has 20+ items, chunk into groups of 10 with brief pauses between.

**Project update size:** Keep under 10,000 characters. The lean format (150-300 words)
stays well under this. If somehow exceeded, trim notes first.

**MCP connection required.** If `Linear:*` tools aren't available, tell user to check
their MCP/connector configuration.

**Summary vs Description (projects):** `save_project` takes `summary` (max 255 chars,
shows in list views) and `description` (unlimited Markdown, shows in the detail panel).
There is no `content` parameter. Set BOTH when creating a project. Pass `description`
with literal newlines, not escaped `\n`.

**Destructive project params:** `setTeams`, `setInitiatives`, and `labels` REPLACE the
full set — anything omitted is removed. Use `addTeams`/`addInitiatives` to append.
Never pass the `set*` forms against an existing project without explicit approval.

**Milestones and project relations:** `save_project` writes neither. Milestones need
`save_milestone` per milestone. Project-to-project dependency relations have no MCP
write path — record them in the description body instead.

---

## Reference

For content extraction rules, metadata inference tables, description templates,
and estimate guidelines, read REFERENCE.md. Load it during `/linear create`
or when converting plans to tickets. Not needed for board, track, push, or resume.
