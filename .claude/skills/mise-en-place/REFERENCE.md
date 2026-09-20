# Mise en Place — Reference

Per-surface detail. `SKILL.md` is the operable document; load this **before the Phase 1 push/PR preconditions** (§1 holds the default-branch resolution they depend on), before mutating Linear, before filing the escalation ticket, and before the process and filesystem sweep.

Every command below is **conditional**. Guard on `git rev-parse --git-dir`, a configured `origin`, and `gh auth status`. A missing precondition is a **coverage finding** — name it in the report. Never a silent skip, never an error dump.

---

## 1. Git sweep

Scope is the repo you were invoked from. Dirty state elsewhere is reported, never written to.

```bash
# resolve the default branch — never assume main.
# origin/HEAD is often unset (shallow/older clones), so fall back to the remote's
# own answer before guessing; if neither resolves, report it and skip the check.
# $repo is Phase 0's pinned origin (gh repo view "$(git remote get-url origin)") — unpinned
# gh on a clone with an `upstream` remote answers for the parent, not origin.
DEFAULT=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null) \
  || DEFAULT="origin/$(gh repo view "$repo" --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null)" \
  || DEFAULT=""
[ "$DEFAULT" = "origin/" ] && DEFAULT=""

git branch --show-current                   # empty => detached HEAD; stop and report
git status --porcelain                      # empty = clean
[ -n "$DEFAULT" ] && git log --oneline "$DEFAULT"..HEAD   # not on the default branch yet
                                            # empty DEFAULT => coverage finding, not a guess

# unpushed — @{u} exits 128 with no upstream, so guard it
if git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1; then
  git log --oneline @{u}..HEAD
else
  echo "NO UPSTREAM — branch has never been pushed; all local commits are unlanded"
fi

LC_ALL=C git branch -vv | grep ': gone]'    # tracking a deleted remote (LC_ALL: git localises this)
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
gh pr list --repo "$repo" --state open --author @me --json number,title,headRefName,isDraft,reviewDecision
gh pr list --repo "$repo" --state open --json number,title,author,headRefName    # full set, for the report
gh pr checks --repo "$repo" <n>             # CI status
gh pr view --repo "$repo" <n> --json mergeable,mergeStateStatus,reviewDecision
```

**Unresolved review threads** need GraphQL — `reviewThreads` is **not** a valid `gh pr view --json` field and the command hard-errors:

```bash
gh api graphql -f query='
  query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){
    pullRequest(number:$n){reviewThreads(first:100){pageInfo{hasNextPage} nodes{isResolved}}}}}' \
  -F o="${repo%/*}" -F r="${repo#*/}" -F n=<n> \
  -q '{n:[.data.repository.pullRequest.reviewThreads.nodes[]|select(.isResolved==false)]|length, more:.data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage}'
# `more:true` means >100 threads — report a coverage finding, never the truncated count.
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
| Body describes an intention overtaken by events | **Escalate.** Rewriting a body overwrites what a person wrote they intended to do. This skill does not write ticket bodies. |
| Work happened with no ticket | **Escalate.** Name the work and its branch/PR in the escalation table. Filing a ticket is a claim about what was planned and it notifies the team — outside this skill's charter. |
| Not touched in >30 days, not progressing | Disposition rule; usually escalate |

**Close only tickets assigned to the resolved current user** (Phase 0). Unassigned is not yours — on a shared board it is the default state of everything nobody has picked up. Anything assigned to or created by someone else, and anything unassigned, goes in the escalation table with its assignee named. Cap ticket-state mutations at **5 per day, cumulative across runs** (SKILL.md Phase 3 is normative); above that, apply none and escalate the whole set — a closedown that wants to change eight tickets has found a board problem.

Retitling preserves the record: comment `Retitled by /mise-en-place <date>. Was: "<original>". Reason: <reason>.`

### Project-level — delegate, don't write directly

- **Description or metadata drift** → `/linear sync-project`, but note it overwrites description, summary, dependencies **and** metadata from repo state. Posture A covers it only when all of those are empty; a single non-empty field among them makes the whole call Posture B — show what would be replaced, and wait. Never call `save_project` directly; the fields are `summary` (255 char) and `description`, not `content`.
- **Session status update** → `/linear handoff` in Phase 5 posts it, resolving the destination from the tickets the session touched. Never call `save_status_update` directly — that reintroduces the misrouting bug linear v0.7.0 fixed.
- **Project status enum** (e.g. Backlog → Active) is Posture B — it is a network write — but check the workspace's real status names first — they are workspace-specific (`In Progress` may not exist). Setting a started status may auto-stamp *today* as the start date; correct it to when work actually began.

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
# ports AND owning PIDs. `lsof -t` returns PIDs only, so it cannot answer
# "was this port already listening at session start" — which is the whole test.
lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR>1 {print $2"\t"$9}' | sort -u \
| while IFS=$'\t' read -r pid addr; do
    printf '%s  ' "$addr"; ps -o pid=,lstart=,command= -p "$pid"
  done

# untracked, non-ignored additions — the only real leftovers
git ls-files --others --exclude-standard
```

`jobs -l` is useless here — every Bash call is a fresh non-interactive shell, so it always returns empty and reads as "nothing running." Do not use it. Background tasks started through the harness stay alive until killed.

**Rules:**

- **You may only kill a PID this session's own transcript shows this session launching** — a `run_in_background` call you can point to. No such call → no kill, whatever the scan shows. The run ledger records a run's *output*, never process launches; do not treat it as kill authority. Re-verify with `ps -o pid=,lstart=,command= -p <pid>` before signalling; a recycled PID is a different process.
- Compare the port in `addr` (after the last `:`) against the baseline's `listening_ports`. A port in that list was the operator's before you started, whatever is on it now.
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

A **credential shape** is: a `sk-`, `ghp_`, `gho_`, `AKIA`, or `xox[baprs]-` prefix; a `-----BEGIN … PRIVATE KEY-----` block; `Bearer <20+ chars>`; or a long random string following `key`, `token`, `secret`, `password` or `passwd`. Refuse the commit and report — never redact and commit.

Before writing to any shared or persistent surface — Linear, GitHub, journals, handoffs, artifacts — redact: credentials and tokens in any form, dollar figures from client work, client names and identifiers, and anything the operator marked confidential. Write the shape ("a five-figure retainer"), not the value.

If the host project defines its own data-handling rules, they override this baseline. If it defines none, apply the baseline — **never skip redaction because the pointer resolved to nothing.**
