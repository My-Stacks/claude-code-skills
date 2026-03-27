---
name: pr-watch
version: "1.0"
description: "Monitor a GitHub PR and notify on reviews, comments, check changes, merge, or closure."
trigger: /pr-watch
---

## Version Check
To check for updates: `curl -s https://raw.githubusercontent.com/My-Stacks/claude-code-skills/main/versions.yaml`
Compare against this file's version in frontmatter.

# PR Watch

Monitor open pull requests for activity via CronCreate polling. Notifies when something changes, stays silent when nothing has.

## Prerequisites

Before starting, verify:

```bash
command -v gh >/dev/null 2>&1 || { echo "gh CLI not installed"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "gh not authenticated — run: gh auth login"; exit 1; }
```

Also confirm the current directory is a git repo with a GitHub remote (unless user provided a full PR URL).

## When to Use

- Right after pushing a branch or opening a PR
- When waiting on a review from a teammate
- User says "watch", "monitor", "babysit", "notify me", or "keep an eye on" in relation to a PR
- User provides a PR number or URL and wants updates

## How It Works

### Step 1: Identify the PR

Try in order:

1. **User provided a PR number or URL** — extract the number (e.g., `#12`, `pull/12`, or just `12`). If full URL, parse `owner/repo` from it.
2. **Current branch has an open PR** — run:
   ```bash
   gh pr view --json number,title,state,url,author,headRefName 2>/dev/null
   ```
3. **No PR found** — tell the user and ask for a PR number.

Get `{owner}/{repo}` for API calls:
```bash
gh repo view --json nameWithOwner --jq .nameWithOwner
```

**Input validation** — before proceeding, verify:
- `{N}` matches `^\d+$`
- `{owner}` and `{repo}` each match `^[a-zA-Z0-9._-]+$`

If validation fails, stop and tell the user the input looks malformed.

**Guard against already-closed PRs** — check that the PR state is `OPEN`. If it's already `MERGED` or `CLOSED`, tell the user and don't start the watch.

Confirm: "Watching PR #{N}: {title} — I'll check every 30 minutes and notify you of any activity."

### Step 2: Capture Baseline and Create State File

Run a single command to capture current state:

```bash
gh pr view {N} --json number,state,reviews,comments,statusCheckRollup,mergedAt,closedAt,headRefOid,isDraft \
  --jq '{
    number: .number,
    state: .state,
    isDraft: .isDraft,
    headRefOid: .headRefOid,
    mergedAt: .mergedAt,
    closedAt: .closedAt,
    comment_ids: [.comments[].id],
    comments: [.comments[] | {id, author: .author.login, body: (.body[:150])}],
    reviews: [.reviews[] | {id, author: .author.login, state: .state, body: (.body[:150])}],
    checks: [(.statusCheckRollup // [])[] | {name: (.name // .context // "unknown"), status: .status, conclusion: .conclusion}]
  }'
```

Write the result to a state file, adding metadata:

```bash
mkdir -p /tmp/pr-watch && chmod 700 /tmp/pr-watch
```

```bash
python3 << 'PYEOF'
import json, sys, os
from datetime import datetime, timezone
state = json.load(sys.stdin)
state['started_at'] = datetime.now(timezone.utc).isoformat()
state['last_polled_at'] = state['started_at']
state['consecutive_failures'] = 0
state['cron_job_id'] = None  # filled in after CronCreate
owner = os.environ['PR_OWNER']
repo = os.environ['PR_REPO']
num = os.environ['PR_NUM']
json.dump(state, open(f'/tmp/pr-watch/{owner}-{repo}-pr-{num}.json', 'w'), indent=2)
PYEOF
```

Pass `{owner}`, `{repo}`, `{N}` as environment variables `PR_OWNER`, `PR_REPO`, `PR_NUM` to avoid shell interpolation in the python block. Pipe the `gh pr view` output into stdin.

### Step 3: Schedule the Polling Loop

Use CronCreate with:
- **cron:** `*/30 * * * *`
- **recurring:** true
- **prompt:** The polling prompt below (substitute `{owner}`, `{repo}`, `{N}` tokens only — the prompt reads `cron_job_id` from the state file at runtime)

After CronCreate returns the job ID, write it to the state file:

```bash
PR_OWNER="{owner}" PR_REPO="{repo}" PR_NUM="{N}" python3 << 'PYEOF'
import json, os
f = f'/tmp/pr-watch/{os.environ["PR_OWNER"]}-{os.environ["PR_REPO"]}-pr-{os.environ["PR_NUM"]}.json'
state = json.load(open(f))
state['cron_job_id'] = os.environ.get('JOB_ID', '')
json.dump(state, open(f, 'w'), indent=2)
PYEOF
```

