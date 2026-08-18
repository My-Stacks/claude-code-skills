# Mise en Place — Reference

Per-surface detail. `SKILL.md` is the operable document; load this before mutating Linear, before filing the escalation ticket, or before the process and filesystem sweep.

Every command below is **conditional**. Guard on `git rev-parse --git-dir`, a configured `origin`, and `gh auth status`. A missing precondition is a **coverage finding** — name it in the report. Never a silent skip, never an error dump.

---

## 1. Git sweep

Scope is the repo you were invoked from. Dirty state elsewhere is reported, never written to.

```bash
# resolve the default branch — never hardcode main
DEFAULT=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main)

git branch --show-current                   # empty => detached HEAD; stop and report
git status --porcelain                      # empty = clean
git log --oneline "$DEFAULT"..HEAD          # not on the default branch yet

# unpushed — @{u} exits 128 with no upstream, so guard it
if git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1; then
  git log --oneline @{u}..HEAD
else
  echo "NO UPSTREAM — branch has never been pushed; all local commits are unlanded"
fi

git branch -vv | grep ': gone]'             # tracking a deleted remote
git worktree list --porcelain               # stray worktrees
```

**Interpreting it:**

- `git status --porcelain` non-empty → Phase 1. Yours vs pre-existing is settled by the Phase 0 baseline diff, never by judgment.
- `: gone]` → the remote branch was deleted, usually merged. `git remote prune origin` is Posture A. **Deleting the local branch is Posture B** — ask.
- A worktree is reported, never removed.

**Never** `git branch -D`, `git push --force`, `git reset --hard`, `--no-verify`, or a rebase during a closedown. A rejected push is a finding, not a retry.

---

## 2. GitHub sweep

```bash
gh pr list --state open --author @me --json number,title,headRefName,isDraft,reviewDecision
gh pr list --state open --json number,title,author,headRefName    # full set, for the report
gh pr checks <n>                            # CI status
gh pr view <n> --json mergeable,mergeStateStatus,reviewDecision
```

**Unresolved review threads** need GraphQL — `reviewThreads` is **not** a valid `gh pr view --json` field and the command hard-errors:

```bash
gh api graphql -f query='
  query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){
    pullRequest(number:$n){reviewThreads(first:100){nodes{isResolved}}}}}' \
  -F o="$(gh repo view --json owner -q .owner.login)" \
  -F r="$(gh repo view --json name -q .name)" -F n=<n> \
  -q '[.data.repository.pullRequest.reviewThreads.nodes[]|select(.isResolved==false)]|length'
```

**Findings worth reporting:**

- Open PRs — separate *yours from this session* (the branch appears in the Phase 1 ladder) from *pre-existing*. Both get reported; only yours get acted on. Author alone is not the test.
- Draft PRs that are actually finished.
- **`no checks reported`** — absence of CI is a finding. It means the local build was the entire gate.
- `mergeStateStatus: BLOCKED` or `DIRTY` on a PR you thought was ready.

---

## 3. Linear sweep

Requires the Linear MCP. Skip cleanly if the repo has no Linear binding, and say you skipped it.

```
list_projects   query: <project name>   fields: [id,name,status,teams]
list_issues     project: <id>  includeArchived: false  limit: 100
                fields: [id,title,status,statusType,priority,updatedAt,assignee]
```

`list_issues.includeArchived` **defaults to `true`** (unlike `list_projects`, which defaults to false). Omit it and the stale-ticket sweep fills with work archived months ago.

### Ticket-level checks

| Check | Fix |
|---|---|
| Ticket describes work that shipped | Close, citing the merge SHA or check |
| Title carries stale state ("not pushed", "WIP") | Retitle, preserving the original in a comment |
| Body describes an intention overtaken by events | Update the body, don't just close |
| Work happened with no ticket | File one retroactively — search by branch or PR first |
| Not touched in >30 days, not progressing | Disposition rule; usually escalate |

**Never touch a ticket assigned to or created by anyone but the operator**, whatever shipped. Those go in the escalation table with the assignee named. Cap ticket-state mutations at **5 per run**; above that, apply none and escalate the whole set — a closedown that wants to change eight tickets has found a board problem.

