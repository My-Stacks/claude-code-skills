#!/usr/bin/env bash
# shadow-spawn.sh — launch a headless `claude -p` that runs /ai-router review
# on a PR in the background. Returns the state directory on stdout.
#
# Usage: bash shadow-spawn.sh <pr-number> [--wait-for-cr true|false]
#
# Security: PR number is strictly validated (digits only) before any
# interpolation, and inner commands receive PR via positional args rather
# than string interpolation. setsid is portable via python3 (already required).
#
# Exit codes:
#   0  ok (state dir printed to stdout)
#   2  invalid args or shadow already running for this PR
#   3  missing dependency (claude, gh, python3)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib/config.sh"

[[ $# -ge 1 ]] || { echo "usage: shadow-spawn.sh <pr-number> [--wait-for-cr true|false]" >&2; exit 2; }
PR=$1; shift

[[ "$PR" =~ ^[1-9][0-9]*$ ]] || { echo "invalid PR number: $PR (must be positive integer)" >&2; exit 2; }

WAIT_FOR_CR=true
while (( $# > 0 )); do
  case "$1" in
    --wait-for-cr)
      [[ $# -ge 2 ]] || { echo "--wait-for-cr requires a value (true|false)" >&2; exit 2; }
      case "$2" in
        true|false) WAIT_FOR_CR=$2 ;;
        *) echo "--wait-for-cr must be 'true' or 'false', got: $2" >&2; exit 2 ;;
      esac
      shift 2
      ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

for bin in claude gh python3; do
  command -v "$bin" >/dev/null 2>&1 || { echo "missing dependency: $bin" >&2; exit 3; }
done

REPO_SLUG=$(gh repo view --json nameWithOwner -q .nameWithOwner | tr '/' '-')
RUN_ID=$(python3 -c 'import uuid; print(uuid.uuid4())')

SHADOW_BASE="${AI_ROUTER_SHADOW_DIR:-${AI_ROUTER_TMPDIR:-${TMPDIR:-/tmp}}/ai-router-shadow}"
SHADOW_BASE=${SHADOW_BASE%/}

# Double-spawn guard: refuse if there's a live "running" shadow for this repo+PR.
shopt -s nullglob
for existing in "$SHADOW_BASE/${REPO_SLUG}-pr${PR}-"*; do
  [[ -d "$existing" ]] || continue
  pidfile="$existing/shadow.pid"
  statusfile="$existing/shadow.status"
  [[ -r "$pidfile" && -r "$statusfile" ]] || continue
  pid=$(cat "$pidfile")
  status=$(cat "$statusfile")
  if [[ "$status" == "running" && "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
    echo "shadow already running for PR $PR (PID $pid, state: $existing)" >&2
    exit 2
  fi
done
shopt -u nullglob

# Compute providers list from configured (non-empty) keys.
PROVIDERS=""
[[ -n "$(anthropic_key)" ]] && PROVIDERS+="${PROVIDERS:+,}anthropic"
[[ -n "$(openai_key)"    ]] && PROVIDERS+="${PROVIDERS:+,}openai"
[[ -n "$(gemini_key)"    ]] && PROVIDERS+="${PROVIDERS:+,}gemini"
[[ -n "$PROVIDERS" ]] || { echo "no providers configured in $(config_path)" >&2; exit 2; }

STATE="$SHADOW_BASE/${REPO_SLUG}-pr${PR}-${RUN_ID}"
mkdir -p "$STATE"

date -u +%Y-%m-%dT%H:%M:%SZ > "$STATE/started_at"
printf '%s\n' "$RUN_ID"      > "$STATE/run_id"
printf '%s\n' "$PR"          > "$STATE/pr"
printf '%s\n' "$WAIT_FOR_CR" > "$STATE/wait_for_cr"
printf '%s\n' "$PROVIDERS"   > "$STATE/providers"

# Atomic status write.
printf 'running\n' > "$STATE/shadow.status.tmp" && mv "$STATE/shadow.status.tmp" "$STATE/shadow.status"

# Detached launch via python3 setsid (portable across Linux + macOS).
# PR + RUN_ID + PROVIDERS + STATE pass as positional args, never interpolated
# into a shell command line, so a malicious PR (already validated above) cannot
# inject shell metacharacters.
python3 -c '
import os, sys, subprocess
os.setsid()
sys.exit(subprocess.run(["bash", "-c", sys.argv[1], "_"] + sys.argv[2:]).returncode)
' '
set -o pipefail
PR=$1; RUN_ID=$2; PROVIDERS=$3; STATE=$4
export AI_ROUTER_RUN_ID="$RUN_ID" AI_ROUTER_PROVIDERS="$PROVIDERS"
claude -p "/ai-router review $PR --post-to-pr $PR" --output-format text \
  > "$STATE/shadow.log" 2>&1
rc=$?
if [[ $rc -eq 0 ]]; then
  printf "done\n" > "$STATE/shadow.status.tmp"
else
  printf "failed:exit-%s\n" "$rc" > "$STATE/shadow.status.tmp"
fi
mv "$STATE/shadow.status.tmp" "$STATE/shadow.status"
' "$PR" "$RUN_ID" "$PROVIDERS" "$STATE" \
  </dev/null >/dev/null 2>&1 &

PID=$!
printf '%s\n' "$PID" > "$STATE/shadow.pid"
ps -o pgid= -p "$PID" 2>/dev/null | tr -d ' ' > "$STATE/shadow.pgid" || printf '%s\n' "$PID" > "$STATE/shadow.pgid"

printf '%s\n' "$STATE"
