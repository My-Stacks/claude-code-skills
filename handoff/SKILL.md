---
name: handoff
version: 2.1
description: "Session continuity for LLM-assisted development. Create, resume, report on, and transfer project context across sessions, models, and tools."
---

# Hand-Off

Structured session continuity for LLM-assisted development. Handoffs capture what changed, what failed, what's next, and what to never retry, so the next session starts working instead of re-learning.

## Commands

| Command | What it does | When to use |
|---------|-------------|-------------|
| `/handoff` | Full session handoff (default) | End of day, long break, switching projects, before major decisions |
| `/handoff quick` | Lightweight checkpoint | Mid-session save, short break, context getting long, before risky changes |
| `/handoff resume` | Pick up from last handoff | Start of new session, "continue where we left off" |
| `/handoff status` | Current project status report | Standup updates, check-ins, "where are we on this?" |
| `/handoff transfer` | Full project knowledge transfer | Moving to a new model/tool, onboarding someone, project migration |

---

## Core Rules

1. **Delta, not snapshot.** Capture what changed this session. Stable context belongs in CLAUDE.md or project docs, not handoffs.

2. **Resume block first.** Goal, state, next action. Not accomplishments.

3. **Show, don't describe.** File paths, line numbers, exact errors. Not "fixed the auth bug" but "Fixed JWT validation in `src/auth/refresh.ts:42`: was using `OAUTH_SECRET`, changed to `JWT_SECRET`."

4. **Failed approaches are mandatory (full handoff).** Highest-value section per token. Use the structured schema (tried, signal, cause, retry only if).

5. **Real errors, not summaries.** Not "API returns errors" but "POST /api/auth/refresh returns 500: `TokenExpiredError: jwt expired` at refresh.ts:42."

6. **Next steps need success criteria.** Not "fix the endpoint" but "Fix refresh endpoint. Files: `src/auth/refresh.ts` ~line 42. Done when: `npm test -- auth` passes."

---

## File Location

```
project-root/docs/handoffs/
├── LATEST.md              ← Copy of most recent handoff (what /resume reads)
├── 20260219-1430-auth-fix.md
└── 20260218-1600-project-init.md
```

- **Naming:** `YYYYMMDD-HHMM-slug.md` (2-4 word slug)
- **LATEST.md:** Real file (not symlink), overwritten with each handoff.
- **Committed to git.** Handoffs are project history.
- Create `docs/handoffs/` if it doesn't exist.

---

## `/handoff` — Full Session Handoff

End of session. Next session might have zero context.

**Target: 400-700 words.** Over 800 means stable context should move to project docs.

### Procedure

1. Review what happened: decisions, files changed, approaches tried, errors hit, open questions.
2. Write using the template below. Follow core rules.
3. Save to `docs/handoffs/YYYYMMDD-HHMM-slug.md`.
4. Copy to `docs/handoffs/LATEST.md` (overwrite).
5. Confirm: file path, one-line summary, recommended first action.

### Template

```yaml
---
date: YYYY-MM-DD HH:MM
branch: <current git branch>
commit: <short SHA>
status: in_progress | paused | blocked | complete
working_set:
  - path/to/key-file-1
  - path/to/key-file-2
---
```

```markdown
# Handoff: [Brief Title]

## Resume
**Goal:** [One line: what we're building/fixing]
**State:** [1-2 sentences: where things stand now]
**Next:** [Single most important action with file path and success criteria]
**Do not repeat:** [Biggest trap for next session]

## Verify
\`\`\`bash
git status -sb && git log --oneline -3
<one command that demonstrates current state: npm test, curl, etc.>
\`\`\`

## Next Steps
1. **[Action]** — Files: `path/to/file` (~line). Done when: [condition]
2. **[Action]** — Files: `path/to/file`. Done when: [condition]
3. **[Action]** — Done when: [condition]

## Failed Approaches
- **Tried:** [What was attempted]
  - **Signal:** `[Exact error or unexpected behavior]`
  - **Cause:** [Why it failed]
  - **Retry only if:** [What would need to change]

## Decisions
| Decision | Rationale |
|----------|-----------|
| [Choice] | [Why] |

## Notes
- [Session-specific: new deps, env changes, config changes, gotchas]
```

**Section rules:**
- Resume, Verify, Next Steps, Failed Approaches: always include.
- Decisions: include only if decisions were made this session. Omit if empty.
- Notes: include only if there are non-obvious session-specific changes. Omit if empty.
- Never include empty sections or placeholder text.

---

## `/handoff quick` — Lightweight Checkpoint

Mid-session save. You're not done, just need a save point.

**Target: 100-250 words.** Resume block + next steps only.

### Template

```yaml
---
date: YYYY-MM-DD HH:MM
branch: <branch>
commit: <short SHA>
status: in_progress | paused | blocked
---
```