Retitling preserves the record: comment `Retitled by /mise-en-place <date>. Was: "<original>". Reason: <reason>.`

### Project-level — delegate, don't write directly

- **Description or metadata drift** → run `/linear sync-project`. Never call `save_project` directly; the fields are `summary` (255 char) and `description`, not `content`.
- **Session status update** → `/linear handoff` in Phase 5 posts it, resolving the destination from the tickets the session touched. Never call `save_status_update` directly — that reintroduces the misrouting bug linear v0.7.0 fixed.
- **Project status enum** (e.g. Backlog → Active) is Posture A, but check the workspace's real status names first — they are workspace-specific (`In Progress` may not exist). Setting a started status may auto-stamp *today* as the start date; correct it to when work actually began.

### Escalation ticket template

One ticket, filed in the same project as the tickets it escalates. If they span projects, one per project — never a mixed ticket. Search for an open issue titled `Board hygiene —` first and update it in place rather than filing a second.

```markdown
Tickets not progressing for more than 30 days get updated or canceled at
closedown. Today is <date>.

<N> were closed directly because shipped reality settles them, each citing its
evidence: <list, one line each>.

The <M> below need a judgment call I should not make alone.

| Ticket | Assignee | State | Last touched | Read | Suggested |
|---|---|---|---|---|---|

## Why this is filed rather than done

<the specific judgment involved — commercial, client-facing, or strategic>
```

---

## 4. Process and filesystem sweep

```bash
# listeners, with start times to compare against the Phase 0 session anchor
lsof -nP -iTCP -sTCP:LISTEN -t | while read -r pid; do
  ps -o pid=,lstart=,command= -p "$pid"
done

# untracked, non-ignored additions — the only real leftovers
git ls-files --others --exclude-standard
```

`jobs -l` is useless here — every Bash call is a fresh non-interactive shell, so it always returns empty and reads as "nothing running." Do not use it. Background tasks started through the harness stay alive until killed.

**Rules:**

- **You may only kill a PID this run's ledger recorded launching.** No ledger entry → no kill. Re-verify with `ps -o pid=,lstart=,command= -p <pid>` before signalling; a recycled PID is a different process.
- A port already listening at session start is the operator's, whatever is on it now.
- `kill <pid>` (TERM) only. **Never** `kill -9`, `pkill`, or `killall`.
- **This skill deletes nothing outside the session scratchpad** — no attribution test, no exceptions. Files written outside it are reported in Still dirty with their paths, marked yours or pre-existing. Deletion is shown as a command for the operator to run.
- **Never delete a gitignored file.** `--ignored` output is local config — `.env`, `settings.local.json`, caches, local databases. It is inventory, not a hit list.

---

## 5. Published artifacts

Only republish an artifact **this session published, from the source file this session wrote**. Anything else — prior sessions, artifacts whose source is gone, artifacts shared with others — is reported as stale in Still dirty with its URL. Never reconstruct an artifact's content to republish it; a rewritten page at the same URL is a silent edit to something people have already read.

---

## 6. Harvest heuristics

| Class | Test | Example |
|---|---|---|
| **Silent-failure trap** | Would it have shipped without anyone noticing? | A class-merge utility that silently dropped a background colour; the page rendered, typechecked and built clean |
| **Environment divergence** | Does dev disagree with prod? | A chunk prefetched in dev but not production, which would have read as a regression |
| **API surprise** | Did a documented API behave unexpectedly? | `getBBox()` returning element-local coordinates, so region filtering matched noise |
| **Rejected approach** | Would someone plausibly retry it? | A texture treatment cut after looking at it, not after reasoning about it |
| **Grounding measurement** | Is it the before-state for a future comparison? | "24 of 36 headings were at body-copy size" |

---

## 7. Redaction

Before writing to any shared or persistent surface — Linear, GitHub, journals, handoffs, artifacts — redact: credentials and tokens in any form, dollar figures from client work, client names and identifiers, and anything the operator marked confidential. Write the shape ("a five-figure retainer"), not the value.

If the host project defines its own data-handling rules, they override this baseline. If it defines none, apply the baseline — **never skip redaction because the pointer resolved to nothing.**
