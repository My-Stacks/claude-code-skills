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

[[ $# -eq 6 ]] || { echo "shadow-runner.sh: bad argc ($#) — expected 6" >&2; exit 64; }
PR=$1; RUN_ID=$2; PROVIDERS=$3; POST=$4; STATE=$5; FIX=$6

# The repo the shadow was spawned in. Worktree ops run from here, and review-only
# runs use it as cwd (unchanged behavior).
REPO_DIR=$PWD

# Atomic pgid write. Equals the new session leader (this bash process).
PGID=$(ps -o pgid= -p $$ | tr -d ' ')
printf '%s\n' "$PGID" > "$STATE/shadow.pgid.tmp" && mv "$STATE/shadow.pgid.tmp" "$STATE/shadow.pgid"

# --- Optional worktree-isolated auto-fix -----------------------------------
# FIX=auto runs the review on an ISOLATED detached `git worktree` of the PR's
# head branch, so an unattended fix can never touch the user's checked-out tree
# or current branch. The fix commits in the worktree and pushes HEAD to the PR
# branch (AI_ROUTER_FIX_PUSH_REF). We refuse — and fall back to review-only —
# for fork PRs (can't push to the fork) or when no verify command is set (an
# unattended fix must be test-gated, and the worktree is discarded after, so an
# un-pushable fix would just be wasted work).
RUN_CWD=$REPO_DIR
WT=""
PUSH_REF=""
if [[ "$FIX" == "auto" ]]; then
  if [[ -z "${AI_ROUTER_FIX_VERIFY_CMD:-}" ]]; then
    echo "shadow-runner: FIX=auto but AI_ROUTER_FIX_VERIFY_CMD unset — review-only." >&2
    FIX=""
  elif ! git -C "$REPO_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "shadow-runner: not a git repo — review-only." >&2
    FIX=""
  else
    HEAD_BRANCH=$(gh pr view "$PR" --json headRefName -q .headRefName 2>/dev/null || echo "")
    IS_FORK=$(gh pr view "$PR" --json isCrossRepository -q .isCrossRepository 2>/dev/null || echo "true")
    if [[ -z "$HEAD_BRANCH" || "$IS_FORK" == "true" ]]; then
      echo "shadow-runner: fork PR or unknown head branch — auto-fix can't push; review-only." >&2
      FIX=""
    else
      WT="$STATE/worktree"
      git -C "$REPO_DIR" worktree remove --force "$WT" 2>/dev/null || true
      git -C "$REPO_DIR" worktree prune 2>/dev/null || true
      if git -C "$REPO_DIR" fetch -q origin "$HEAD_BRANCH" \
         && git -C "$REPO_DIR" worktree add -q --detach "$WT" "origin/$HEAD_BRANCH"; then
        RUN_CWD="$WT"
        PUSH_REF="$HEAD_BRANCH"
      else
        echo "shadow-runner: worktree setup failed — review-only." >&2
        git -C "$REPO_DIR" worktree remove --force "$WT" 2>/dev/null || true
        WT=""; FIX=""
      fi
    fi
  fi
fi

# Remove the worktree on ANY exit (normal, error, runtime-cap, or cancel). A
# hard SIGKILL of the runner can still leak it; `git worktree prune` on the next
# run reclaims the metadata. Cancel maps SIGTERM/INT to exit so this fires.
cleanup_wt() { [[ -n "$WT" ]] && { git -C "$REPO_DIR" worktree remove --force "$WT" 2>/dev/null || true; git -C "$REPO_DIR" worktree prune 2>/dev/null || true; }; }
trap cleanup_wt EXIT
trap 'exit 143' INT TERM

# Build the claude -p prompt. PR is interpolated into the string, but
# shadow-spawn.sh strictly validated it (^[1-9][0-9]*$) so injection is blocked.
if [[ "$POST" == "true" ]]; then
  PROMPT="/ai-router review $PR --post-to-pr $PR"
else
  PROMPT="/ai-router review $PR"
fi
[[ "$FIX" == "auto" ]] && PROMPT="$PROMPT --fix=auto"

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
#
# Build the optional-env list as an ARRAY rather than inline ${VAR:+...}
# expansions. Inline expansions are word-split by bash after substitution,
# so a value containing a space/newline/quote splits into multiple args and
# corrupts the child env (e.g. PATH with a space in it, or a poorly-formed
# AI_ROUTER_CONFIG). Array elements are passed verbatim with no splitting.
ENV_EXTRA=()
[[ -n "${LC_ALL:-}" ]]                   && ENV_EXTRA+=(LC_ALL="$LC_ALL")
[[ -n "${AI_ROUTER_CONFIG:-}" ]]         && ENV_EXTRA+=(AI_ROUTER_CONFIG="$AI_ROUTER_CONFIG")
[[ -n "${AI_ROUTER_TMPDIR:-}" ]]         && ENV_EXTRA+=(AI_ROUTER_TMPDIR="$AI_ROUTER_TMPDIR")
[[ -n "${AI_ROUTER_POST_BODY_DIR:-}" ]]  && ENV_EXTRA+=(AI_ROUTER_POST_BODY_DIR="$AI_ROUTER_POST_BODY_DIR")
[[ -n "${AI_ROUTER_SHADOW_TIMEOUT:-}" ]] && ENV_EXTRA+=(AI_ROUTER_SHADOW_TIMEOUT="$AI_ROUTER_SHADOW_TIMEOUT")
[[ -n "${AI_ROUTER_SHADOW_RUNTIME:-}" ]] && ENV_EXTRA+=(AI_ROUTER_SHADOW_RUNTIME="$AI_ROUTER_SHADOW_RUNTIME")
[[ -n "${AI_ROUTER_POST_GRACE:-}" ]]     && ENV_EXTRA+=(AI_ROUTER_POST_GRACE="$AI_ROUTER_POST_GRACE")
[[ -n "${GH_TOKEN:-}" ]]                 && ENV_EXTRA+=(GH_TOKEN="$GH_TOKEN")
[[ -n "${GITHUB_TOKEN:-}" ]]             && ENV_EXTRA+=(GITHUB_TOKEN="$GITHUB_TOKEN")
# Auto-fix passthrough (only meaningful when FIX survived the checks above).
[[ -n "$PUSH_REF" ]]                          && ENV_EXTRA+=(AI_ROUTER_FIX_PUSH_REF="$PUSH_REF")
[[ "$FIX" == "auto" && -n "${AI_ROUTER_FIX_VERIFY_CMD:-}" ]] && ENV_EXTRA+=(AI_ROUTER_FIX_VERIFY_CMD="$AI_ROUTER_FIX_VERIFY_CMD")
[[ -n "${AI_ROUTER_FIX_DENYLIST:-}" ]]        && ENV_EXTRA+=(AI_ROUTER_FIX_DENYLIST="$AI_ROUTER_FIX_DENYLIST")
set +e
( cd "$RUN_CWD" && env -i \
  HOME="$HOME" \
  PATH="$PATH" \
  TMPDIR="${TMPDIR:-/tmp}" \
  TERM="${TERM:-dumb}" \
  USER="${USER:-$(id -un 2>/dev/null || echo user)}" \
  LANG="${LANG:-en_US.UTF-8}" \
  AI_ROUTER_RUN_ID="$RUN_ID" \
  AI_ROUTER_PROVIDERS="$PROVIDERS" \
  AI_ROUTER_STATE_DIR="$STATE" \
  ${ENV_EXTRA[@]:+"${ENV_EXTRA[@]}"} \
  python3 -c '
import os, signal, subprocess, sys
timeout = int(sys.argv[1])
proc = subprocess.Popen(sys.argv[2:], start_new_session=True)
# Capture PGID NOW, while the child is guaranteed to exist. Calling
# os.getpgid(proc.pid) later (e.g. after TimeoutExpired) can race with a
# fast-exiting child whose PID has already been recycled on a busy host —
# then killpg lands on an unrelated process group.
pgid = os.getpgid(proc.pid)
# Record claude PID and PGID so the parent can liveness-check + cancel the
# actual reviewer process. start_new_session puts claude in its OWN pgid,
# distinct from this wrapper and from shadow-runner.sh — without this file,
# cancel signals the runner and leaves claude detached.
state = os.environ.get("AI_ROUTER_STATE_DIR")
if state:
    try:
        with open(os.path.join(state, "claude.pid.tmp"), "w") as f:
            f.write(f"{proc.pid}\n")
        os.rename(os.path.join(state, "claude.pid.tmp"),
                  os.path.join(state, "claude.pid"))
        with open(os.path.join(state, "claude.pgid.tmp"), "w") as f:
            f.write(f"{pgid}\n")
        os.rename(os.path.join(state, "claude.pgid.tmp"),
                  os.path.join(state, "claude.pgid"))
    except OSError:
        pass  # best-effort; main flow continues
try:
    sys.exit(proc.wait(timeout=timeout))
except subprocess.TimeoutExpired:
    try: os.killpg(pgid, signal.SIGTERM)
    except ProcessLookupError: pass
    try: proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        try: os.killpg(pgid, signal.SIGKILL)
        except ProcessLookupError: pass
        proc.wait()
    sys.exit(142)
' "$RUNTIME_CAP" claude -p "$PROMPT" --output-format text ) \
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
