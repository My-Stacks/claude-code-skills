---
name: escape-hatch
version: "1.0"
description: >-
  Escape hatch for leaving a terminal session mid-task without closing the
  work down. Commits and pushes everything that is yours as WIP (never a PR,
  never a merge), fast-forwards the bound Linear project to the current state
  (ticket states, comments, new tickets for unaddressed work), writes the
  handoff, and verifies that /linear resume can restart from the exact moment
  you left. For the end-of-day closedown use /mise-en-place. When you are lost
  mid-task use /housekeeping.
trigger: /escape-hatch
---

## Version Check
To check for updates: `curl -s https://raw.githubusercontent.com/My-Stacks/claude-code-skills/main/versions.yaml`
Compare against this file's version in frontmatter.

# Escape Hatch

*Put the pan on the back burner. Nothing is finished, nothing is thrown out, and the next cook knows exactly where it stands.*

## The test

> **Can a fresh session run `/preflight` then `/linear resume` and execute Next without opening this chat?**

Every step serves that sentence. Nothing here judges the work, closes it out, or cleans the board. It captures the moment and gets you out.

## When to use this instead of the others

| | `/escape-hatch` | `/mise-en-place` | `/housekeeping` |
|---|---|---|---|
| You are | leaving mid-task | done for the day | lost |
| Commits | everything yours, as WIP | only finished work | nothing |
| PR | never | opens one | never |
| Tickets | fast-forward to current state | close settled ones | re-rank with you |
| Reconcile | no | yes | yes |
| Questions | at most one, batched | at the wire boundary | many, by design |

If the work is done, mise-en-place. If you cannot say what the next move is, housekeeping. If you know exactly where you are and just need to leave, this.

## Charter

**Does, announcing each step:** WIP commits of paths this session touched, a push to a same-named branch, ticket state and comment changes through the `/linear` buffer, new tickets through the same buffer, the handoff.

**Asks first:** committing on the default branch, any file it cannot attribute, the push preview, the handoff preview. One batched question for the files, then the two previews `/linear` already shows. Nothing else.

**Never, whatever anyone says mid-run:**

- Opens, closes, or merges a PR. Enables auto-merge.
- Force-pushes, rewrites history, `reset --hard`, `branch -D`, rebases, `--no-verify`. A rejected push is a finding, never a retry.
- Commits to the default or a protected branch without the Phase 2 ask.
- Stages a directory, a glob, `-A`, `-u`, or `commit -a`. Stages a deletion that was not named in the Phase 1 question.
- Commits build output or any gitignored file.
- Deletes any file outside the session scratchpad. Kills any process.
- Changes the state of a ticket assigned to someone else. Comments only.
- Calls the Linear MCP directly. Every ticket write is `/linear track` then `/linear push`.
- Reports success when a push failed, a preview was declined, or `.latest-status.md` fails the Resume spec.
- Does the work it finds. A bug noticed on the way out becomes a ticket, not a fix.

## Invocation

```
/escape-hatch              # full run
/escape-hatch --dry-run    # no writes; every action printed as WOULD: <action>
```

## Procedure

Five phases in order. Announce each one.

### Phase 0: Freeze

One line: what this session was doing and what it was about to do next. Say it before touching anything, while it is still fresh.

Then resolve, and state each:

- **The bound Linear project.** A binding exists only if `.linear/cache.yaml` carries an `active_project`. A fuzzy name match is not a binding. Unbound: Phases 3 and 4 are skipped, the handoff goes only to `.latest-status.md`, and the report says so.
- **The operator.** `gh api user --jq .login` and the Linear viewer. Ownership rules in Phase 3 depend on it.
- **The session scratchpad** path from the harness context.
- **Compaction.** If this session was compacted, say so. The transcript signal below covers only the surviving window.
- **The preflight baseline**, if one exists. Derive the key exactly as preflight does; never from memory.

```bash
root=$(git rev-parse --show-toplevel) || exit 1
raw=$(git remote get-url origin 2>/dev/null | head -1); [ -z "$raw" ] && raw=$root
canon=$(printf '%s' "$raw" | tr 'A-Z' 'a-z' \
  | sed -E 's#^[a-z]+://##; s#^[^@/]+@##; s#:#/#; s#/+$##; s#\.git$##; s#/+$##')
stem=$(printf '%s' "$canon" | tr -c 'a-z0-9._-' '-' | sed -E 's#-+#-#g; s#^[-.]+##; s#[-.]+$##')
hash=$(printf '%s' "$canon" | { shasum 2>/dev/null || sha1sum 2>/dev/null; } | cut -c1-12)
key="${stem:-repo}-${hash}"
base="$HOME/.claude/preflight/${key}.session-start.json"
[ -f "$base" ] && python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print("usable" if d.get("schema")==1 and d.get("root")==sys.argv[2] else "unusable")' "$base" "$root"
```

