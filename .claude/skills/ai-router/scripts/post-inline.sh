#!/usr/bin/env bash
# post-inline.sh — post an ai-router review as INLINE PR comments at real lines.
#
# Usage: bash post-inline.sh <pr-number> <verified-findings-json> <summary-md>
#   verified-findings-json : output of verify-findings.py
#   summary-md             : markdown for the review body
#
# Posts a single PR review (event=COMMENT) with one inline comment per grounded
# finding (verify.status confirmed/partial). Ungrounded findings are listed in the
# review body, never posted inline (GitHub rejects out-of-diff lines).
#
# Env:
#   AI_ROUTER_RUN_ID     — UUID for this run (generated if unset); embedded in marker
#   AI_ROUTER_POST_BODY_DIR — override/disable the trusted-dir check (see post-review.sh)
#
# Exit codes:
#   0  ok
#   2  bad args / untrusted input file
#   3  missing dependency (gh / python3)
#  10  gh review API call failed

set -euo pipefail

[[ $# -ge 3 ]] || { echo "usage: post-inline.sh <pr-number> <verified-findings-json> <summary-md>" >&2; exit 2; }
PR=$1
FINDINGS_FILE=$2
SUMMARY_FILE=$3

[[ "$PR" =~ ^[1-9][0-9]*$ ]] || { echo "invalid PR number: $PR (must be positive integer)" >&2; exit 2; }
command -v gh >/dev/null 2>&1 || { echo "missing dependency: gh" >&2; exit 3; }
command -v python3 >/dev/null 2>&1 || { echo "missing dependency: python3" >&2; exit 3; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- input-file safety (same model as post-review.sh): this script is wildcard-
# allowlisted, so constrain inputs to the per-run tmpdir, require ownership, and
# reject symlinks so a stray call can't turn arbitrary local files into PR content.
if [[ -z "${AI_ROUTER_POST_BODY_DIR+set}" ]]; then
  TRUSTED_DIR=${AI_ROUTER_TMPDIR:-${TMPDIR:-/tmp}}
elif [[ -z "$AI_ROUTER_POST_BODY_DIR" ]]; then
  TRUSTED_DIR=""
else
  TRUSTED_DIR=$AI_ROUTER_POST_BODY_DIR
fi
check_input() {
  local f=$1
  [[ -r "$f" ]] || { echo "cannot read: $f" >&2; exit 2; }
  [[ -L "$f" ]] && { echo "post-inline.sh: $f must not be a symlink" >&2; exit 2; }
  local real; real=$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$f")
  if [[ -n "$TRUSTED_DIR" ]]; then
    local troot; troot=$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$TRUSTED_DIR")
    case "$real" in
      "$troot"/*) : ;;
      *) echo "post-inline.sh: $f must live under $troot (got: $real)" >&2; exit 2 ;;
    esac
  fi
  local owner; owner=$(python3 -c 'import os,sys; print(os.stat(sys.argv[1]).st_uid)' "$real")
  [[ "$owner" == "$(id -u)" ]] || { echo "post-inline.sh: $f not owned by current user" >&2; exit 2; }
}
check_input "$FINDINGS_FILE"
check_input "$SUMMARY_FILE"

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
SHA=$(gh pr view "$PR" --json headRefOid -q .headRefOid)
[[ -n "$SHA" ]] || { echo "post-inline.sh: could not resolve head commit for PR #$PR" >&2; exit 10; }

SKILL_MD="$SCRIPT_DIR/../SKILL.md"
SKILL_VER=$(awk -F'"' '/^version:/ {print $2; exit}' "$SKILL_MD" 2>/dev/null || true)
SKILL_VER=${SKILL_VER:-1.6}
RUN_ID=${AI_ROUTER_RUN_ID:-$(python3 -c 'import uuid; print(uuid.uuid4())' 2>/dev/null || echo "run-$(date +%s)-$$")}
[[ "$RUN_ID" =~ ^[A-Za-z0-9._:-]+$ ]] || { echo "post-inline.sh: invalid RUN_ID: $RUN_ID" >&2; exit 2; }

TMPDIR_BASE="${AI_ROUTER_TMPDIR:-${TMPDIR:-/tmp}}"
PAYLOAD=$(mktemp "$TMPDIR_BASE/ai-router-review.XXXXXX")
ERRFILE=$(mktemp "$TMPDIR_BASE/ai-router-builderr.XXXXXX")
trap 'rm -f "$PAYLOAD" "$ERRFILE"' EXIT

# Build the review payload: stdout (JSON) -> PAYLOAD, stderr (counts/errors) ->
# ERRFILE. Separate files mean a Python traceback can't pollute the JSON or
# masquerade as the success counts line.
if ! python3 "$SCRIPT_DIR/lib/build-review-payload.py" \
      --commit "$SHA" --body-file "$SUMMARY_FILE" \
      --version "$SKILL_VER" --run-id "$RUN_ID" \
      < "$FINDINGS_FILE" >"$PAYLOAD" 2>"$ERRFILE"; then
  echo "post-inline.sh: failed to build review payload" >&2
  cat "$ERRFILE" >&2
  exit 10
fi
COUNTS=$(cat "$ERRFILE")

if ! gh api -X POST "repos/$REPO/pulls/$PR/reviews" --input "$PAYLOAD" >/dev/null; then
  echo "gh review API failed for PR #$PR" >&2
  exit 10
fi

echo "posted inline review: PR #$PR run-id=$RUN_ID ${COUNTS:-}"
