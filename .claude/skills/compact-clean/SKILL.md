---
name: compact-clean
version: "1.0"
description: >-
  Pre-compaction flush for a working session — run it right before /compact,
  or when the context bar is getting full. Certifies which files this session
  edited and writes the session's live judgment (decisions, traps, dead ends)
  to a local ledger that survives compaction, so the post-compact session
  resumes without re-deriving and /mise-en-place can still land the work.
  Writes nothing into the repo and lands nothing. For the end-of-day closedown
  that commits, pushes and PRs, use /mise-en-place.
trigger: /compact-clean
---

## Version Check
To check for updates: `curl -s https://raw.githubusercontent.com/My-Stacks/claude-code-skills/main/versions.yaml`
Compare against this file's version in frontmatter.

# Compact Clean

*Compaction is not the enemy. Unplanned compaction is.*

## The test

> **After the context is compacted, can this session still commit its own work — and can it avoid re-deciding what it already decided?**

Everything here serves those two answers. Nothing else earns a line.

## What compaction actually destroys

This is the whole reason the skill exists, and it is narrower than it looks.

`/preflight`'s baseline is a file on disk — compaction cannot touch it. `git status` at closedown is a live read — compaction cannot touch that either. So the *change set* ("what is dirty that wasn't at session start") survives intact.

What dies is **authorship certification**: the session's own knowledge that *it* made those edits. Without it, "changed since session start" and "changed by this session" become indistinguishable, and a background build, a second agent, a teammate's editor or a stray script are all equally good explanations for a dirty path.

`/mise-en-place` refuses to commit on that ambiguity — correctly. This skill removes the ambiguity by writing the certification down while the session still holds it.

**Corollary:** the certification can only come from the model. No shell script can produce it. That is why the PreCompact hook below is a *partial* net and not a replacement for running this skill.

## Charter

**ALWAYS** — this skill writes only to `~/.claude/compact-clean/`, outside every repo.

- Write the ledger record and the notes file. Announce the paths; do not ask.

**NEVER** — no announcement and no approval makes these allowed.

- **Commit, stage, push, or open a PR.** This skill does not touch the ladder. It runs mid-session, often unattended, and a mid-session commit is the work, not housekeeping.
- **Write anything inside a repo.** Not `journal/`, not `.linear/`, not a scratch file. The ledger is local-only, always, even in a repo that has opted into an in-repo journal. It may fire automatically; automatic writes into a client's tree are how you end up explaining yourself.
- **Mutate a ticket, post a status, or notify anyone.** Nothing here crosses the wire.
- **Certify a path the session did not edit.** An uncertain path is recorded as a candidate, never as certified. Over-certifying is the one failure here that can cost someone their work, because `/mise-en-place` trusts this file.
- **Delete or rewrite an earlier ledger record.** Append only. A session may compact many times.

## Invocation

```
/compact-clean              # certify + write notes, then tell you it is safe to /compact
/compact-clean --evidence   # snapshot only: no certification, no notes (what the hook does)
```

Run it **immediately before** `/compact`. Anything you do between the two is uncertified.

## Procedure

### Phase 1 — Derive the key and read the baseline (no writes)

The ledger must land beside the baseline it will be read with, so the key derivation is **byte-identical to `/preflight` Step 3 and `/mise-en-place` Phase 0**. Never reconstruct it from memory — a one-character deviation writes a ledger nothing will ever read.

```bash
root=$(git rev-parse --show-toplevel) || exit 1
raw=$(git remote get-url origin 2>/dev/null | head -1); [ -z "$raw" ] && raw=$root
canon=$(printf '%s' "$raw" | tr 'A-Z' 'a-z' \
  | sed -E 's#^([a-z]+://([^/@]+@)?[^/:]+):[0-9]+/#\1/#; s#^[a-z]+://##; s#^[^@/]+@##; s#:#/#; s#/+$##; s#\.git$##; s#/+$##')
stem=$(printf '%s' "$canon" | tr -c 'a-z0-9._-' '-' | sed -E 's#-+#-#g; s#^[-.]+##; s#[-.]+$##')
hash=$(printf '%s' "$canon" | { shasum 2>/dev/null || sha1sum 2>/dev/null; } | cut -c1-12)
key="${stem:-repo}-${hash}"
tree=$(printf '%s' "$root" | { shasum 2>/dev/null || sha1sum 2>/dev/null; } | cut -c1-12)
```