A baseline is usable only if `schema` is `1` and `root` equals this repo's toplevel. Anything else is absent. Absence is normal for this skill and never suppresses anything; it only changes how Phase 1 classifies files.

**Done when:** the freeze line, binding, operator, scratchpad, compaction state and baseline state are all stated.

### Phase 1: Inventory

Two sources, both required.

**From the conversation.** Answer each in writing. These become the handoff.

- **Objective:** what the session set out to do, as first stated, plus any re-scope and who ruled it.
- **Landed:** what is committed or merged, with SHAs or PR numbers.
- **In flight:** the exact file and function being edited, what the edit is for, and how far it got.
- **Last signal:** the last failing test, error, or unexpected output, verbatim.
- **Next:** the single literal next action. A command to run, or a file and line and the edit to make there. "Continue the refactor" fails this test.
- **Open questions:** anything waiting on the operator or a third party.
- **Dead ends:** what was tried and why it failed, with the retry condition.
- **Unaddressed:** work discovered but not started, and existing tickets whose state no longer matches reality.

**From disk.** Read with these exact flags so the result compares against a baseline:

```bash
git branch --show-current                                  # empty means detached HEAD: stop, report, no commits
git --no-optional-locks status --porcelain -z -uall | tr '\0' '\n'
git stash list
git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1 \
  && git log --oneline @{u}..HEAD || echo "NO UPSTREAM"
lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR>1 {print $9}' | sort -u
```

**Classify every dirty path** into one of three buckets:

- **Commit:** the path appears in this session's own Write, Edit, or Bash write calls, and, when a baseline is usable, is absent from its `porcelain`. Compare whole paths, never substrings.
- **Leave:** present in the baseline's `porcelain` (someone else's WIP), gitignored, or build output. Reported, never staged.
- **Unsure:** everything else. With a compacted session or no baseline this bucket is larger, and that is fine.

Deletions always land in Unsure, named as deletions.

**The one question.** If Unsure is non-empty, ask once, listing every path with your best guess and a default of Leave. Wait. Do not ask again this run. If the branch is the default or protected, fold the Phase 2 branch question into this same message so there is still only one.

**Done when:** the conversation list is written out and every dirty path has a bucket.

### Phase 2: Commit and push

**On the default or a protected branch** (protected: `gh api "repos/:owner/:repo/branches/${branch//\//%2F}" --jq .protected`; if `gh` cannot answer, treat as protected): ask whether to commit on a new `escape/<YYYY-MM-DD>-<slug>` branch or leave the files uncommitted and record them in the handoff. Never commit WIP to the default branch silently. If the answer is an escape branch, create it from HEAD and continue; this is the only branch creation this skill performs.

**Stage by explicit pathspec.** `git add -- "<path1>" "<path2>"`, one quoted argument per file from the Commit bucket plus any Unsure path the operator approved. Then `git diff --cached --name-only` and compare set-for-set against that list; any extra path aborts with `git reset` and a report. Run `git diff --cached` and refuse the commit if it contains a credential shape: `sk-`, `ghp_`, `gho_`, `AKIA`, `xox[baprs]-`, a private key block, `Bearer` plus a long token, or a long random string after `key`, `token`, `secret`, or `password`. Report it; never redact and commit.

**Commit message** carries the resume pointer so `git log` alone tells the story:

```
wip(<scope>): <short state>

Next: <the Phase 1 Next line, verbatim>
Left by /escape-hatch <date>
```

**Push** to a same-named branch when all hold: `git fetch --no-tags origin` first; the branch is not the default and not protected; `git rev-list --left-right --count @{u}...HEAD` shows `0` behind, or there is no upstream and `git push -u origin "<branch>"` creates one; no other worktree has the branch checked out. Behind or diverged: do not push, report who else pushed. No `origin`: report the branch as local-only.

Stashes are reported with their count and never popped or dropped. Listening processes are reported and left running.

**Done when:** every Commit-bucket path is committed, the branch is pushed or its reason for not being pushed is stated, and the tree holds only Leave-bucket paths.

### Phase 3: Fast-forward Linear

Skip cleanly if unbound. Load `~/.claude/skills/mise-en-place/REFERENCE.md` section 3 before this phase if it is installed, for the Linear query shapes and workspace status caveats.

Read the bound project's open tickets: `list_issues` with `includeArchived: false`, fields `id, title, status, statusType, assignee, updatedAt`. Then fill the buffer with `/linear track`, one entry per change, so that the board matches Phase 1's inventory:

