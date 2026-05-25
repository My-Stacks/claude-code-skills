#!/usr/bin/env bash
# shadow-runner.sh — body of the detached shadow process.
#
# Called only by shadow-spawn.sh via:
#   python3 -c 'os.setsid(); subprocess.run(["bash", "<this>", PR, RUN_ID, PROVIDERS, POST, STATE])'
#
# Runs inside the new session created by python3's os.setsid(), so $$ equals the
# session/process-group leader. Writing $$ -> $STATE/shadow.pgid here (rather
# than from the parent) is race-free: the file appears only after setsid() has
# already taken effect.

set -euo pipefail

[[ $# -eq 5 ]] || { echo "shadow-runner.sh: bad argc ($#) — expected 5" >&2; exit 64; }
PR=$1; RUN_ID=$2; PROVIDERS=$3; POST=$4; STATE=$5

# Atomic pgid write. Equals the new session leader (this bash process).
PGID=$(ps -o pgid= -p $$ | tr -d ' ')
printf '%s\n' "$PGID" > "$STATE/shadow.pgid.tmp" && mv "$STATE/shadow.pgid.tmp" "$STATE/shadow.pgid"

# Build the claude -p prompt. PR is interpolated into the string, but
# shadow-spawn.sh strictly validated it (^[1-9][0-9]*$) so injection is blocked.
if [[ "$POST" == "true" ]]; then
  PROMPT="/ai-router review $PR --post-to-pr $PR"
else
  PROMPT="/ai-router review $PR"
fi

# Isolation: scrub inherited env. The shadow scrubs API keys, Anthropic
# console creds, and anything else the parent happened to export. Keep ONLY
# what claude / gh / config-file reads need:
#   HOME      — claude looks up ~/.claude/, gh looks up ~/.config/gh/
#   PATH      — needed to find `claude`, `gh`, `bash`, `python3`, `jq`, `curl`
#   TMPDIR    — temp files (provider body/resp, post-review comment)
#   TERM      — claude -p uses "dumb" for non-interactive output formatting
#   USER      — some gh git operations want a user
#   LANG/LC_* — keep UTF-8 happy (LC_ALL passed through only if non-empty;
#               an empty LC_ALL confuses some glibc setlocale() builds)
#   AI_ROUTER_RUN_ID, AI_ROUTER_PROVIDERS — explicit per-run inputs
#   AI_ROUTER_{CONFIG,TMPDIR,POST_BODY_DIR,SHADOW_TIMEOUT,SHADOW_RUNTIME,POST_GRACE}
#     — documented overrides, passed through only when set so the shadow
#       honors the parent's choices (CI custom-config, alt tmpdir, etc.).
#   GH_TOKEN, GITHUB_TOKEN — passed through ONLY when set in the parent.
#     gh's primary auth is file-backed (~/.config/gh/hosts.yml), but CI
#     environments authenticate solely via env tokens. Without this, headless
#     CI shadows can't talk to GitHub. Provider API keys still live only in
#     ~/.orchestrator-config.json — they are NOT inherited via env.
#
# Max-runtime cap ensures one shadow can't run longer than
# AI_ROUTER_SHADOW_RUNTIME (default 600s = 10 min). claude -p for a review is
# normally ~3 min; the cap is a hard ceiling so orphaned shadows (parent
# session ended before poll fired) can't burn unbounded API tokens.
#
# Mechanism: the wrapper puts claude in its OWN process group (start_new_session
# so claude+descendants are killable as a unit without taking down this bash
# runner, which still needs to write the status file. SIGTERM → 5s grace →
# SIGKILL escalation, then reap to avoid a zombie. Exits 142 on timeout so the
# existing bash accounting below still works.
RUNTIME_CAP=${AI_ROUTER_SHADOW_RUNTIME:-600}

# `set +e` around the call so a non-zero exit doesn't trip set -e and abort
# before the status file is written — the poller relies on the status file
# transitioning out of "running".
set +e
env -i \
  HOME="$HOME" \
  PATH="$PATH" \
  TMPDIR="${TMPDIR:-/tmp}" \
  TERM="${TERM:-dumb}" \
  USER="${USER:-$(id -un 2>/dev/null || echo user)}" \
  LANG="${LANG:-en_US.UTF-8}" \
  ${LC_ALL:+LC_ALL="$LC_ALL"} \
  AI_ROUTER_RUN_ID="$RUN_ID" \
  AI_ROUTER_PROVIDERS="$PROVIDERS" \
  ${AI_ROUTER_CONFIG:+AI_ROUTER_CONFIG="$AI_ROUTER_CONFIG"} \
  ${AI_ROUTER_TMPDIR:+AI_ROUTER_TMPDIR="$AI_ROUTER_TMPDIR"} \
  ${AI_ROUTER_POST_BODY_DIR:+AI_ROUTER_POST_BODY_DIR="$AI_ROUTER_POST_BODY_DIR"} \
  ${AI_ROUTER_SHADOW_TIMEOUT:+AI_ROUTER_SHADOW_TIMEOUT="$AI_ROUTER_SHADOW_TIMEOUT"} \
  ${AI_ROUTER_SHADOW_RUNTIME:+AI_ROUTER_SHADOW_RUNTIME="$AI_ROUTER_SHADOW_RUNTIME"} \
  ${AI_ROUTER_POST_GRACE:+AI_ROUTER_POST_GRACE="$AI_ROUTER_POST_GRACE"} \
  ${GH_TOKEN:+GH_TOKEN="$GH_TOKEN"} \
  ${GITHUB_TOKEN:+GITHUB_TOKEN="$GITHUB_TOKEN"} \
  python3 -c '
import os, signal, subprocess, sys
timeout = int(sys.argv[1])
proc = subprocess.Popen(sys.argv[2:], start_new_session=True)
try:
    sys.exit(proc.wait(timeout=timeout))
except subprocess.TimeoutExpired:
    pgid = os.getpgid(proc.pid)
    try: os.killpg(pgid, signal.SIGTERM)
    except ProcessLookupError: pass
    try: proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        try: os.killpg(pgid, signal.SIGKILL)
        except ProcessLookupError: pass
        proc.wait()
    sys.exit(142)
' "$RUNTIME_CAP" claude -p "$PROMPT" --output-format text \
  > "$STATE/shadow.log" 2>&1
rc=$?
set -e

# Distinguish "claude exited non-zero" from "we hit the runtime cap".
# The python wrapper exits 142 on timeout (kept for back-compat with the
# previous signal.alarm-based design).
if (( rc == 142 )); then
  printf 'failed:runtime-cap-%ss\n' "$RUNTIME_CAP" > "$STATE/shadow.status.tmp"
elif (( rc == 0 )); then
  printf 'done\n' > "$STATE/shadow.status.tmp"
else
  printf 'failed:exit-%s\n' "$rc" > "$STATE/shadow.status.tmp"
fi
mv "$STATE/shadow.status.tmp" "$STATE/shadow.status"
exit "$rc"
