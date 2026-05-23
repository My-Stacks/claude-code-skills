#!/usr/bin/env bash
# shadow-runner.sh — body of the detached shadow process.
#
# Called only by shadow-spawn.sh via:
#   python3 -c 'os.setsid(); subprocess.run(["bash", "<this>", PR, RUN_ID, PROVIDERS, STATE])'
#
# Runs inside the new session created by python3's os.setsid(), so $$ equals the
# session/process-group leader. Writing $$ -> $STATE/shadow.pgid here (rather
# than from the parent) is race-free: the file appears only after setsid() has
# already taken effect.

set -euo pipefail

[[ $# -eq 4 ]] || { echo "shadow-runner.sh: bad argc ($#)" >&2; exit 64; }
PR=$1; RUN_ID=$2; PROVIDERS=$3; STATE=$4

# Atomic pgid write. Equals the new session leader (this bash process).
PGID=$(ps -o pgid= -p $$ | tr -d ' ')
printf '%s\n' "$PGID" > "$STATE/shadow.pgid.tmp" && mv "$STATE/shadow.pgid.tmp" "$STATE/shadow.pgid"

export AI_ROUTER_RUN_ID="$RUN_ID" AI_ROUTER_PROVIDERS="$PROVIDERS"

# Headless claude. PR is interpolated into the prompt string, but shadow-spawn.sh
# strictly validated it (^[1-9][0-9]*$) before spawn, so this can't inject.
#
# `set +e` around the call so a non-zero exit doesn't trip set -e and abort
# before the status file is written — the poller relies on the status file
# transitioning out of "running".
set +e
claude -p "/ai-router review $PR --post-to-pr $PR" --output-format text \
  > "$STATE/shadow.log" 2>&1
rc=$?
set -e

if (( rc == 0 )); then
  printf 'done\n' > "$STATE/shadow.status.tmp"
else
  printf 'failed:exit-%s\n' "$rc" > "$STATE/shadow.status.tmp"
fi
mv "$STATE/shadow.status.tmp" "$STATE/shadow.status"
exit "$rc"