```markdown
# Quick Handoff: [Brief Title]

## Resume
**Goal:** [One line]
**State:** [1-2 sentences]
**Next:** [Single next action]

## Next Steps
1. [Action with specifics]
2. [Action]
3. [Action]
```

---

## `/handoff resume` — Pick Up Where We Left Off

Start of new session. Restores context from last handoff.

### Procedure

1. Read `docs/handoffs/LATEST.md`. If missing, find most recent file by name in `docs/handoffs/`.
2. Parse fully.
3. Confirm before working:
   > "Picking up from [date]. Goal: [goal]. State: [state]. Starting with: [next action]. [N] approaches marked do-not-retry."
4. Run the verify commands. If state has drifted (different branch, new commits, tests failing that handoff says pass), flag it before proceeding.
5. Begin work on highest-priority next step.
6. Do not retry failed approaches unless the human explicitly asks or the "retry only if" condition is met.

---

## `/handoff status` — Project Status Report

Read-only. Quick pulse check for standups or "where are we?"

### Procedure

1. Read `docs/handoffs/LATEST.md`.
2. Check git state (branch, recent commits, dirty files).
3. Optionally run quick health checks (tests, build).

### Output format (under 200 words)

```
**Project:** [name]
**Branch:** [branch] @ [short SHA] [clean/dirty]
**Status:** [in_progress/blocked/paused/complete]
**Last handoff:** [date, brief title]

**Current state:** [2-3 sentences]
**Next priority:** [Single most important action]
**Blockers:** [Any, or "None"]
```

---

## `/handoff transfer` — Full Project Knowledge Transfer

For moving to a different model, tool, or zero-context reader. NOT optimized for tokens. Optimized for completeness.

**When:** Moving between AI tools, onboarding, archiving, "give me everything about this project."

**Target: 2,000-5,000 words.** Be thorough.

### Procedure

1. Read all available context: CLAUDE.md, README, package.json, architecture docs, recent handoffs, git log.
2. Review codebase structure.
3. Gather environment and deployment info.
4. Write using the template below.
5. Save to `docs/handoffs/YYYYMMDD-HHMM-transfer.md` and copy to LATEST.md.

### Template

```markdown
# Project Transfer: [Project Name]

**Date:** YYYY-MM-DD
**Purpose:** [reason: new tool, new model, onboarding, archival]

## What This Project Is
[2-3 sentences: what it does, who it's for, what problem it solves]

## Links and Access
| Resource | URL / Location |
|----------|---------------|
| Repository | [URL] |
| Hosting | [provider + URL] |
| CI/CD | [provider] |
| Project board | [URL] |

*Only include rows that exist.*

## Tech Stack
- **Runtime:** [e.g., Node.js 22]
- **Framework:** [e.g., Next.js 15]
- **Database:** [e.g., PostgreSQL]
- **Key libraries:** [the important ones]

## Repository Structure
\`\`\`
[directory tree, 2-3 levels deep, annotated]
\`\`\`

## How to Run
\`\`\`bash
# Setup
[clone, install, env]

# Dev / Test / Build / Deploy
[commands]
\`\`\`

### Environment Variables
| Variable | Purpose | Where to get it |
|----------|---------|----------------|
| [VAR] | [what] | [where] |

## Architecture
[How the system is structured. Key components and connections.]

## Current State
- **Working:** [what functions correctly]
- **Broken:** [what's failing, with specifics]
- **Not built yet:** [known gaps]
- **Tech debt:** [things that work but need improvement]

## Key Decisions
| Decision | Rationale | Date |
|----------|-----------|------|
| [Choice] | [Why] | [When] |

## Active Context
[What was being worked on. Include or reference latest handoff.]

### Failed approaches (do not retry)
[From recent handoffs]

### Immediate next steps
[Prioritized actions]

## Conventions
- **Git:** [branching, commit format]
- **Code style:** [formatting, patterns]
- **Testing:** [what's tested, expectations]

## Gotchas
- [Things that look wrong but are intentional]
- [Common mistakes in this codebase]
- [Fragile areas]
```

---

## Persistent Context

Handoffs are deltas. Stable context lives elsewhere:

| What | Where |
|------|-------|
| Project overview, conventions, dev commands | `CLAUDE.md` or `README.md` |
| Architecture, system design | `docs/architecture.md` |
| Major decisions | `docs/decisions/ADR-NNN.md` |
| Session state | `docs/handoffs/LATEST.md` |

If you're repeating the same content across handoffs, move it to a persistent file.

---

## Project Setup

Add to the project's CLAUDE.md:

```markdown
## Session Handoffs
Use the handoff skill for session continuity. Files live in docs/handoffs/.
At session start: /handoff resume. At session end: /handoff.
```
