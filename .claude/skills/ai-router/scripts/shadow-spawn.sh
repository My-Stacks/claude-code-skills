#!/usr/bin/env bash
# shadow-spawn.sh — launch a headless `claude -p` that runs /ai-router review
# on a PR in the background. Returns the state directory on stdout.
#
# Usage: bash shadow-spawn.sh <pr-number> [--wait-for-cr true|false]
#
# Exit codes:
#   0  ok (state dir printed to stdout)
#   2  missing PR number or already-running shadow
#   3  missing dependency (claude, gh, uuidgen)

set -euo pipefail

[[ $# -ge 1 ]] || { echo "usage: shadow-spawn.sh <pr-number> [--wait-for-cr true|false]" >&2; exit 2; }
PR=$1; shift

WAIT_FOR_CR=true
while (( $# > 0 )); do
  case "$1" in
    --wait-for-cr) WAIT_FOR_CR=$2; shift 2 ;;
    *) echo "unknown flag: $1" >&2; exit 64 ;;
  esac
done

for bin in claude gh; do
  command -v "$bin" >/dev/null 2>&1 || { echo "missing dependency: $bin" >&2; exit 3; }
done

REPO_SLUG=$(gh repo view --json nameWithOwner -q .nameWithOwner | tr '/' '-')
RUN_ID=$(uuidgen 2>/dev/null | tr 'A-Z' 'a-z' || echo "run-$(date +%s)-$$")
STATE="/tmp/ai-router-shadow/${REPO_SLUG}-pr${PR}-${RUN_ID}"
mkdir -p "$STATE"

date -u +%Y-%m-%dT%H:%M:%SZ > "$STATE/started_at"
echo "$RUN_ID" > "$STATE/run_id"
echo "$PR"     > "$STATE/pr"
echo "$WAIT_FOR_CR" > "$STATE/wait_for_cr"
echo "running" > "$STATE/shadow.status"

# setsid puts the headless claude in its own process group → clean kill path.
# No --bare so the ai-router skill resolves; conversation context is naturally
# isolated because `claude -p` is a separate process with no parent IPC.
setsid bash -c "
  AI_ROUTER_RUN_ID='$RUN_ID' AI_ROUTER_PROVIDERS='anthropic,openai,gemini' \
  claude -p '/ai-router review $PR --post-to-pr $PR' \
    --output-format text \
    > '$STATE/shadow.log' 2>&1
  rc=\$?
  if [[ \$rc -eq 0 ]]; then
    echo done > '$STATE/shadow.status'
  else
    echo \"failed:exit-\$rc\" > '$STATE/shadow.status'
  fi
" &

PID=$!
echo "$PID" > "$STATE/shadow.pid"
ps -o pgid= -p "$PID" 2>/dev/null | tr -d ' ' > "$STATE/shadow.pgid" || echo "$PID" > "$STATE/shadow.pgid"

echo "$STATE"
