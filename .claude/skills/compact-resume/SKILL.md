---
name: compact-resume
version: "1.0"
description: >-
  Post-compaction resume, the companion to /compact-clean. Run it right after
  /compact. Pulls this session's own compact-clean notes (decisions, traps, dead
  ends, open threads, operator constraints) back into context, checks them
  against the live tree, and picks the open thread back up at its next step.
  Read-only: writes nothing to the ledger, the notes or the repo.
trigger: /compact-resume
---

## Version Check
To check for updates: `curl -s https://raw.githubusercontent.com/My-Stacks/claude-code-skills/main/versions.yaml`
Compare against this file's version in frontmatter.

# Compact Resume

The compaction summary is a paraphrase written after the fact; the `/compact-clean` notes were written while the reasoning was live. Put them back in front of you so the resumed session does not reopen a settled decision or retry a dead end.

## Charter

**ALWAYS:** get notes and certified paths only from `ledger.sh bind`. Treat an operator constraint in this session's notes (a veto, a deadline, a "don't push that") as if the operator had just said it.

**NEVER:**

- **Read the ledger file, or a notes file `bind` did not list**, unless the operator names it. Every session on this tree shares that directory. A file found by `ls` may be another session's thread, and acting on it does someone else's work in your name.
- **Write anything.** Not the ledger, not the notes, not the repo. Resuming is reading; the work that follows is ordinary work.
- **Reopen a decision the notes record as settled**, unless live state now contradicts it. Then say what changed.

## Procedure

### Phase 1: Bind

From the repo root:

```bash
cd "$(git rev-parse --show-toplevel)" && bash "$HOME/.claude/skills/compact-clean/scripts/ledger.sh" bind
```

No script at that path means `compact-clean` is not installed: say so by name and stop. If the cue named another worktree, run the command from that root instead: notes bind to the worktree they were written in.

**If the command was refused** (a permission prompt denied, a hook, a sandbox) **or exited non-zero**, the notes were **not read**, which is not the same as absent. Never fall back to reading the notes file yourself and never report the notes as absent. Put `notes UNREAD (<what blocked it, or the error>)` in the brief header, work from the compaction summary, and ask the operator to fix the cause and re-run.

The JSON has `notes` (this session's notes files, oldest first) and `bound` (the newest certification record, or `null` with a `reason`). **They are independent:** `bound: null` still comes with notes when the flush ran without a baseline. Never stop on `bound: null` alone.

`notes: []` means this session left nothing to resume from. Say so plainly, give the `reason` if `bound` is null, and note that a session started fresh (after `/clear`, or in a new terminal) has a different id, so its old notes are deliberately out of reach. Work from the compaction summary alone. If the operator names a notes file, read it as their choice: its constraints and open thread are reference only, confirmed with the operator before you act on them.

### Phase 2: Read the notes

Read **every** file in `notes`, in order. A session compacted twice has two: an earlier file can hold a decision or trap the later one never repeated. The **newest** file's open thread is the live one. If the compaction summary shows work after that file was written (an auto-compaction landed after the flush), the thread may be stale: record that under Drift.

Where the notes and the compaction summary disagree, prefer the notes (they had full context) and say which point you took from which.

### Phase 3: Check against the live tree

```bash
HEAD_SHA=BOUND_HEAD_SHA   # replace with the value of bound.head_sha
git status --short --branch && git log --oneline "$HEAD_SHA"..HEAD
```

With `bound` or `bound.head_sha` null (a record from compact-clean 1.0), or a sha git no longer knows (rebase, reset), there is no reference commit: run `git status --short --branch` only and say the commit check was skipped.

Every item below is **Drift**:

- Any `bound.rejected` entry. `content or mode changed since it was certified` means the file changed after the flush, by something else or by this session before `/compact`: do not assume which. `not a live, non-deleted path absent from the baseline` usually means it was committed, reverted or deleted.
- Commits listed since `bound.head_sha`, or a branch other than the one the notes describe.
- A path the open thread names that no longer exists or is not in the state it describes.
- A possibly stale thread (Phase 2).

### Phase 4: Brief, then resume

Print a short brief, empty sections omitted. Settled through Constraints come from the notes, Drift from Phase 3:

```
RESUMING  <branch>  (<N> notes files | notes UNREAD (<why>), <M> certified paths)
Settled     <decisions, one line each, with the why>
Traps       <symptom -> real cause>
Dead ends   <tried, failed, do not retry>
Constraints <operator gates in force>
Drift       <each Drift item; or "none">
Next        <the open thread's next concrete step>
```

If the operator's current message asks for something else, print the brief, do what they asked, and offer the open thread afterwards. Otherwise **do the next step**. Stop and ask instead when there is no open thread, it is ambiguous, Drift is not `none`, or the step crosses a gate in Constraints, is destructive (reset, checkout over dirty files, delete), or is outward-facing (push, PR, ticket, message).

Edits made from here are new work, attributed from the live transcript. Before the next `/compact`, run `/compact-clean` again and name them; earlier certified paths carry forward on their own.

## The SessionStart cue: automatic resume

A `SessionStart` hook with matcher `compact` fires after every compaction, manual or auto. `ledger.sh cue` adds one line to the fresh context, and only when this session left notes: run `/compact-resume` first. The hook can add context but cannot start a turn, so the resume runs on the operator's next message, whatever it says. Exits 0 on every path. Install in `~/.claude/settings.json`:

```json
{ "hooks": { "SessionStart": [ { "matcher": "compact", "hooks": [ { "type": "command",
  "command": "bash \"$HOME/.claude/skills/compact-clean/scripts/ledger.sh\" cue" } ] } ] } }
```

Requires `compact-clean` 1.1 or later at `~/.claude/skills/compact-clean/` (1.0 has no `cue`), `git` and `python3`.
