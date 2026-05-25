#!/usr/bin/env bash
# shadow-list.sh — list active shadow-review runs for this repo.
#
# Usage: bash shadow-list.sh
# stdout: tab-separated rows of:  PR  STATUS  STARTED_AT  STATE_DIR  PID  ALIVE
#         (header line first; no rows if nothing active)
# stderr: human-readable errors
# exit 0 always (empty list isn't an error)
#
# Useful for spotting orphans after a parent session ended without
# `/ai-router shadow-cancel`. Skips `.stale.*` archived dirs.

set -euo pipefail

command -v gh >/dev/null 2>&1 || { echo "missing dependency: gh" >&2; exit 3; }

REPO_SLUG=$(gh repo view --json nameWithOwner -q .nameWithOwner | tr '/' '-')
SHADOW_BASE="${AI_ROUTER_SHADOW_DIR:-${AI_ROUTER_TMPDIR:-${TMPDIR:-/tmp}}/ai-router-shadow}"
SHADOW_BASE=${SHADOW_BASE%/}

printf 'PR\tSTATUS\tSTARTED_AT\tSTATE_DIR\tPID\tALIVE\n'

shopt -s nullglob
for d in "$SHADOW_BASE/${REPO_SLUG}-pr"*; do
  [[ -d "$d" ]] || continue
  case "$d" in *.stale.*) continue ;; esac
  pr=$(cat "$d/pr" 2>/dev/null || echo "?")
  status=$(cat "$d/shadow.status" 2>/dev/null || echo "?")
  started=$(cat "$d/started_at" 2>/dev/null || echo "?")
  # Prefer claude.pid (the actual reviewer) over shadow.pid (the outer python
  # wrapper, which exits immediately after Popen). Falling back to shadow.pid
  # supports legacy state dirs.
  pid=$(cat "$d/claude.pid" 2>/dev/null || cat "$d/shadow.pid" 2>/dev/null || echo "")
  alive="no"
  if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
    alive="yes"
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$pr" "$status" "$started" "$d" "${pid:--}" "$alive"
done
