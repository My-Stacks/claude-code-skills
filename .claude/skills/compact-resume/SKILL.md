---
name: compact-resume
version: "1.0"
description: >-
  Post-compaction resume, the companion to /compact-clean. Run it right after
  /compact. Pulls this session's own compact-clean notes (decisions, traps, dead
  ends, open threads, operator constraints) back into context, checks them
  against the live tree, and picks the open thread back up at its next step.
  Read-only: writes nothing to the ledger or the repo.
trigger: /compact-resume
---

## Version Check
To check for updates: `curl -s https://raw.githubusercontent.com/My-Stacks/claude-code-skills/main/versions.yaml`
Compare against this file's version in frontmatter.

# Compact Resume

## Why

A compaction summary is a paraphrase written after the fact. The notes `/compact-clean` saved were written while the reasoning was still live: which decisions are settled, what looked right and wasn't, what was already tried. This skill puts them back in front of you so the resumed session does not reopen a settled decision or retry a dead end.

## Charter

**ALWAYS:** get notes and certified paths only from `ledger.sh bind`. Treat an operator constraint in the notes (a veto, a deadline, a "don't push that") as if the operator had just said it.

**NEVER:**

- **Read the ledger file, or a notes file `bind` did not list.** Every session on this tree shares that directory. A file found by `ls` may be another session's thread, and acting on it does someone else's work in your name.
- **Write anything.** Not the ledger, not the repo. Resuming is reading; the work that follows is ordinary work.
- **Reopen a decision the notes record as settled**, unless live state now contradicts it. Then say what changed.

## Procedure

### Phase 1: Bind

From the repo root:

```bash
cd "$(git rev-parse --show-toplevel)" && bash "$HOME/.claude/skills/compact-clean/scripts/ledger.sh" bind
```

No script at that path means `compact-clean` is not installed: say so by name and stop. A non-zero exit means nothing is bound: relay the error.

The JSON has `notes` (this session's notes files, oldest first) and `bound` (the newest certification record, or `null` with a `reason`). **They are independent:** `bound: null` still comes with notes when the flush ran without a baseline. Never stop on `bound: null` alone.

`notes: []` means this session left nothing to resume from. Say so plainly, give the `reason` if `bound` is null, and note that a session started fresh (after `/clear`, or in a new terminal) has a different id, so its old notes are deliberately out of reach. Work from the compaction summary alone. If the operator names a notes file, read it as their choice, not yours.

### Phase 2: Read the notes

Read **every** file in `notes`, in order. A session compacted twice has two: an earlier file can hold a decision or trap the later one never repeated. The **newest** file's open thread is the live one.

Where the notes and the compaction summary disagree, prefer the notes (they had full context) and say which point you took from which.

### Phase 3: Check against the live tree

```bash
git status --short && git log --oneline -5
```

- `bound.paths` is this session's certified work, still dirty and unchanged. That is where the open thread left off.
- `bound.rejected` with `content or mode changed since it was certified` means **something else** touched that file: nothing in this session has edited since compaction. Surface it before building on that file.
- Paths the open thread names should still exist and be in the state it describes. A commit, branch switch or vanished file since the flush means someone moved on: report it and do not proceed blindly.

### Phase 4: Brief, then resume

Print a short brief, every section from the notes, empty ones omitted:

```
RESUMING  <branch>  (<N> notes files, <M> certified paths)
Settled     <decisions, one line each, with the why>
Traps       <symptom -> real cause>
Dead ends   <tried, failed, do not retry>
Constraints <operator gates in force>
Drift       <rejected paths, new commits, missing files; or "none">
Next        <the open thread's next concrete step>
```

Then **do the next step**. Stop and ask instead only when there is no open thread, it is ambiguous, Drift is not `none`, or the step crosses a gate in Constraints or is outward-facing (push, PR, ticket, message).

Edits made from here are new work, attributed from the live transcript. Before the next `/compact`, run `/compact-clean` again and name them; earlier certified paths carry forward on their own.

## Relationship to the other skills

| | when | reads | writes |
|---|---|---|---|
| `/compact-clean` | before `/compact` | live session | ledger + notes |
| **`/compact-resume`** | **after `/compact`** | **bound notes + live tree** | **nothing** |
| `/mise-en-place` | end of day | bound record + notes | repo, on approval |

Requires `compact-clean` installed at `~/.claude/skills/compact-clean/`, `git` and `python3`.