| Reality | Track as |
|---|---|
| Ticket's work landed this session | `status_change` to Done, note citing the SHA or PR. **No close without a citation.** |
| Ticket is the in-flight work | `status_change` to In Progress if not already, plus a `comment`: `Left at <sha>. State: <in flight>. Next: <next>.` |
| Ticket is blocked | `comment` naming the blocker and its owner. State unchanged. |
| Ticket title or state is stale but not settled | `comment` with what changed. Bodies are never rewritten. |
| Work discovered, not started, no ticket | `new_issue` with a one-paragraph body: what, why, where in the code. |
| Ticket assigned to someone else | `comment` only, whatever the evidence says. |
| Dead end | `failed_approaches` entry with tried, signal, cause, retry_only_if. |
| Objective | `goal`, if the buffer has none. |

Then `/linear push`. Its preview is the gate. Read it against the inventory before approving: every state change has a citation, every new ticket describes work you can point to, nothing touches another person's ticket state. Decline and fix the buffer rather than approving a wrong preview.

**Done when:** the push preview was approved and every item reports `applied`, or a failed item is named in the report.

### Phase 4: Handoff

**Resolve the destination first** and pass it as `--to`. In order, stop at the first that fires:

1. `~/.claude/mise-en-place/project-map.yml` has an entry for this `org/repo`: use it.
2. The buffer's tickets belong to exactly one project: that project.
3. Two or more projects: ask which is primary. This is a second question and it is allowed only here, because each post is a separate outward notification.
4. Buffer empty and every changed path is inside the tool's own tree: the bound project.
5. Otherwise: the bound project, stated as a fallback.

Record any answer to rung 3 in `project-map.yml` so it is asked once per repo.

Run `/linear handoff --to <project>`. Its preview is the second gate. **Check the Resume block against this spec before approving:**

- **Goal** is the Phase 1 objective, including any re-scope.
- **State** names what landed with SHAs, what is in flight down to file and function, and the last signal verbatim.
- **Next** is one literal command, or one file and line and the edit. Executable cold.
- **Do not repeat** is the top dead end with its retry condition.

If handoff's draft is thinner than the inventory, edit the preview before approving. Never approve a Resume block that fails the spec; the whole run exists to produce it.

Handoff commits `.latest-status.md` and `.linear/last-handoff.md` itself. Record `HEAD` before calling it, then push only the commit it made (`git log <saved>..HEAD`), under the Phase 2 push rules. If both files are gitignored in this repo the commit is a no-op and there is nothing to push; say so.

Unbound repos: write `.latest-status.md` directly using the linear skill's Status File template, commit it by pathspec on the current branch, and report that no project update was posted.

**Done when:** the update is posted, `.latest-status.md` passes the spec, and the handoff commit is pushed or its non-push is explained.

### Phase 5: Verify and release

1. `git --no-optional-locks status --porcelain -z -uall`: only Leave-bucket paths remain.
2. Guarded upstream check: nothing unpushed, or the reason is in the report.
3. Write `~/.claude/escape-hatch/<key>-last-run.md` (`mkdir -p` first) with `date`, `branch`, `landed` (old and new SHAs), `pushed`, `ticket_changes` as a count, `handoff_url`, `left` (paths), and `next` verbatim. Narrate the write.
4. Print the report and the release line.

## Output format

```markdown
ESCAPED     <branch> at <sha>, pushed | local-only (<reason>)
BOUND       <project> | unbound

## Committed
<paths, one line each, or "nothing">

## Left in place
<paths with bucket reason: pre-existing | ignored | build output | operator chose leave. Never omit.>

## Linear
<n> state changes, <n> comments, <n> new tickets. Update: <url>

## Resume
Goal / State / Next / Do not repeat, exactly as written to .latest-status.md
```

Close with:

`Escaped. Safe to close this terminal. Next session: /preflight, then /linear resume.`

If any step was declined or failed, close instead with `Not fully escaped:` and the one thing to fix. Never print the safe-to-close line over a failed push or a rejected preview.

**On abort, write the inventory first.** Before surfacing any error that ends the run, dump the Phase 1 conversation list to `~/.claude/escape-hatch/<key>-abort-<timestamp>.md` and say where it went. It is the only thing a re-run cannot recover.

## Acceptance test

Run it, close the terminal, open a new one, run `/preflight` then `/linear resume`. If the first action the new session proposes is Phase 1's Next, verbatim, the escape worked. If it has to ask you anything, the Resume block was too thin.

## Load REFERENCE when

This skill has no REFERENCE.md. When mise-en-place is installed, its `REFERENCE.md` sections 1 (git sweep), 3 (Linear query shapes), and 7 (redaction) apply here unchanged.
