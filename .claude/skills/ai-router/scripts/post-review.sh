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
# Defense-in-depth: this script is wildcard-allowlisted, so a stray invocation
# could otherwise turn arbitrary local files into public PR comments. Constrain
# BODY_FILE to the per-run tmpdir, require caller ownership, and reject any
# component being a symlink. Reject symlinks BEFORE realpath so a symlink
# pointing into the trusted dir can't bypass the case check.
[[ -L "$BODY_FILE" ]] && { echo "post-review.sh: BODY_FILE must not be a symlink" >&2; exit 2; }

# AI_ROUTER_POST_BODY_DIR overrides the default tmpdir. Unset → use default;
# explicit empty string → trusted-path check disabled (escape hatch for
# unusual workflows; ownership + non-symlink checks still apply).
if [[ -z "${AI_ROUTER_POST_BODY_DIR+set}" ]]; then
  TRUSTED_DIR=${AI_ROUTER_TMPDIR:-${TMPDIR:-/tmp}}
elif [[ -z "$AI_ROUTER_POST_BODY_DIR" ]]; then
  TRUSTED_DIR=""   # explicit opt-out
else
  TRUSTED_DIR=$AI_ROUTER_POST_BODY_DIR
fi
BODY_FILE_REAL=$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$BODY_FILE")
if [[ -n "$TRUSTED_DIR" ]]; then
  TRUSTED_REAL=$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$TRUSTED_DIR")
  case "$BODY_FILE_REAL" in
    "$TRUSTED_REAL"/*) : ;;
    *) echo "post-review.sh: BODY_FILE must live under $TRUSTED_REAL (got: $BODY_FILE_REAL)" >&2; exit 2 ;;
  esac
fi
# Owner check — guards against another local user pre-staging a body file.
FILE_OWNER=$(python3 -c 'import os,sys; print(os.stat(sys.argv[1]).st_uid)' "$BODY_FILE_REAL")
if [[ "$FILE_OWNER" != "$(id -u)" ]]; then
  echo "post-review.sh: BODY_FILE not owned by current user" >&2; exit 2
fi
command -v gh >/dev/null 2>&1 || { echo "missing dependency: gh" >&2; exit 3; }

# Skill version is read from the SKILL.md frontmatter so the marker stays in sync.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_MD="$SCRIPT_DIR/../SKILL.md"
SKILL_VER=$(awk -F'"' '/^version:/ {print $2; exit}' "$SKILL_MD" 2>/dev/null || true)
SKILL_VER=${SKILL_VER:-1.5}

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
# UUID via python3 — uuidgen isn't on every system and its output format is
# inconsistent across distros.
RUN_ID=${AI_ROUTER_RUN_ID:-$(python3 -c 'import uuid; print(uuid.uuid4())' 2>/dev/null || echo "run-$(date +%s)-$$")}

# Validate marker fields before they land in the HTML comment block. A value
# containing `-->`, a newline, or other markdown-active chars would break out
# of the signature block and either confuse the poll's run-id match or render
# as visible content. Both fields are normally script-generated and safe, but
# AI_ROUTER_RUN_ID / AI_ROUTER_PROVIDERS can be set externally.
[[ "$RUN_ID" =~ ^[A-Za-z0-9._:-]+$ ]] || {
  echo "post-review.sh: invalid RUN_ID (must match [A-Za-z0-9._:-]+): $RUN_ID" >&2
  exit 2
}
[[ "$PROVIDERS" =~ ^[a-z][a-z0-9_,-]*$ ]] || {
  echo "post-review.sh: invalid PROVIDERS (must be CSV of [a-z0-9_-] tokens): $PROVIDERS" >&2
  exit 2
}

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
