#!/usr/bin/env bash
# post-review.sh — post an ai-router synthesized review to a PR.
#
# Usage: bash post-review.sh <pr-number> <markdown-file> [<providers-csv>]
#   providers-csv defaults to "anthropic,openai,gemini" or $AI_ROUTER_PROVIDERS
#
# Always posts a NEW comment. Prepends a signature marker block so the
# shadow-review poller can identify the comment for a specific run.
#
# Env:
#   AI_ROUTER_RUN_ID  — UUID for this run (generated if unset)
#   AI_ROUTER_PROVIDERS — CSV of providers that contributed
#
# Exit codes:
#   0  ok
#   2  missing PR number or file
#   3  missing dependency (gh)
#  10  gh pr comment failed

set -euo pipefail

[[ $# -ge 2 ]] || { echo "usage: post-review.sh <pr-number> <markdown-file> [providers-csv]" >&2; exit 2; }
PR=$1
BODY_FILE=$2
PROVIDERS=${3:-${AI_ROUTER_PROVIDERS:-anthropic,openai,gemini}}

# Strict PR validation — the script is allow-listed in permissions.allow, so a
# bad caller could otherwise post to an unintended PR. Matches shadow-spawn.sh.
[[ "$PR" =~ ^[1-9][0-9]*$ ]] || { echo "invalid PR number: $PR (must be positive integer)" >&2; exit 2; }

[[ -r "$BODY_FILE" ]] || { echo "cannot read: $BODY_FILE" >&2; exit 2; }
command -v gh >/dev/null 2>&1 || { echo "missing dependency: gh" >&2; exit 3; }

# Skill version is read from the SKILL.md frontmatter so the marker stays in sync.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_MD="$SCRIPT_DIR/../SKILL.md"
SKILL_VER=$(awk -F'"' '/^version:/ {print $2; exit}' "$SKILL_MD" 2>/dev/null || true)
SKILL_VER=${SKILL_VER:-1.3}

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
# UUID via python3 — uuidgen isn't on every system and its output format is
# inconsistent across distros.
RUN_ID=${AI_ROUTER_RUN_ID:-$(python3 -c 'import uuid; print(uuid.uuid4())' 2>/dev/null || echo "run-$(date +%s)-$$")}

TMPDIR_BASE="${AI_ROUTER_TMPDIR:-${TMPDIR:-/tmp}}"
# Trailing-only X's for BSD mktemp compatibility (see call-provider.sh).
WRAPPED=$(mktemp "$TMPDIR_BASE/ai-router-comment.XXXXXX")
trap 'rm -f "$WRAPPED"' EXIT

{
  printf '<!-- ai-router:review:v%s ts=%s run-id=%s -->\n' "$SKILL_VER" "$TS" "$RUN_ID"
  printf '<!-- providers: %s -->\n' "$PROVIDERS"
  printf '\n'
  cat "$BODY_FILE"
  printf '\n<!-- /ai-router:review:v%s run-id=%s -->\n' "$SKILL_VER" "$RUN_ID"
} > "$WRAPPED"

if ! gh pr comment "$PR" --body-file "$WRAPPED" >/dev/null; then
  echo "gh pr comment failed for PR #$PR" >&2
  exit 10
fi

echo "posted: PR #$PR run-id=$RUN_ID"
