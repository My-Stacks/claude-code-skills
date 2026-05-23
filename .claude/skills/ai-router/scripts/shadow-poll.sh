#!/usr/bin/env bash
# shadow-poll.sh — single poll tick. Called every 3 min by the parent session's cron.
#
# Usage: bash shadow-poll.sh <state-dir>
#
# Outputs (first line of stdout) — see SKILL.md "Shadow Review" for cron contract:
#   BOTH_READY              — ai-router + CodeRabbit both posted
#   ONLY_AI_ROUTER_READY    — CodeRabbit was skipped; ai-router posted
#   WAITING have_ai=… have_cr=… elapsed=…s
#   TIMEOUT have_ai=… have_cr=…
#   FAILED:<status>         — shadow process failed AND no ai-router comment posted
#
# Side-effect on terminal states (BOTH_READY / ONLY_AI_ROUTER_READY):
#   writes <state-dir>/both.json with the matched comment bodies + URLs.
#
# Exit codes:
#   0  WAITING or terminal-ready (parent reads stdout to dispatch)
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

PR=$(cat "$STATE/pr")
RUN_ID=$(cat "$STATE/run_id")
STARTED=$(cat "$STATE/started_at")
WAIT_FOR_CR=$(cat "$STATE/wait_for_cr" 2>/dev/null || echo true)
SHADOW_STATUS=$(cat "$STATE/shadow.status")

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)

# `gh api --paginate` emits [...][...] (one array per page); `jq -s '[.[][]]'`
# slurps and flattens into a single array that downstream filters iterate.
COMMENTS=$(gh api "repos/$REPO/issues/$PR/comments" --paginate | jq -s '[.[][]]')

AIROUTER=$(jq --arg rid "$RUN_ID" \
  '[.[] | select(.body | contains("run-id=" + $rid))] | last // null' <<<"$COMMENTS")

# CodeRabbit posts both via PR-issue comments AND via the pulls/reviews endpoint
# (formal reviews). Check both so we don't time out waiting for a comment that
# arrived as a review.
CR_REVIEWS=$(gh api "repos/$REPO/pulls/$PR/reviews" --paginate 2>/dev/null | jq -s '[.[][]]' || echo '[]')
CODERABBIT=$(jq --arg started "$STARTED" \
  '[.[] | select((.user.login // "")=="coderabbitai[bot]" or (.user.login // "")=="coderabbitai") | select(.created_at > $started)] | last // null' <<<"$COMMENTS")
CR_REVIEW=$(jq --arg started "$STARTED" \
  '[.[] | select((.user.login // "")=="coderabbitai[bot]" or (.user.login // "")=="coderabbitai") | select((.submitted_at // "") > $started)] | last // null' <<<"$CR_REVIEWS")

HAVE_AI=0; [[ "$AIROUTER" != "null" ]] && HAVE_AI=1
HAVE_CR=0
[[ "$CODERABBIT" != "null" || "$CR_REVIEW" != "null" ]] && HAVE_CR=1
# Prefer the issue-comment object (has body+html_url); fall back to review object.
[[ "$CODERABBIT" == "null" ]] && CODERABBIT=$CR_REVIEW

# If the shadow failed but the ai-router comment IS already on the PR (the
# headless instance posted before exiting non-zero), surface as ready rather
# than FAILED.
if [[ "$SHADOW_STATUS" == failed:* && $HAVE_AI -eq 0 ]]; then
  echo "FAILED:$SHADOW_STATUS"
  exit 1
fi

# Terminal: both required and both present.
if [[ "$WAIT_FOR_CR" == "true" && $HAVE_AI -eq 1 && $HAVE_CR -eq 1 ]]; then
  jq -n --argjson a "$AIROUTER" --argjson c "$CODERABBIT" \
    '{ai_router:{body:$a.body,url:($a.html_url // null),id:$a.id},
      coderabbit:{body:$c.body,url:($c.html_url // null),id:$c.id}}' \
    > "$STATE/both.json"
  echo "BOTH_READY"
  exit 0
fi

# Terminal: CodeRabbit skipped, ai-router present.
if [[ "$WAIT_FOR_CR" == "false" && $HAVE_AI -eq 1 ]]; then
  jq -n --argjson a "$AIROUTER" \
    '{ai_router:{body:$a.body,url:($a.html_url // null),id:$a.id}}' \
    > "$STATE/both.json"
  echo "ONLY_AI_ROUTER_READY"
  exit 0
fi

# Compute elapsed via python3 (portable ISO-8601 across BSD/GNU date).
# Fail loudly on parse error — never silently mask the timeout.
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

if (( ELAPSED > TIMEOUT_S )); then
  echo "TIMEOUT have_ai=$HAVE_AI have_cr=$HAVE_CR elapsed=${ELAPSED}s"
  exit 2
fi

echo "WAITING have_ai=$HAVE_AI have_cr=$HAVE_CR elapsed=${ELAPSED}s"
exit 0
