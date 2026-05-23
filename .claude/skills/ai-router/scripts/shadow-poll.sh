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
#   FAILED:<status>         — shadow process failed
#
# Side-effect on terminal states (BOTH_READY / ONLY_AI_ROUTER_READY):
#   writes <state-dir>/both.json with the matched comment bodies + URLs.
#
# Exit codes:
#   0  WAITING or terminal-ready (parent reads stdout to dispatch)
#   1  FAILED
#   2  TIMEOUT
#   3  missing dependency
#  64  usage / state-dir missing

set -euo pipefail

[[ $# -eq 1 ]] || { echo "usage: shadow-poll.sh <state-dir>" >&2; exit 64; }
STATE=$1
[[ -d "$STATE" ]] || { echo "state-dir missing: $STATE" >&2; exit 64; }

for bin in gh jq; do
  command -v "$bin" >/dev/null 2>&1 || { echo "missing dependency: $bin" >&2; exit 3; }
done

PR=$(cat "$STATE/pr")
RUN_ID=$(cat "$STATE/run_id")
STARTED=$(cat "$STATE/started_at")
WAIT_FOR_CR=$(cat "$STATE/wait_for_cr" 2>/dev/null || echo true)

SHADOW_STATUS=$(cat "$STATE/shadow.status")
if [[ "$SHADOW_STATUS" == failed:* ]]; then
  echo "FAILED:$SHADOW_STATUS"
  exit 1
fi

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
COMMENTS=$(gh api "repos/$REPO/issues/$PR/comments" --paginate)

AIROUTER=$(jq --arg rid "$RUN_ID" \
  '[.[] | select(.body | contains("run-id=" + $rid))] | last // null' <<<"$COMMENTS")

CODERABBIT=$(jq --arg started "$STARTED" \
  '[.[] | select(.user.login=="coderabbitai[bot]") | select(.created_at > $started)] | last // null' <<<"$COMMENTS")

HAVE_AI=0; [[ "$AIROUTER"   != "null" ]] && HAVE_AI=1
HAVE_CR=0; [[ "$CODERABBIT" != "null" ]] && HAVE_CR=1

# Terminal: both required and both present
if [[ "$WAIT_FOR_CR" == "true" && $HAVE_AI -eq 1 && $HAVE_CR -eq 1 ]]; then
  jq -n --argjson a "$AIROUTER" --argjson c "$CODERABBIT" \
    '{ai_router:{body:$a.body,url:$a.html_url,id:$a.id},
      coderabbit:{body:$c.body,url:$c.html_url,id:$c.id}}' \
    > "$STATE/both.json"
  echo "BOTH_READY"
  exit 0
fi

# Terminal: CodeRabbit skipped, ai-router present
if [[ "$WAIT_FOR_CR" == "false" && $HAVE_AI -eq 1 ]]; then
  jq -n --argjson a "$AIROUTER" \
    '{ai_router:{body:$a.body,url:$a.html_url,id:$a.id}}' \
    > "$STATE/both.json"
  echo "ONLY_AI_ROUTER_READY"
  exit 0
fi

# Compute elapsed seconds (macOS gdate / Linux date fallback).
NOW=$(date -u +%s)
if command -v gdate >/dev/null 2>&1; then
  START_S=$(gdate -d "$STARTED" +%s)
elif date -d "$STARTED" +%s >/dev/null 2>&1; then
  START_S=$(date -d "$STARTED" +%s)
else
  # BSD date with ISO-8601 input
  START_S=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$STARTED" +%s 2>/dev/null || echo "$NOW")
fi
ELAPSED=$(( NOW - START_S ))

# Timeout (default 30 min).
TIMEOUT_S=${AI_ROUTER_SHADOW_TIMEOUT:-1800}
if (( ELAPSED > TIMEOUT_S )); then
  echo "TIMEOUT have_ai=$HAVE_AI have_cr=$HAVE_CR elapsed=${ELAPSED}s"
  exit 2
fi

echo "WAITING have_ai=$HAVE_AI have_cr=$HAVE_CR elapsed=${ELAPSED}s"
exit 0
