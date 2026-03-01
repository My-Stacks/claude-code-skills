---
name: linear-reference
description: |
  Reference material for Linear skill. Loaded on demand during /linear create
  or when converting plans/reports to tickets. Not needed for board, track,
  push, resume, or handoff operations.
version: "0.2.0"
---

# Linear Skill Reference

Load this file when creating tickets or converting plans to issues.
Not needed for session tracking, board management, or handoff operations.

## Content Extraction from Plans/Reports

Default to minimal. Only add sections that have actual content AND are critical for completion.

**Always include:**

| Ticket Field | Where to Look | Transform |
|-------------|--------------|-----------|
| title | Document heading, first sentence of summary | Action-oriented, 5-10 words: "[Verb] [what] for [purpose]" |
| problem | Summary, Problem, Background, Current State | 2-3 sentences: what's wrong and why it matters |
| solution | Proposed Solution, Approach, Strategy, Design | 2-3 sentences: what will be done (not how) |

**Include only if explicitly present in source AND critical for task completion:**

| Ticket Field | Where to Look | Transform |
|-------------|--------------|-----------|
| acceptance criteria | Benefits, Expected Outcomes, Requirements | Simple checklist, 3-5 items. Given/When/Then only if source uses that format. |
| implementation | Implementation Steps, numbered instructions, file references | Actionable steps with file paths. Max 5 steps. |
| technical notes | Risks, Gotchas, Edge Cases, Dependencies | Known risks, affected files, prerequisites. Max 3 items. |

**Rules:**
- Omit any section with no content. Never use placeholder text.
- Required sections (title, problem): ask for clarification if not extractable.
- Optional sections: omit silently if not in source material.
- **Reference, don't copy.** If source is a long doc, link to it with a 2-sentence summary instead of reproducing content in the ticket.
- **Linear's philosophy: write only as much as you need.** Short, simple, plain language.

## Metadata Inference

| Field | Logic | Set automatically? |
|-------|-------|--------------------|
| labels | Bug fix -> "Bug". New feature -> "Feature". Refactor/cleanup -> "Improvement". Docs -> "Documentation". | Yes |
| project | Use `active_project` from cache. Override if user specifies different. | Yes |
| estimate | See estimate guide below. | Yes |
| priority | Only infer from explicit language: "critical"/"blocking" -> 1 (Urgent), "high priority" -> 2 (High). Otherwise ask or omit. | No (ask) |
| cycle | Use what user says. "current" -> resolve to UUID. Default: no cycle (backlog). | User-provided |
| state | Cycle specified -> first `unstarted` type state. No cycle -> first `backlog` type state. | Yes (from cycle) |
| assignee | If user says "me" or "assign to me", use current user. Otherwise ask or leave unassigned. | No (ask) |

## Estimate Guide

| Points | Scope | Time approximation |
|--------|-------|--------------------|
| 1 | 1-3 files, simple change, single iteration | ~4 hours |
| 2 | 1-5 files, moderate complexity, 2 iterations | ~1 day |
| 3 | 5-10 files, some complexity, may touch shared code | ~2 days |
| 5 | 10-20 files, significant refactoring or new subsystem | ~2-4 days |
| 8 | 20+ files, architectural change, critical path | ~1 week |

## Description Templates

Only include sections that have actual content. Most tickets need only Problem + Solution.

### Minimal (default)
```markdown
## Problem
[2-3 sentences]

## Solution
[2-3 sentences]
```

### Standard Issue (when complexity warrants it)
```markdown
## Problem
[2-3 sentences]

## Solution
[2-3 sentences]

## Acceptance Criteria
- [ ] [criterion]
- [ ] [criterion]
- [ ] [criterion]

## Implementation
[steps with file paths, max 5]

## Notes
[risks, gotchas, max 3 items]
```

### Bug Report
```markdown
## Bug
[What's broken, 2-3 sentences]

## Reproduce
[Steps, numbered]

## Expected vs Actual
[Expected behavior]. Instead, [actual behavior].

## Environment
[Relevant env details, 1-2 lines]
```

### Template Selection
1. Explicit request ("use bug template") -> that template.
2. Label inference: "Bug" label -> bug template.
3. Source complexity: 3+ sections of detail in source -> standard template.
4. Default: minimal template.

## Proposal Format

Show before every `/linear create`:

```
## Ticket Proposal

**Title:** [title]
**Labels:** [labels] (reason: [why])
**Project:** [project]
**Estimate:** [n]pt ([file count], [complexity])
**Cycle:** [cycle or "Backlog"]
**State:** [state] (auto: [reason])
**Assignee:** [name or "Unassigned"]

### Description
[rendered template sections with content]

---
Ready to create? Or adjust anything?
```
