---
name: compact-clean
version: "1.0"
description: >-
  Pre-compaction flush for a working session. Run it right before /compact, or
  when the context bar is getting full. Certifies which files this session
  edited and saves the session's live judgment (decisions, traps, dead ends) to
  a local ledger that survives compaction, so the post-compact session resumes
  without re-deriving and /mise-en-place can still land the work. Writes nothing
  into the repo and lands nothing. For the end-of-day closedown that commits,
  pushes and PRs, use /mise-en-place.
trigger: /compact-clean
---

## Version Check
To check for updates: `curl -s https://raw.githubusercontent.com/My-Stacks/claude-code-skills/main/versions.yaml`
Compare against this file's version in frontmatter.

# Compact Clean

## What compaction destroys

`/preflight`'s baseline is a file and `git status` is a live read, so the change set survives compaction. What dies is **authorship**: this session's own knowledge that *it* made an edit. Without it, "changed since session start" and "changed by this session" are indistinguishable, and `/mise-en-place` correctly refuses to commit. This skill writes the authorship down while you still hold it. Only a model can do that, which is why the hook below is a partial net and not a substitute.

## Charter

**ALWAYS:** write only under `~/.claude/compact-clean/`, outside every repo, and only through `scripts/ledger.sh`. Announce what was written; do not ask.

**NEVER**, whatever the announcement or approval:

- **Commit, stage, push, or open a PR.** This runs mid-session; a mid-session commit is the work, not housekeeping.
- **Write inside a repo.** Not `journal/`, not `.linear/`, not a scratch file.
- **Mutate a ticket, post a status, or notify anyone.**
- **Certify a path this session did not deliberately edit.** Over-certifying is the one failure here that can cost someone their work, because `/mise-en-place` commits what this file certifies. Unsure means leave it out: it stays a candidate.
- **Hand-write or rewrite a ledger record.** The script appends; records are never edited.

## Invocation

```
/compact-clean              # certify + notes, then hand you the exact /compact line
/compact-clean --evidence   # snapshot only: nothing certified, nothing will land
```

Run it **immediately before** `/compact`. Anything done between the two is uncertified.

Each call below is self-contained: it derives the key, tree and baseline itself, byte-identical to `/preflight`, so nothing needs to persist between shell calls.

## Procedure

### Phase 1: Probe

```bash
bash "$HOME/.claude/skills/compact-clean/scripts/ledger.sh" probe
```

States the root, key, baseline and ledger path. **Baseline ABSENT** means nothing certified now can ever land (`/mise-en-place` binds every record to the baseline in force). Still run Phases 3 **and** 4 so the notes are written, and tell the operator to run `/preflight`.

Under `--evidence`, run `bash "$HOME/.claude/skills/compact-clean/scripts/ledger.sh" evidence </dev/null` instead, relay its output, and stop.

### Phase 2: List your edits

List every path **you deliberately changed** in the live part of this session: written, edited, created, or changed by a command whose purpose was to change that file (`sed -i` on it, a heredoc into it).

- **Only what you remember first-hand.** Edits certified before an earlier compaction are carried forward automatically; never re-list them from a summary's description.
- **Side effects are not edits.** A lockfile from an install, formatter or codegen output over a glob, build artifacts: leave them out. They fall into candidates and are reported, never committed.
- **Shared files.** If you know another session, agent or person also edited a file you edited, leave it out. Attribution is by path, so their changes would be certified along with yours.
- **Deletions are never certified.** The script drops them; closedown handles them deliberately.

Name paths **repo-relative**, and run the Phase 4 command from the repo root exactly as shown (absolute paths also work). A bare name is read from the directory the command runs in, never guessed at the root, because a same-named file there may be another session's.

### Phase 3: Harvest the volatile half

Write down only what a fresh reader could not recover from the diff:

- **Decisions and their why**, especially ones already litigated, so they are not reopened.
- **Traps**: what looked right and wasn't, with the symptom that gave it away.
- **Dead ends**, so they are not retried.
- **Open threads**: what you were mid-way through, and the next concrete step.
- **Operator constraints**: a veto, a deadline, a "don't push that".

Prose, not a transcript. Nothing worth keeping means no notes, stated in one line.

### Phase 4: Write the record

```bash
cd "$(git rev-parse --show-toplevel)" && bash "$HOME/.claude/skills/compact-clean/scripts/ledger.sh" certify -- <path> <path> ... <<'CC_NOTES_END'
<notes from Phase 3>
CC_NOTES_END
```

