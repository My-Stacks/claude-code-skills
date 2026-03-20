---
date: 2026-03-20
project: Claude Code Skills
goal: "Build copilot-scoring skill — standardized rubric for evaluating GitHub Copilot code review effectiveness"
---

## Resume
Goal: Build copilot-scoring skill with standardized rubric synthesized from 4 agent self-assessments
State: PR #3 open on feature/copilot-scoring, Martina assigned as reviewer, Copilot review requested
Next: Martina signs off on rubric dimensions/weights, then integrate into ai-router skill
Do not repeat: Don't build as standalone skill — Martina wants it baked into /ai-router

## Changes
- Created copilot-scoring skill v1.0 (2 commits on feature/copilot-scoring)
- Synthesized rubric from Growy, Scout, Prezzo, and Hub Strategist analyses
- PR #3 opened: feat: add copilot-scoring skill v1.0 (k-hud assigned, marti06 reviewing)
- Confirmed vault-backup PR #1 already merged, deleted stale branch
- Confirmed ai-router PR #2 already merged, available on main
- Set up Linear project binding (AI team → Claude Code Skills)

## Failed Approaches
- **Tried:** Creating standalone copilot-scoring skill separate from ai-router
  **Signal:** Martina said "put it in /ai-router pr review through all of them"
  **Cause:** Copilot scoring should be part of the ai-router review routing, not a separate skill
  **Retry only if:** Team decides standalone scoring has independent value beyond ai-router

## Notes
- Copilot can't be added as PR reviewer via gh CLI — it's configured at repo/org level in GitHub settings
- The vault-backup remote branch was already auto-deleted by GitHub on merge
- ai-router v1.1 is on main with ensemble review across Claude, GPT, Gemini
- Next step after Martina approves rubric: integrate copilot-scoring dimensions into /ai-router review as a pre-review gate
