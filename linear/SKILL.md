---
name: linear
description: |
  Linear project management with integrated session continuity.
  Session tracking, board management, ticket creation, project updates,
  and structured handoffs persisted to Linear.
trigger: /linear
version: "0.4.0"
---

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

## Commands

| Command | Purpose | Writes to Linear |
|---------|---------|:---:|
| `/linear` | Setup if first run. Otherwise show command menu. | No |
| `/linear help` | Show command menu (same as bare `/linear` after setup) | No |
| `/linear board` | Current sprint state, what's next | No |
| `/linear search <query>` | Find existing issues before creating duplicates | No |
| `/linear track` | Log work this session (buffered locally) | No |
| `/linear push` | Batch-push buffered changes to Linear | Yes |
| `/linear handoff` | End-of-session: push + write session summary | Yes |
| `/linear resume` | Start-of-session: pull context, initialize buffer | No |
| `/linear update` | Post a project status update | Yes |
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

### `/linear handoff`

End-of-session. Push remaining changes, write lean session summary to Linear.

**Procedure:**
1. If buffer has pending ticket changes, run push flow first.
2. Write full session details to `.linear/last-handoff.md` (see Full Handoff format below).
3. Draft the **lean update** for Linear (see Lean Update format below).
4. Show preview. Wait for approval.
5. Post as a **project update** on `active_project` via `save_status_update`.
6. Clear entire session buffer.
7. Confirm with link to the update in Linear.

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
- **Linear gets the lean version.** 150-300 words. No exceptions.
- **Full details live locally.** `.linear/last-handoff.md` has everything.
- **Failed approaches are mandatory.** Highest value per token.
- **Cut aggressively.** If removing a line wouldn't cause the next session to make a mistake, remove it.

### `/linear resume`

Start-of-session. Pull context from Linear, orient, begin. Loads lean, expands on demand.

**Procedure:**
1. Check for existing `.linear/session.yaml`. If it has pending changes from a
   crashed/interrupted session, flag it: "Found unpushed buffer from [date] with
   [n] pending changes. Push these first, or discard?"
2. Check for `.linear/last-handoff.md`. If present, read Resume block from local file (no API call needed).
3. If no local handoff, fetch most recent project update for `active_project` via `get_status_updates`. Parse the Resume block only (Goal, State, Next, Do not repeat).
4. Fetch current board state (same as `/linear board`).
5. **Store full update** in `.linear/last-handoff.md` for on-demand access.
6. Synthesize and confirm:
   > "Picking up from [date]. Goal: [goal].
   > Starting with: [next action].
   > Board: [n] in progress, [n] todo, [n] blocked."
7. If board contradicts handoff (issue done that handoff says in-progress,
   new issues appeared), flag drift before proceeding.
8. Initialize new session buffer with goal carried forward.
9. **Do not retry failed approaches** unless explicitly asked or
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
`.linear/last-handoff.md` for last session context.

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

Omit sections with no content. Preview, approve, post via `save_status_update` on `active_project`.

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

**Priority values:** 0=None, 1=Urgent, 2=High, 3=Normal, 4=Low.

**Required fields on state transitions:** Some teams require PR links, time estimates, or
custom fields before allowing status changes. If push gets a validation error on a state
transition, surface the required fields and ask the user to provide them.

**Rate limits:** Linear allows 5,000 requests/hour. Batching keeps us well under, but
if push has 20+ items, chunk into groups of 10 with brief pauses between.

**Project update size:** Keep under 10,000 characters. The lean format (150-300 words)
stays well under this. If somehow exceeded, trim notes first.

**MCP connection required.** If `Linear:*` tools aren't available, tell user to check
their MCP/connector configuration.

**Content vs Description (projects):** Linear projects have two text fields.
`description` (255 chars, shows in list views) and `content` (unlimited, shows in detail panel).
Always set BOTH when creating projects. Summary in description, details in content.

---

## Reference

For content extraction rules, metadata inference tables, description templates,
and estimate guidelines, read REFERENCE.md. Load it during `/linear create`
or when converting plans to tickets. Not needed for board, track, push, or resume.
