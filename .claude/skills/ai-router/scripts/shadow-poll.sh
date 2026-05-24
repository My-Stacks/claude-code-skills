#!/usr/bin/env bash
# shadow-poll.sh — single poll tick. Called every 3 min by the parent session's cron.
#
# Usage: bash shadow-poll.sh <state-dir>
#
# Outputs (first line of stdout) — see SKILL.md "Shadow Review" for cron contract:
#   BOTH_READY              — ai-router + CodeRabbit both posted
#   ONLY_AI_ROUTER_READY    — CodeRabbit was skipped; ai-router posted
#   WAITING have_ai=… have_cr=… elapsed=…s
#   TIMEOUT have_ai=… have_cr=…       (partial both.json written if anything matched)
#   FAILED:<status>                   — process died or exited without posting
#
# Side-effects:
#   BOTH_READY / ONLY_AI_ROUTER_READY / TIMEOUT (when have_ai==1) — writes
#   <state-dir>/both.json with the matched comment object(s).
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
WAIT_FOR_CR=$(cat "$STATE/wait_for_cr" 2>/dev/null || echo true)
POST=$(cat "$STATE/post" 2>/dev/null || echo false)
SHADOW_STATUS=$(cat "$STATE/shadow.status")
SHADOW_PID=$(cat "$STATE/shadow.pid" 2>/dev/null || echo "")

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)

# `gh api --paginate` emits [...][...] (one array per page); `jq -s '[.[][]]'`
# slurps and flattens. `?since=` bounds the result to items at-or-after our
# spawn time, sharply reducing GitHub-API work on PRs with long histories.
COMMENTS=$(gh api "repos/$REPO/issues/$PR/comments?since=$STARTED&per_page=100" --paginate 2>/dev/null | jq -s '[.[][]]' || echo '[]')
CR_REVIEWS=$(gh api "repos/$REPO/pulls/$PR/reviews?per_page=100" --paginate 2>/dev/null | jq -s '[.[][]]' || echo '[]')

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
CODERABBIT=$(jq --arg started "$STARTED" \
  '[.[] | select((.user.login // "")=="coderabbitai[bot]" or (.user.login // "")=="coderabbitai") | select((.created_at // "") > $started)] | last // null' <<<"$COMMENTS")
CR_REVIEW=$(jq --arg started "$STARTED" \
  '[.[] | select((.user.login // "")=="coderabbitai[bot]" or (.user.login // "")=="coderabbitai") | select((.submitted_at // "") > $started)] | last // null' <<<"$CR_REVIEWS")

HAVE_AI=0; [[ "$AIROUTER" != "null" ]] && HAVE_AI=1
HAVE_CR=0
[[ "$CODERABBIT" != "null" || "$CR_REVIEW" != "null" ]] && HAVE_CR=1
# Prefer the issue-comment shape (has body + html_url); fall back to review.
[[ "$CODERABBIT" == "null" ]] && CODERABBIT=$CR_REVIEW

write_both() {
  # $1: include CR? (true|false)
  local include_cr=$1
  if [[ "$include_cr" == "true" && "$CODERABBIT" != "null" ]]; then
    jq -n --argjson a "$AIROUTER" --argjson c "$CODERABBIT" \
      '{ai_router:{body:$a.body, url:($a.html_url // null), id:$a.id},
        coderabbit:{body:$c.body, url:($c.html_url // null), id:$c.id}}' \
      > "$STATE/both.json"
  elif [[ "$AIROUTER" != "null" ]]; then
    jq -n --argjson a "$AIROUTER" \
      '{ai_router:{body:$a.body, url:($a.html_url // null), id:$a.id}}' \
      > "$STATE/both.json"
  fi
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
  echo "FAILED:shadow-exited-without-posting"
  exit 1
fi

# 2. Terminal: both required and both present.
if [[ "$WAIT_FOR_CR" == "true" && $HAVE_AI -eq 1 && $HAVE_CR -eq 1 ]]; then
  write_both true
  echo "BOTH_READY"
  exit 0
fi

# 3. Terminal: CodeRabbit skipped, ai-router present.
if [[ "$WAIT_FOR_CR" == "false" && $HAVE_AI -eq 1 ]]; then
  write_both false
  echo "ONLY_AI_ROUTER_READY"
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
  if (( HAVE_AI == 1 )); then
    write_both "$( [[ "$WAIT_FOR_CR" == "true" && $HAVE_CR -eq 1 ]] && echo true || echo false )"
  fi
  echo "TIMEOUT have_ai=$HAVE_AI have_cr=$HAVE_CR elapsed=${ELAPSED}s"
  exit 2
fi

echo "WAITING have_ai=$HAVE_AI have_cr=$HAVE_CR elapsed=${ELAPSED}s"
exit 0
