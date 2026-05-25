#!/usr/bin/env bash
# shadow-spawn.sh — launch a headless `claude -p` that runs /ai-router review
# on a PR in the background. Returns the state directory on stdout.
#
# Usage: bash shadow-spawn.sh <pr-number> [--wait-for-cr true|false] [--post]
#
# Security:
# - PR number is strictly validated (^[1-9][0-9]*$) before any interpolation.
# - Inner commands receive PR as a positional arg, not interpolated.
# - State dir is created mode 700 to keep shadow.log private.
# - API keys never appear in argv (curl --config file; see lib/http.sh).
#
# Concurrency:
# - The state dir IS the lock: a single atomic `mkdir -m 700` per repo+PR.
#   A second spawn for the same PR fails immediately; a stale dir (whose owning
#   PID is gone and whose status isn't "running") is archived aside and retried
#   once.
#
# Exit codes:
#   0  ok (state dir printed to stdout)
#   2  invalid args or shadow already running for this PR
#   3  missing dependency (claude, gh, python3)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib/config.sh"

[[ $# -ge 1 ]] || { echo "usage: shadow-spawn.sh <pr-number> [--wait-cr] [--wait-reviewers] [--post]" >&2; exit 2; }
PR=$1; shift

[[ "$PR" =~ ^[1-9][0-9]*$ ]] || { echo "invalid PR number: $PR (must be positive integer)" >&2; exit 2; }

# Opt-out by default. Each --wait-* flag adds an AND clause to the terminal-ready
# condition. With no flags, the run resolves to ONLY_AI_ROUTER_READY as soon as
# the headless review finishes.
WAIT_CR=false
WAIT_REVIEWERS=false
POST=false   # default: synthesis goes to shadow.log, NOT to a PR comment
while (( $# > 0 )); do
  case "$1" in
    --wait-cr)        WAIT_CR=true;        shift ;;
    --wait-reviewers) WAIT_REVIEWERS=true; shift ;;
    --post)           POST=true;           shift ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

for bin in claude gh python3; do
  command -v "$bin" >/dev/null 2>&1 || { echo "missing dependency: $bin" >&2; exit 3; }
done

REPO_FULL=$(gh repo view --json nameWithOwner -q .nameWithOwner)
REPO_SLUG=${REPO_FULL//\//-}
RUN_ID=$(python3 -c 'import uuid; print(uuid.uuid4())')

SHADOW_BASE="${AI_ROUTER_SHADOW_DIR:-${AI_ROUTER_TMPDIR:-${TMPDIR:-/tmp}}/ai-router-shadow}"
SHADOW_BASE=${SHADOW_BASE%/}
mkdir -p "$SHADOW_BASE"

STATE="$SHADOW_BASE/${REPO_SLUG}-pr${PR}"

# Atomic claim — `mkdir` fails iff the dir already exists. No TOCTOU.
if ! mkdir -m 700 "$STATE" 2>/dev/null; then
  pid=$(cat "$STATE/shadow.pid" 2>/dev/null || true)
  status=$(cat "$STATE/shadow.status" 2>/dev/null || echo "?")
  if [[ "$status" == "running" && "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
    echo "shadow already running for PR $PR (PID $pid, state: $STATE)" >&2
    exit 2
  fi
  # Stale state — archive aside (preserve logs for forensics) and re-mkdir.
  mv "$STATE" "${STATE}.stale.$(date -u +%Y%m%dT%H%M%SZ)" 2>/dev/null || true
  mkdir -m 700 "$STATE" || { echo "shadow lock conflict for PR $PR" >&2; exit 2; }
fi

# Compute providers from configured (non-empty) keys.
PROVIDERS=""
[[ -n "$(anthropic_key)" ]] && PROVIDERS+="${PROVIDERS:+,}anthropic"
[[ -n "$(openai_key)"    ]] && PROVIDERS+="${PROVIDERS:+,}openai"
[[ -n "$(gemini_key)"    ]] && PROVIDERS+="${PROVIDERS:+,}gemini"
if [[ -z "$PROVIDERS" ]]; then
  echo "no providers configured in $(config_path)" >&2
  rmdir "$STATE" 2>/dev/null || true
  exit 2
fi

PR_AUTHOR=$(gh api "repos/$REPO_FULL/pulls/$PR" --jq '.user.login' 2>/dev/null || echo "")

date -u +%Y-%m-%dT%H:%M:%SZ    > "$STATE/started_at"
printf '%s\n' "$RUN_ID"         > "$STATE/run_id"
printf '%s\n' "$PR"             > "$STATE/pr"
printf '%s\n' "$WAIT_CR"        > "$STATE/wait_cr"
printf '%s\n' "$WAIT_REVIEWERS" > "$STATE/wait_reviewers"
printf '%s\n' "$POST"           > "$STATE/post"
printf '%s\n' "$PROVIDERS"      > "$STATE/providers"
printf '%s\n' "$REPO_FULL"      > "$STATE/repo"
printf '%s\n' "$PR_AUTHOR"      > "$STATE/pr_author"
# Atomic status write.
printf 'running\n' > "$STATE/shadow.status.tmp" && mv "$STATE/shadow.status.tmp" "$STATE/shadow.status"

# Detached launch. python3 -c is the portable equivalent of `setsid` (which is
# not present on macOS by default). os.setsid() runs in the python wrapper;
# the inner bash inherits the new session/pgid, then shadow-runner.sh writes
# its own $$ to shadow.pgid (race-free — file appears only after the new
# session is in place).
python3 -c '
import os, sys, subprocess
os.setsid()
sys.exit(subprocess.run(["bash", *sys.argv[1:]]).returncode)
' "$SCRIPT_DIR/lib/shadow-runner.sh" "$PR" "$RUN_ID" "$PROVIDERS" "$POST" "$STATE" \
  </dev/null >/dev/null 2>&1 &

PID=$!
printf '%s\n' "$PID" > "$STATE/shadow.pid"

# Wait briefly for shadow-runner.sh to write the pgid. Don't sleep forever —
# if the child crashed instantly, the parent should still return.
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [[ -s "$STATE/shadow.pgid" ]] && break
  sleep 0.2
done

printf '%s\n' "$STATE"