Read `$HOME/.claude/preflight/${key}.${tree}.session-start.json`. The baseline is **per-tree** as of `/preflight` 5.3 — `$key` alone names whichever sibling worktree wrote last, so reading it would certify against another tree. If that file is missing, fall back to the same root-glob `/mise-en-place` uses: scan `~/.claude/preflight/*.session-start.json` and take the one whose top-level `root` field equals `$root` (never by grep — `worktrees` lists every sibling path, so a text match confirms a sibling's file). That fallback also recovers a baseline left by a pre-5.3 `/preflight`, which used the un-treed name. Either way **verify its `root` matches `$root`**; a mismatch means it belongs to a sibling worktree, so treat it as absent.

**No baseline is not a reason to stop.** Write the ledger anyway with `"baseline": false` — the certification is still the scarce thing, and `/mise-en-place` can pair it with a baseline written later. Say plainly that closedown will still be report-only until `/preflight` has run.

**Done when:** `$key`, `$root` and baseline presence are resolved and stated in one line.

### Phase 2 — Certify authorship (the load-bearing phase)

List every path **this session edited**, from your own memory of the session — files you wrote, changed, or created, whether through an edit tool or through a shell command. Under a shell-first working style the transcript holds no `file_path` fields at all, so this list cannot be derived mechanically; it is yours to produce.

Then intersect it with reality. Read the tree with **exactly the flags `/preflight` used to write the baseline** — `--no-optional-locks ... -z -uall`. Without `-uall` a new file inside a new directory collapses to `?? newdir/`, which never compares equal to the full path the baseline stored, so every such file is misread as a candidate:

```bash
mkdir -p "$HOME/.claude/compact-clean"
tmp="$HOME/.claude/compact-clean/.${key}.${tree}.porcelain.$$"   # never /tmp: the charter keeps every
trap 'rm -f "$tmp"' EXIT                                        # write under ~/.claude/compact-clean/,
git --no-optional-locks status --porcelain -z -uall > "$tmp"     # and a fixed name collides across sessions
                                                                 # -z: a filename may contain a newline
```

Classify each path you named:

- **In your list and dirty now and absent from the baseline** → `certified`. This is the set `/mise-en-place` may commit.
- **In your list but present in the baseline** → `pre-existing`. You edited a file that was already dirty; authorship of the *earlier* change is not yours. Record it as a candidate, never certified.
- **Dirty now but not in your list** → `candidate`. Something changed it and you cannot say what. Record it so closedown can report it as still dirty.
- **In your list but clean now** → dropped, with a one-line note. It was reverted or already committed.

**State the certified list to the operator before writing it.** This is the one moment a wrong entry is cheap to fix; after compaction you will not remember enough to catch it.

**Under `--evidence`, skip this phase entirely** and record every dirty-not-in-baseline path as `candidate`. Certification requires a model that remembers the session; a hook has neither.

**Done when:** the four buckets are printed, certified first.

### Phase 3 — Harvest the volatile half

The change set survives compaction. Your reasoning does not. Write down only what a fresh reader could not recover from the diff:

- **Decisions and their why** — especially the ones already litigated. This is what stops the post-compact session reopening a settled question.
- **Traps** — the thing that looked right and wasn't, with the symptom that gave it away.
- **Dead ends** — approaches ruled out, so they are not retried at cost.
- **Open threads** — what you were mid-way through, and the next concrete step.
- **Anything the operator said that constrains the work** — a veto, a deadline, a "don't push that".

Skip anything already in the diff, the commit messages, or a ticket. Prose, not a transcript. If the session produced nothing worth keeping, say so in one line and write no notes file — an empty notes file reads as a lost session.

**Done when:** notes are written, or their absence is stated.

### Phase 4 — Write the ledger (append only)

```bash
mkdir -p "$HOME/.claude/compact-clean"
ledger="$HOME/.claude/compact-clean/${key}.ledger.jsonl"
```

Append **one JSON object on one line**, built with `python3` — never string-concatenated, because a path may contain quotes, backslashes or a newline and a malformed line poisons every later read:

| field | meaning |
|---|---|
| `schema` | `1`. A reader refuses what it does not understand rather than misreading a renamed field. |
| `writer` | `compact-clean 1.0` or `compact-clean 1.0 (hook)`. |
| `root` | repo toplevel. The identity test — the key is shared by every worktree of one origin. |
| `session_id` | groups records from one session across repeated compactions. |
| `written_at` | epoch seconds. Staleness is the reader's call, not this skill's. |
| `head_sha` | `HEAD` at write time, so a reader can bound commits made after it. |
| `certified` | `true` only from Phase 2. `--evidence` and the hook always write `false`. |
| `paths` | the certified list. Empty under `--evidence`. |
| `candidates` | dirty-not-in-baseline paths this run could not certify. |
| `baseline` | whether a `root`-matching baseline existed. |
| `notes` | path to the notes file, or `null`. |
| `trigger` | what wrote the record: absent for a manual run, `precompact-hook` from the `PreCompact` hook. |

Open the ledger in **append mode** (`open(ledger, "a")`) and write the finished line in a single call. Never build a replacement file and `mv` it into place: that destroys every earlier record, and this ledger is append-only because one session may compact many times. Serialise the whole line in memory first and write it only if non-empty — a half-written line is worse than no line, because it looks like data.

**Done when:** the record is appended and its path reported.

### Phase 5 — Report and hand off to /compact

Six lines, no more:

```
COMPACT CLEAN
Certified   <n> paths (listed)
Candidates  <n> — reported at closedown, never committed
Notes       <path> | none — nothing worth keeping
Baseline    present | absent — closedown is report-only until /preflight runs
Safe to compact.
```

End on `Safe to compact.` only when the ledger write succeeded. If it failed, say so in its place and say the certification is still in this context — compacting now loses it.

## The PreCompact hook — a partial net, and why

Auto-compaction fires without warning when the context fills, which is exactly the long session this skill protects. A `PreCompact` command hook catches that case.

**It cannot certify.** Prompt-based hooks — the kind that can reason — support only `Stop`, `SubagentStop`, `UserPromptSubmit` and `PreToolUse`; `PreCompact` is a command hook, so it gets a shell and no model. It therefore runs the `--evidence` path: snapshot porcelain, `HEAD` and the timestamp, mark `certified: false`.

That is still worth having. It preserves the candidate set and the exact moment of compaction, so closedown can report accurately instead of reporting clean. But it does **not** preserve the ability to land the work, and it captures no notes. Only running this skill does that.

Install `hooks/precompact-snapshot.sh` and wire it into `~/.claude/settings.json`:

```json
{ "hooks": { "PreCompact": [ { "hooks": [ { "type": "command",
  "command": "$HOME/.claude/skills/compact-clean/hooks/precompact-snapshot.sh" } ] } ] } }
```

The script exits 0 on every path, including outside a git repo. A hook that fails a compaction to protect a bookkeeping file has its priorities backwards.

## Relationship to the other skills

| | when | lands work | writes to repo |
|---|---|---|---|
| `/preflight` | session start | no | no |
| **`/compact-clean`** | **before compaction** | **no** | **no** |
| `/housekeeping` | mid-task, lost | no | on approval |
| `/mise-en-place` | end of day | yes, to PR | on approval |

`/preflight` opens the session and `/mise-en-place` closes it; this one keeps the thread intact in between. It is not a mini-closedown — it deliberately lands nothing, because the session is not over.
