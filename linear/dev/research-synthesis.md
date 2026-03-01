---
type: work
topic: Linear Skill Optimization Research
date: 2026-03-01
status: active
priority: high
key_facts:
  - Linear's own docs advocate SHORT, SIMPLE issues with OPTIONAL descriptions
  - Anthropic context engineering targets ~200 words for summaries
  - Current handoff format targets 400-800 words, producing 2+ page updates
  - Resume block (4 lines) is the actual high-value payload
  - wrsmith108 skill reveals MCP reliability issues (search/update timeout)
  - Linear has TWO text fields: description (255 char) and content (unlimited)
  - Project update max: 10,000 characters
blockers: none
decisions:
  - Reduce handoff target from 400-800 words to 200-400 words
  - Add lazy-loading to resume (parse Resume block first)
  - Default ticket creation to 3 sections instead of 6
  - Add /linear context command for visibility
next_actions:
  - Apply changes to SKILL.md and REFERENCE.md
  - Test with real handoff/resume cycle
---

## Research Sources

1. Linear docs: "Write Issues, Not User Stories" (linear.app/docs)
2. Linear docs: Initiative and Project Updates
3. Anthropic: "Effective Context Engineering for AI Agents"
4. wrsmith108/linear-claude-skill (GitHub)
5. CCPM: Claude Code Project Management (aroussi.com)
6. Cyrus Agent pattern (parallel worktrees + Linear streaming)

## Problem Statement

The Linear skill produces verbose output in two places:
- **Project updates (handoff)**: 400-800 word target creates 2+ page updates that flood Linear
- **Ticket descriptions**: 6-section template creates unnecessarily detailed tickets

This wastes tokens on resume (pulling bloated updates back into context) and makes Linear noisy for human readers. The core tension: need enough context for session continuity, but not so much that it's wasteful.

## Finding 1: Linear's Own Philosophy Contradicts Verbose Tickets

Linear's documentation is explicit:
- Title: 5-10 words, action-oriented, scannable
- Description: OPTIONAL. "Write only as much as you need to share to perform the task"
- Quote user feedback directly instead of summarizing
- Everyone writes their own issues (forces deep thinking about what matters)

**Implication:** The REFERENCE.md 6-section template (problem, solution, acceptance criteria, implementation, technical notes) directly contradicts Linear's design philosophy. Default should be minimal: title + 2-3 sentence problem + 2-3 sentence solution. Other sections only when explicitly present in source material AND critical for completion.

## Finding 2: The Resume Block Is the Only Thing That Matters for Session Continuity

Current handoff format has 5 sections: Resume, What Changed, Failed Approaches, Notes, Next Steps. But when `/linear resume` runs, it really only needs:

1. **Resume block** (Goal, State, Next, Do not repeat): 4 lines, ~50 words
2. **Failed approaches**: prevents wasted retries
3. **Board state**: fetched live from Linear, always current

"What Changed" is historical record (useful for humans, low value for agents). "Notes" are session-specific (usually stale by next session). "Next Steps" duplicates Resume.Next with extra detail.

**Implication:** Restructure handoff into two tiers:
- **Tier 1 (always in update):** Resume block + failed approaches + next action
- **Tier 2 (available on demand):** Full changelog, notes, detailed next steps stored in `.linear/last-handoff.md`

## Finding 3: Context Engineering Best Practices Target ~200 Words

Anthropic's context engineering guide and OpenAI's patterns both converge:
- Summaries should be ~200 words
- Preserve: architectural decisions, unresolved bugs, implementation details
- Discard: redundant tool outputs, completed work details
- Progressive disclosure: start lean, pull details on demand

Current 400-800 word target is 2-4x the recommended size. Even 200-400 is generous.

## Finding 4: MCP Reliability Affects Architecture

wrsmith108's skill documents that Linear MCP has reliability issues:
- Create issue: reliable
- Search issues: times out
- Update status: unreliable
- Add comment: broken

This matters because the skill's buffer-then-push architecture already mitigates some of this. But it means `/linear resume` should minimize API calls: fetch one project update, parse locally, avoid round-trips.

## Finding 5: Linear's Two Text Fields

Linear projects have `description` (255 chars, shows in list views) and `content` (unlimited, shows in detail panel). The skill should always set both when creating projects. For issues, `description` is the body field (confusingly).

## Specific Changes

### SKILL.md Changes (v0.3.1 -> v0.4.0)

**1. Handoff format: Leaner, tiered**

Before (400-800 word target):
```
## Session: [Date] [Brief Title]
### Resume (4 lines)
### What Changed (full list)
### Failed Approaches (all of them)
### Notes (all of them)
### Next Steps (all of them, with file paths and line numbers)
```

After (150-300 word target for Linear update):
```
## Session: [Date] [Brief Title]
### Resume
Goal: [1 line]
State: [1 line]
Next: [1 line with file path]
Do not repeat: [1 line]

### Key Changes
- [issue key]: [2-3 word outcome] (max 5 items)

### Traps
- [failed approach + cause, 1 line each] (max 2 items)
```

Full session details stored in `.linear/last-handoff.md` for on-demand retrieval.

**2. Resume: Lazy-load**

Before: Fetch update, parse everything, fetch board, synthesize.
After:
1. Fetch update, parse ONLY Resume block (4 lines)
2. Fetch board state
3. Confirm with user: "Goal: X. Starting with: Y. Board: N in progress."
4. Store full update in `.linear/last-handoff.md`
5. If agent needs failed approaches or notes, read from local file (no API call)

**3. Add `/linear context` command**

Shows current loaded state without API calls:
```
Linear: Auth Service (3 buffered changes)
Last handoff: Feb 21 "Auth module refactor"
Board: 2 in progress, 4 todo, 1 blocked
Resume: Goal: Fix token refresh | Next: Update test fixtures
```

**4. Add Verbosity Control section**

Explicit targets for each output type. Replaces implicit "should be concise" with measurable limits.

### REFERENCE.md Changes (v0.1.0 -> v0.2.0)

**1. Default ticket sections: 3 instead of 6**

Before: title, problem, solution, acceptance criteria, implementation, technical notes
After: title, problem (2-3 sentences), solution (2-3 sentences)
Optional (only if in source AND critical): acceptance criteria (checklist), implementation, technical notes

**2. Acceptance criteria format**

Before: Given/When/Then by default
After: Simple checklist (3-5 items). Given/When/Then only if source uses that format.

**3. Add reference pattern**

Instead of copying full plan content into ticket body, add: "See [doc link]" with 2-3 sentence summary.

## Token Impact Estimate

| Component | Before (est. tokens) | After (est. tokens) | Reduction |
|-----------|---------------------|---------------------|-----------|
| Handoff update | 600-1200 | 200-400 | ~65% |
| Resume context load | 800-1500 | 200-400 | ~75% |
| Ticket description | 300-800 | 100-300 | ~65% |
| Per-session total | 1700-3500 | 500-1100 | ~70% |

These are rough estimates based on typical word-to-token ratios (1 word ≈ 1.3 tokens).