With no notes, end the command with `</dev/null` instead of the heredoc. Always supply stdin one way or the other. Options go **before** `--`, each as its own word (`--drop path`, never `--drop=path`); the script refuses anything else rather than guess, because a misread `--drop` would re-certify the file being disclaimed.

**Binding is mechanical.** Every record carries a hash of `CLAUDE_CODE_SESSION_ID` (never the id itself), and closedown trusts only records from its own session. Subagents share their parent's id, which is the parent's delegated work; concurrent runs are serialised by a lock, so none is lost. You never handle a record id. If that variable is unset, the script writes nothing and says so: the certification and notes then exist only in this context.

**Carry-forward is automatic.** This session's earlier certification is carried into each new record, as long as each file is still dirty and its content and mode are **unchanged** since it was certified (a `chmod +x` is an edit). A file changed afterwards and not named again is reported `NOT CARRIED`: something else edited it. Name it again only if that edit was yours.

**Corrections.** If the operator says a certified path is not yours, re-run from the repo root with `certify --drop <repo-relative path> </dev/null`. A drop is **sticky and has no undo**: that path is never certified again this session, so if it was yours after all, it is reported at closedown and the operator commits it by hand. A `--drop` that matches nothing fails without writing. The newest record supersedes, including when it certifies nothing: closedown never falls back to an older one.

The script classifies each path you named: **Certified** (dirty now, absent from the baseline), **Pre-existing** (dirty before the session; never certified), **Dropped** (clean now, a deletion, outside the repo, `--drop`, or no baseline). Everything else dirty is a **Candidate**: reported at closedown, never committed.

### Phase 5: Hand off

Relay the script's report verbatim. It ends with one of:

- `Safe to compact.` The operator can run `/compact`.
- `Nothing certified` or `Baseline ABSENT`. Say plainly that no work from this record can land, though its notes will be harvested.

If the script exited non-zero, say the record was **not** written and that the certification exists only in this context: compacting now loses it.

## Ledger format

One JSON object per line in `~/.claude/compact-clean/<key>.ledger.jsonl`, append-only. `<key>` is shared by every worktree of an origin; `root` tells them apart.

| field | meaning |
|---|---|
| `schema` | `1` |
| `writer` | `compact-clean 1.0`, or `compact-clean 1.0 (hook)` |
| `record_id` | random 12-hex id, for reports and notes filenames; binding does not use it |
| `root` | repo toplevel |
| `session` | `sha256:` of `CLAUDE_CODE_SESSION_ID` (manual) or of the hook payload's `session_id`: the binding |
| `written_at` | epoch seconds |
| `baseline_started_at` | `started_at` of the baseline in force, or `null` if none |
| `head_sha` | `HEAD` at write time |
| `certified` | `true` only from `certify` with a baseline and at least one path |
| `paths` | certified repo-relative paths, cumulative for the session |
| `fingerprints` | `<mode> <blob>` per certified path, as git would stage it (a symlink by its link text) |
| `dropped` | paths disclaimed this session; sticky |
| `candidates` | dirty paths (and rename sources) absent from the baseline and not certified |
| `baseline` | whether a valid baseline was found |
| `notes` | `<key>.<tree>.<record_id>.notes.md` in the same directory, or `null` |
| `trigger` | `manual`, `evidence`, or `hook-<auto\|manual\|unknown>` |

Closedown reads it only through `ledger.sh bind`, and checks what it staged with `ledger.sh verify-staged`; never directly. `tests/run.sh` covers the attribution rules.

## The PreCompact hook: a partial net

Auto-compaction fires without warning, which is exactly the long session this skill protects. `PreCompact` runs a command hook: a shell, no model. It therefore records evidence only (`certified: false`): the candidate set and the moment of compaction, so closedown reports accurately instead of reporting clean. It cannot preserve the ability to land work, and it captures no notes. A manual `/compact` fires it too, adding an uncertified record right after yours; that is harmless.

Install: copy this skill directory to `~/.claude/skills/compact-clean/` (the path below assumes it), then add to `~/.claude/settings.json`:

```json
{ "hooks": { "PreCompact": [ { "hooks": [ { "type": "command",
  "command": "bash \"$HOME/.claude/skills/compact-clean/scripts/ledger.sh\" hook" } ] } ] } }
```

Hook mode exits 0 on every path. Failing a compaction to protect a bookkeeping file has its priorities backwards.

## Relationship to the other skills

| | when | lands work | writes to repo |
|---|---|---|---|
| `/preflight` | session start | no | no |
| **`/compact-clean`** | **before compaction** | **no** | **no** |
| `/housekeeping` | mid-task, lost | no | on approval |
| `/mise-en-place` | end of day | yes, to PR | on approval |
