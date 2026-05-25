#!/usr/bin/env bash
# shadow-poll.sh — single poll tick. Called every 3 min by the parent session's cron.
#
# Usage: bash shadow-poll.sh <state-dir>
#
# Outputs (first line of stdout) — see SKILL.md "Shadow Review" for cron contract:
#   ALL_READY               — every requested source has landed (ai-router + any waits)
#   ONLY_AI_ROUTER_READY    — no --wait-* flags requested; ai-router done
#   WAITING have_ai=… have_cr=… have_reviewers=… elapsed=…s
#   TIMEOUT have_ai=… have_cr=… have_reviewers=…   (partial both.json written if have_ai==1)
#   FAILED:<status>                                — process died or exited without posting
#
# Side-effects:
#   ALL_READY / ONLY_AI_ROUTER_READY / TIMEOUT (when have_ai==1) — writes
#   <state-dir>/both.json with the matched comment object(s); reviewers (if any)
#   land in a `reviewers` array alongside `ai_router` and `coderabbit`.
#
# Exit codes:
#   0  WAITING or terminal-ready
#   1  FAILED
#   2  TIMEOUT
#   3  missing dependency
#  64  usage / state-dir missing / unparseable started_at

set -euo pipefail

[[ $# -eq 1 ]] || { echo "usage: shadow-poll.sh <state-dir>" >&2; exit 64; }
STATE=$1
[[ -d "$STATE" ]] || { echo "state-dir missing: $STATE" >&2; exit 64; }

for bin in gh jq python3; do
  command -v "$bin" >/dev/null 2>&1 || { echo "missing dependency: $bin" >&2; exit 3; }
done

# Require the core state files. Under `set -euo pipefail` a missing file would
# silently abort the poll without ever emitting the documented first-line
# status — the cron would die without surfacing anything.
for required in pr run_id started_at shadow.status; do
  if [[ ! -r "$STATE/$required" ]]; then
    echo "FAILED:missing-state-$required"
    exit 1
  fi
done

PR=$(cat "$STATE/pr")
RUN_ID=$(cat "$STATE/run_id")
STARTED=$(cat "$STATE/started_at")
# wait_cr / wait_reviewers: new opt-out shape. wait_for_cr: legacy shape from
# older state dirs (kept readable for in-flight runs across the upgrade).
if [[ -r "$STATE/wait_cr" ]]; then
  WAIT_CR=$(cat "$STATE/wait_cr")
else
  WAIT_CR=$(cat "$STATE/wait_for_cr" 2>/dev/null || echo false)
fi
WAIT_REVIEWERS=$(cat "$STATE/wait_reviewers" 2>/dev/null || echo false)
PR_AUTHOR=$(cat "$STATE/pr_author" 2>/dev/null || echo "")
POST=$(cat "$STATE/post" 2>/dev/null || echo false)
SHADOW_STATUS=$(cat "$STATE/shadow.status")
SHADOW_PID=$(cat "$STATE/shadow.pid" 2>/dev/null || echo "")

# Read repo from state (persisted by shadow-spawn.sh) so cron ticks don't
# depend on cwd being a git checkout. Fall back to `gh repo view` for state
# dirs written by older spawns that didn't persist it.
if [[ -r "$STATE/repo" ]]; then
  REPO=$(cat "$STATE/repo")
else
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
fi
# Defense-in-depth against a malformed $STATE/repo silently breaking the API
# URL — `gh api repos/<repo>/...` would 404 or worse with garbage.
[[ "$REPO" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || { echo "invalid repo in state: $REPO" >&2; exit 64; }

# `gh api --paginate` emits [...][...] (one array per page); `jq -s '[.[][]]'`
# slurps and flattens. `?since=` bounds the result to items at-or-after our
# spawn time, sharply reducing GitHub-API work on PRs with long histories.
#
# Capture rc separately so rate limits / auth errors / network blips surface
# as FAILED:gh-api-error instead of silently collapsing into "no comments"
# (which would later drift the run to FAILED:shadow-exited-without-posting).
fetch_json() {
  # $1 endpoint, $2 dest var, $3 stderr-file
  local endpoint=$1 var=$2 err=$3 raw rc
  raw=$(gh api "$endpoint" --paginate 2>"$err"); rc=$?
  if (( rc != 0 )); then return $rc; fi
  printf -v "$var" '%s' "$(jq -s '[.[][]]' <<<"$raw" 2>>"$err" || echo '[]')"
}
POLL_ERR="$STATE/poll.err"
if ! fetch_json "repos/$REPO/issues/$PR/comments?since=$STARTED&per_page=100" COMMENTS "$POLL_ERR"; then
  echo "FAILED:gh-api-error (issues/comments — see $POLL_ERR)"
  exit 1
fi
if ! fetch_json "repos/$REPO/pulls/$PR/reviews?per_page=100" CR_REVIEWS "$POLL_ERR"; then
  echo "FAILED:gh-api-error (pulls/reviews — see $POLL_ERR)"
  exit 1
fi

# AI-router signal source depends on --post:
#   POST=true:  the headless instance posted to the PR; we match by run-id marker.
#   POST=false: synthesis lives in $STATE/shadow.log; readiness is shadow.status=="done".
if [[ "$POST" == "true" ]]; then
  AIROUTER=$(jq --arg rid "$RUN_ID" \
    '[.[] | select(.body | contains("run-id=" + $rid))] | last // null' <<<"$COMMENTS")
else
  if [[ "$SHADOW_STATUS" == "done" && -s "$STATE/shadow.log" ]]; then
    AIROUTER=$(jq -n --rawfile body "$STATE/shadow.log" \
      '{body:$body, html_url:null, id:null, source:"shadow.log"}')
  else
    AIROUTER="null"
  fi
fi

# CodeRabbit posts via issue-comments AND pulls/reviews endpoints; check both.
# Match case-insensitively on substring "coderabbit" so self-hosted variants,
# legacy slugs (coderabbitai, coderabbitai[bot]), and rebrands all resolve to
# the same bucket without per-deployment config.
CODERABBIT=$(jq --arg started "$STARTED" \
  '[.[] | select((.user.login // "") | test("coderabbit"; "i")) | select((.created_at // "") > $started)] | last // null' <<<"$COMMENTS")
CR_REVIEW=$(jq --arg started "$STARTED" \
  '[.[] | select((.user.login // "") | test("coderabbit"; "i")) | select((.submitted_at // "") > $started)] | last // null' <<<"$CR_REVIEWS")

# "Other reviewers" = any issue-comment or pulls/review since spawn that is NOT
# from the PR author and NOT from CodeRabbit (CR has its own bucket above).
# Self-posts from the shadow itself are excluded via the ai-router signature
# marker so --post=true runs don't think the shadow is its own "reviewer".
REVIEWERS=$(jq --arg started "$STARTED" --arg author "$PR_AUTHOR" --arg rid "$RUN_ID" '
  [ .[]
    | select((.user.login // "") != $author)
    | select((.user.login // "") | test("coderabbit"; "i") | not)
    | select((.created_at // "") > $started)
    | select((.body // "") | contains("run-id=" + $rid) | not)
  ]' <<<"$COMMENTS")
REVIEWER_REVIEWS=$(jq --arg started "$STARTED" --arg author "$PR_AUTHOR" '
  [ .[]
    | select((.user.login // "") != $author)
    | select((.user.login // "") | test("coderabbit"; "i") | not)
    | select((.submitted_at // "") > $started)
  ]' <<<"$CR_REVIEWS")
# Merge issue-comment and formal-review hits into one reviewers array.
REVIEWERS=$(jq -n --argjson c "$REVIEWERS" --argjson r "$REVIEWER_REVIEWS" '$c + $r')

HAVE_AI=0; [[ "$AIROUTER" != "null" ]] && HAVE_AI=1
HAVE_CR=0
[[ "$CODERABBIT" != "null" || "$CR_REVIEW" != "null" ]] && HAVE_CR=1
HAVE_REVIEWERS=0
[[ "$(jq 'length' <<<"$REVIEWERS")" != "0" ]] && HAVE_REVIEWERS=1
# Prefer the issue-comment shape (has body + html_url); fall back to review.
[[ "$CODERABBIT" == "null" ]] && CODERABBIT=$CR_REVIEW

write_both() {
  # Always called when AIROUTER is present. Includes CR / reviewers iff their
  # respective wait flag is set AND the data exists. Partial writes (timeout
  # path) just pass whatever subset has landed.
  [[ "$AIROUTER" == "null" ]] && return 0
  local cr_arg=$CODERABBIT rev_arg=$REVIEWERS
  [[ "$WAIT_CR" == "false" || $HAVE_CR -eq 0 ]] && cr_arg=null
  [[ "$WAIT_REVIEWERS" == "false" ]] && rev_arg='[]'
  jq -n \
    --argjson a "$AIROUTER" \
    --argjson c "$cr_arg" \
    --argjson rs "$rev_arg" \
    '{ai_router:{body:$a.body, url:($a.html_url // null), id:$a.id}}
     + (if $c == null then {} else
         {coderabbit:{body:$c.body, url:($c.html_url // null), id:$c.id}}
       end)
     + (if ($rs | length) == 0 then {} else
         {reviewers:[$rs[] | {user:.user.login, body:.body,
                              url:(.html_url // null), id:.id,
                              at:(.submitted_at // .created_at // null)}]}
       end)' > "$STATE/both.json"
}

# 1. Shadow process died WITHOUT posting an ai-router comment → FAILED.
#    PID liveness is a best-effort fallback for the case where the headless
#    instance was hard-killed without writing status. PID reuse is possible
#    on long-running hosts, so we trust shadow.status first (which is now
#    written reliably even on non-zero exit — see lib/shadow-runner.sh) and
#    only use kill -0 as a secondary signal.
process_alive=true
if [[ -n "$SHADOW_PID" && "$SHADOW_PID" =~ ^[0-9]+$ ]]; then
  kill -0 "$SHADOW_PID" 2>/dev/null || process_alive=false
fi

if [[ "$SHADOW_STATUS" == failed:* && $HAVE_AI -eq 0 ]]; then
  echo "FAILED:$SHADOW_STATUS"
  exit 1
fi
if [[ "$SHADOW_STATUS" == "running" && "$process_alive" == "false" && $HAVE_AI -eq 0 ]]; then
  echo "FAILED:process-exited-without-status"
  exit 1
fi
if [[ "$SHADOW_STATUS" == "done" && $HAVE_AI -eq 0 ]]; then
  # In POST=true mode, ai-router presence is detected via a PR comment with the
  # run-id marker. GitHub's REST API can lag the actual write by a few seconds
  # on a fresh comment, so a single tick of "done + no comment" is normal —
  # only the second consecutive observation past the grace window is a real
  # failure. The grace marker is the first-seen timestamp; default 90s.
  if [[ "$POST" == "true" ]]; then
    GRACE_S=${AI_ROUTER_POST_GRACE:-90}
    NOW_S=$(date -u +%s)
    if [[ -r "$STATE/done_seen_at" ]]; then
      DONE_AT=$(cat "$STATE/done_seen_at")
      if (( NOW_S - DONE_AT < GRACE_S )); then
        echo "WAITING have_ai=0 have_cr=$HAVE_CR have_reviewers=$HAVE_REVIEWERS post-grace=$((NOW_S - DONE_AT))s"
        exit 0
      fi
    else
      printf '%s\n' "$NOW_S" > "$STATE/done_seen_at"
      echo "WAITING have_ai=0 have_cr=$HAVE_CR have_reviewers=$HAVE_REVIEWERS post-grace=new"
      exit 0
    fi
  fi
  echo "FAILED:shadow-exited-without-posting"
  exit 1
fi

# 2. Terminal-ready check (AND semantics): ai-router AND every requested wait.
READY=0
if (( HAVE_AI == 1 )); then
  READY=1
  [[ "$WAIT_CR" == "true" && $HAVE_CR -eq 0 ]] && READY=0
  [[ "$WAIT_REVIEWERS" == "true" && $HAVE_REVIEWERS -eq 0 ]] && READY=0
fi

if (( READY == 1 )); then
  write_both
  if [[ "$WAIT_CR" == "false" && "$WAIT_REVIEWERS" == "false" ]]; then
    echo "ONLY_AI_ROUTER_READY"
  else
    echo "ALL_READY"
  fi
  exit 0
fi

# 4. Compute elapsed via python3 (portable ISO-8601 across BSD/GNU date).
#    Fail loudly on parse error — never silently mask the timeout.
START_S=$(python3 -c '
import sys, datetime
s = sys.argv[1].rstrip("Z")
try:
    dt = datetime.datetime.fromisoformat(s).replace(tzinfo=datetime.timezone.utc)
    print(int(dt.timestamp()))
except Exception as e:
    print(f"parse-error: {e}", file=sys.stderr)
    sys.exit(1)
' "$STARTED") || { echo "could not parse started_at: $STARTED" >&2; exit 64; }

NOW=$(date -u +%s)
ELAPSED=$(( NOW - START_S ))
TIMEOUT_S=${AI_ROUTER_SHADOW_TIMEOUT:-1800}

# 5. Timeout. Write partial both.json so the parent can surface whatever did land.
#    `>=` so the documented 30-min wall is honored on the tick that crosses it,
#    not the one after (3-min overshoot).
if (( ELAPSED >= TIMEOUT_S )); then
  (( HAVE_AI == 1 )) && write_both
  echo "TIMEOUT have_ai=$HAVE_AI have_cr=$HAVE_CR have_reviewers=$HAVE_REVIEWERS elapsed=${ELAPSED}s"
  exit 2
fi

echo "WAITING have_ai=$HAVE_AI have_cr=$HAVE_CR have_reviewers=$HAVE_REVIEWERS elapsed=${ELAPSED}s"
exit 0
