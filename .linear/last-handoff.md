---
date: 2026-03-22
project: Claude Code Skills
goal: "Add pull-and-sync skill and fix ai-router timeout"
---

## Resume
Goal: Ship pull-and-sync skill and fix ai-router API timeout
State: Both PRs open and awaiting review (PR #4 timeout fix, PR #5 pull-and-sync skill)
Next: Merge PRs after Martina reviews, then install pull-and-sync to ~/.claude/skills/
Do not repeat: N/A — clean session

## Changes
- PR #4: Bumped ai-router API call timeout 60s -> 120s (Anthropic Sonnet was timing out at ~56s)
- PR #5: New pull-and-sync skill v1.0 — session-start nudge, multi-branch sync, stash/restore safety
- Linear setup: connected AI team, bound to Claude Code Skills project

## Notes
- ai-router timeout root cause: Anthropic Sonnet takes ~56s for full review responses, network jitter pushed past 60s deadline causing HTTP 000
- pull-and-sync was motivated by Kyle pushing without pulling Martina's changes — skill adds automatic session-start sync check
- Validation calls (10s timeout) left unchanged — they only generate 1 token

## Next Steps
1. Merge PR #4 and PR #5 after Martina reviews
   Done when: Both merged to main
2. Install pull-and-sync skill to other workspaces
   Done when: `~/.claude/skills/pull-and-sync/SKILL.md` exists and session-start nudge fires
