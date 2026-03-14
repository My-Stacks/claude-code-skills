## Version Check
To check for updates: `curl -s https://raw.githubusercontent.com/My-Stacks/claude-code-skills/refs/heads/main/versions.yaml`
Compare against this file's version in frontmatter.

---
name: handoff
version: 3.0
description: "Session continuity via .latest-status.md. Auto-updates during plan execution. Manual handoff, resume, and transfer commands."
---

# Hand-Off

Single-file session continuity. `.latest-status.md` at project root, committed to git. Auto-updates on plan start/completion. Replaces dated handoff archives.

## Commands

| Command | Action |
|---------|--------|
| `/handoff` | Write/update `.latest-status.md` (full manual update) |
| `/handoff resume` | Read `.latest-status.md`, verify git state, begin work |
| `/handoff transfer` | Full knowledge transfer to `docs/handoffs/`, commits to git |

---

## Core Rules

1. **Delta, not snapshot.** Capture what changed. Stable context → CLAUDE.md.
2. **Resume block first.** Goal, state, next action.
3. **Show, don't describe.** File paths, line numbers, exact errors.
4. **Traps are mandatory.** Failed approaches with signal, cause, retry condition.
5. **Real errors.** Exact messages, not summaries.
6. **Next steps need success criteria.**

---

## File: `.latest-status.md`

Single file at project root. Committed to git. Target: 100-300 words.

### Template

```yaml
---
date: YYYY-MM-DD HH:MM
branch: <current git branch>
status: in_progress | paused | blocked | complete
---
```

```markdown
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

**Sections:** Resume + Next always present. Traps only if failed approaches exist. Linear only if `.linear/` exists.

---

## `/handoff` — Manual Update

Write or update `.latest-status.md` with full session context.

### Procedure

1. Review session: decisions, files changed, approaches tried, errors, open questions.
2. Write using the template above. Follow core rules.
3. Save to `.latest-status.md` at project root (overwrite).
4. Commit to git.
5. Confirm: one-line summary, recommended first action.

---

## `/handoff resume` — Pick Up Where We Left Off

### Procedure

1. Read `.latest-status.md`. If missing, fall back to `docs/handoffs/LATEST.md`.
   - If found at old location, read it and suggest running `/handoff` to create new-format file.
2. Parse fully.
3. Confirm before working:
   > "Picking up from [date]. Goal: [goal]. State: [state]. Starting with: [next action]. [N] traps noted."
4. Run `git status -sb && git log --oneline -3`. If state has drifted (different branch, new commits), flag before proceeding.
5. Begin work on highest-priority next step.
6. Do not retry trapped approaches unless the human asks or retry condition is met.

---

## `/handoff transfer` — Full Knowledge Transfer

For moving to a different model, tool, or zero-context reader. **Target: 2,000-5,000 words.**

### Procedure

1. Read all context: CLAUDE.md, README, package.json, architecture docs, `.latest-status.md`, git log.
2. Review codebase structure.
3. Write using transfer template below.
4. Save to `docs/handoffs/YYYYMMDD-HHMM-transfer.md` and copy to `docs/handoffs/LATEST.md`.
5. Commit to git.

### Transfer Template

```markdown
# Project Transfer: [Project Name]
**Date:** YYYY-MM-DD | **Purpose:** [reason]

## What This Project Is — [2-3 sentences]
## Links and Access — [table, only rows that exist]
## Tech Stack — [runtime, framework, database, key libraries]
## Repository Structure — [tree, 2-3 levels, annotated]
## How to Run — [setup, dev, test, build, deploy]
## Architecture — [key components and connections]
## Current State — [working / broken / not built / tech debt]
## Active Context — [reference .latest-status.md, failed approaches, next steps]
## Conventions — [git, code style, testing]
## Gotchas — [non-obvious things about this codebase]
```

---

## Auto-Update Behavior

`.latest-status.md` auto-updates during plan mode execution, not just on manual `/handoff`.

**On plan start** (entering execution after plan approval):
- Light update: date, branch, status → `in_progress`, goal from plan, brief description of what's about to happen.

**On plan completion:**
- Full update: what was done, current state, next steps, any traps encountered, Linear tickets if applicable.

This is behavioral — follow these instructions as part of your workflow when executing plans.

---

## Linear Integration

Auto-detect on every update. Read-only.

1. Check for `.linear/cache.yaml` → read `active_project` for project link.
2. Check `.linear/session.yaml` → read recent ticket activity (keys + statuses).
3. Write `## Linear` section with project link + ticket list.
4. No section if `.linear/` directory doesn't exist.

---

## Persistent Context

Handoffs are deltas. Stable context lives elsewhere:

| What | Where |
|------|-------|
| Project overview, conventions | `CLAUDE.md` or `README.md` |
| Session state | `.latest-status.md` |
| Full transfers | `docs/handoffs/` |

If you're repeating content across updates, move it to a persistent file.