Set `JOB_ID` to the value returned by CronCreate.

Tell the user:
- Job ID (for manual cancel via CronDelete)
- Polling interval: every 30 minutes
- Auto-expires after 2 hours
- Auto-cancels on merge/close
- Ends when session ends (CronCreate jobs are session-scoped)

### Polling Prompt Template

Construct this prompt, substituting `{owner}`, `{repo}`, and `{N}` only. The prompt reads `cron_job_id` from the state file — do NOT hardcode the job ID.

```
Read the state file at /tmp/pr-watch/{owner}-{repo}-pr-{N}.json.
If the file is missing, output "State file missing — watch for PR #{N} aborted." and stop.
Read the cron_job_id from the state file for use in any CronDelete calls.
If cron_job_id is null, output "Job ID not yet written — skipping this poll." and stop.

Fetch current PR state:
gh pr view {N} --json number,state,reviews,comments,statusCheckRollup,mergedAt,closedAt,headRefOid,isDraft \
  --jq '{number: .number, state: .state, isDraft: .isDraft, headRefOid: .headRefOid, mergedAt: .mergedAt, closedAt: .closedAt, comment_ids: [.comments[].id], comments: [.comments[] | {id, author: .author.login, body: (.body[:150])}], reviews: [.reviews[] | {id, author: .author.login, state: .state, body: (.body[:150])}], checks: [(.statusCheckRollup // [])[] | {name: (.name // .context // "unknown"), status: .status, conclusion: .conclusion}]}'

Compare the fetched state against the saved state file. Check for these changes:

1. PR merged or closed → notify "PR #{N} was {merged/closed}. Watch ended." then call CronDelete with the job ID from the state file, and delete the state file.
2. New commits pushed (headRefOid changed) → notify with new SHA.
3. Draft status changed (isDraft flipped) → notify "PR #{N} marked ready for review" or "converted to draft."
4. New reviews (review IDs not in saved state) → show reviewer, state (APPROVED/CHANGES_REQUESTED/COMMENTED/DISMISSED), and body excerpt from the fetched data. Highlight approvals and change requests.
5. New comments (compare comment_ids arrays via set difference, not count) → show author and body excerpt for each new comment ID.
6. Status checks changed (any check name changed status/conclusion) → show which checks passed/failed/pending. Highlight failures.
7. Timeout: compare current UTC time against started_at. If >= 7200 seconds elapsed, notify "PR #{N} watch timed out after 2 hours. Run /pr-watch again to restart." then call CronDelete with the job ID and delete the state file.

If NOTHING changed, produce zero output — no text at all.

If the gh command fails, increment consecutive_failures in the state file. If consecutive_failures >= 3, notify "PR #{N} watch degraded — 3 consecutive poll failures. Stopping." then call CronDelete with the job ID from the state file and delete the state file.

After comparing, overwrite the state file with the new state (preserve started_at, cron_job_id, reset consecutive_failures to 0 on success).
```

### Step 4: Run First Check Immediately

After creating the cron job and writing the job ID to state, run the polling check once immediately. This validates the watch is working. Since the baseline was just captured, this first poll will almost always report no changes — that's expected. It confirms the `gh` commands succeed and the state file round-trips correctly.

## Cancellation

The watch ends when any of these happen:
- PR merged or closed (auto-detected during poll)
- 2-hour timeout (auto-detected during poll)
- 3 consecutive poll failures (auto-detected)
- User says "stop watching" or "cancel the PR watch"
- User runs CronDelete with the job ID
- Session ends (CronCreate jobs are session-scoped)

When the user asks to stop: read the state file to get the job ID, call CronDelete, then delete the state file.

## Error Handling

- **gh command fails during poll:** Don't overwrite state. Increment `consecutive_failures`. After 3 consecutive failures, auto-cancel via CronDelete and clean up state file.
- **State file missing/corrupt:** Abort the watch, notify user, and call CronDelete if job ID is known.
- **gh auth expired mid-watch:** Will surface as consecutive failures, triggering auto-cancel with a message the user can act on.

## Multiple PRs

Set up independent cron jobs for each PR. Each gets its own state file (`/tmp/pr-watch/{owner}-{repo}-pr-{N}.json`), job ID, and 2-hour timeout. The `{owner}-{repo}` prefix prevents collisions when watching same PR numbers across different repos.

## Output Format

Keep notifications scannable:

```
PR #12 update:
  Review: @reviewer APPROVED "Looks good, just one nit on the template"
  Comment: @reviewer — "Can we add a note about..."
  Checks: 2/3 passed, 1 failed (lint)
  New commits: abc1234
```

For silent polls (no changes), produce zero output.
