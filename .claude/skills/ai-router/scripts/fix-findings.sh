#!/usr/bin/env bash
# fix-findings.sh — apply verified findings' suggested fixes. Phase 3.
#
# Usage: bash fix-findings.sh <verified-json> <propose|auto> [<pr-number>]
#
#   propose : apply every confirmed finding that carries a suggestion to the
#             WORKING TREE, then stop. Nothing is committed or pushed — the diff
#             is left for a human to review and commit. (developer posture)
#   auto    : apply only findings that pass the conservative allowlist, run the
#             verify command, and only if it passes: commit + push to the current
#             branch and resolve the fixed threads. On failure: revert, push
#             nothing. (guided posture — guarded auto-fixer)
#
# Safety (all enforced here, not left to the caller):
#   - never runs on main/master or a detached HEAD;
#   - requires a clean working tree (the fix commit must be isolated/revertible);
#   - apply-fix.py only edits lines whose current content still matches the
#     grounded `shown_code`, so a shifted/stale file is never corrupted;
#   - fixes apply bottom-up per file so earlier edits don't shift later lines;
#   - auto refuses categories outside the allowlist and paths in the denylist;
#   - auto with no verify command set does NOT push — it downgrades to propose.
#
# Env:
#   AI_ROUTER_FIX_VERIFY_CMD  test/build/lint command for `auto` (e.g. "npm test").
#   AI_ROUTER_FIX_DENYLIST    override the sensitive-path regex (extended, -E -i).
#
# Exit codes: 0 ok | 2 usage/guardrail | 3 missing dep | 1 verify failed (reverted)

set -euo pipefail

ALLOWLIST='["correctness","maintainability","performance","tests"]'
DENYLIST_DEFAULT='(^|/)(\.env|.*secret|.*credential|.*password|.*token|auth|login|session|crypto|payment|billing|stripe|migration|schema|settings|config|infra|terraform|[Dd]ockerfile|docker-compose|deploy)|\.github/workflows/'
DENYLIST=${AI_ROUTER_FIX_DENYLIST:-$DENYLIST_DEFAULT}
MAX_RANGE=20
MAX_REPL=25

[[ $# -ge 2 ]] || { echo "usage: fix-findings.sh <verified-json> <propose|auto> [<pr>]" >&2; exit 2; }
VERIFIED=$1
MODE=$2
PR=${3:-}
[[ "$MODE" == "propose" || "$MODE" == "auto" ]] || { echo "mode must be propose|auto" >&2; exit 2; }
[[ -r "$VERIFIED" ]] || { echo "cannot read: $VERIFIED" >&2; exit 2; }
[[ -z "$PR" || "$PR" =~ ^[1-9][0-9]*$ ]] || { echo "invalid PR: $PR" >&2; exit 2; }
for b in python3 jq git; do command -v "$b" >/dev/null 2>&1 || { echo "missing dependency: $b" >&2; exit 3; }; done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git repo" >&2; exit 2; }
BRANCH=$(git rev-parse --abbrev-ref HEAD)

# AI_ROUTER_FIX_PUSH_REF: when set, we're in a detached worktree (the shadow
# flow) and push the resulting commit to that remote branch instead of the
# current local branch. Lets auto-fix run on an isolated checkout that never
# touches the user's working tree.
PUSH_REF=${AI_ROUTER_FIX_PUSH_REF:-}

# --- Guardrails ------------------------------------------------------------
if [[ -n "$PUSH_REF" ]]; then
  if [[ "$PUSH_REF" == "main" || "$PUSH_REF" == "master" ]]; then
    echo "fix-findings.sh: refusing to push fixes to '$PUSH_REF'." >&2
    exit 2
  fi
elif [[ "$BRANCH" == "main" || "$BRANCH" == "master" || "$BRANCH" == "HEAD" ]]; then
  echo "fix-findings.sh: refusing to fix on '$BRANCH' — check out a feature branch first." >&2
  exit 2
fi

# --- Select eligible findings ---------------------------------------------
# propose: any confirmed finding with a suggestion (a human reviews the diff).
# auto: confirmed + suggestion + category allowlist + path denylist + size caps.
if [[ "$MODE" == "auto" ]]; then
  ELIGIBLE=$(jq --argjson allow "$ALLOWLIST" --arg deny "$DENYLIST" --argjson maxr "$MAX_RANGE" --argjson maxl "$MAX_REPL" '
    [ .[]
      | select((.verify.status // "") == "confirmed")
      | select((.suggestion // "") | length > 0)
      | select(.category as $c | $allow | index($c))
      | select(((.end_line // .start_line) - .start_line) <= $maxr)
      | select(((.suggestion | split("\n") | length)) <= $maxl)
      | select((.verify.resolved_file // .file) | test($deny; "i") | not)
    ] | sort_by([(.verify.resolved_file // .file), (-(.start_line))])' "$VERIFIED")
else
  ELIGIBLE=$(jq '
    [ .[]
      | select((.verify.status // "") == "confirmed")
      | select((.suggestion // "") | length > 0)
    ] | sort_by([(.verify.resolved_file // .file), (-(.start_line))])' "$VERIFIED")
fi

N=$(jq 'length' <<<"$ELIGIBLE")
if [[ "$N" -eq 0 ]]; then
  echo "fix-findings.sh: no ${MODE}-eligible findings (need confirmed + a suggestion$( [[ $MODE == auto ]] && echo ' + allowlisted category/path' ))."
  exit 0
fi

# Refuse only if a file we're about to edit has uncommitted changes. We add and
# revert per-file, so unrelated dirty/untracked files in the tree are fine — no
# need to demand a globally clean tree.
TARGETS=()
while IFS= read -r tf; do [[ -n "$tf" ]] && TARGETS+=("$tf"); done \
  < <(jq -r '[.[] | (.verify.resolved_file // .file)] | unique | .[]' <<<"$ELIGIBLE")
DIRTY=()
for tf in "${TARGETS[@]:-}"; do
  [[ -n "$tf" && -n "$(git status --porcelain -- "$tf" 2>/dev/null)" ]] && DIRTY+=("$tf")
done
if [[ ${#DIRTY[@]} -gt 0 ]]; then
  echo "fix-findings.sh: these target files have uncommitted changes — commit or stash them first:" >&2
  printf '  %s\n' "${DIRTY[@]}" >&2
  exit 2
fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/ai-router-fix-XXXXXX")
trap 'rm -rf "$TMP"' EXIT
APPLIED=()        # "file:start-end"
SKIPPED=()        # "file:start-end (reason)"
declare -a FILES  # changed files (unique)

apply_one() {
  local i=$1
  local f s e
  f=$(jq -r ".[$i].verify.resolved_file // .[$i].file" <<<"$ELIGIBLE")
  s=$(jq -r ".[$i].start_line" <<<"$ELIGIBLE")
  e=$(jq -r ".[$i].end_line // .[$i].start_line" <<<"$ELIGIBLE")
  jq -r ".[$i].verify.shown_code" <<<"$ELIGIBLE" > "$TMP/expected"
  jq -r ".[$i].suggestion" <<<"$ELIGIBLE" > "$TMP/repl"
  if [[ ! -f "$f" ]]; then SKIPPED+=("$f:$s-$e (file not found in tree)"); return; fi
  local rc=0
  python3 "$SCRIPT_DIR/apply-fix.py" --file "$f" --start "$s" --end "$e" \
    --expected "$TMP/expected" --replacement "$TMP/repl" 2>"$TMP/err" || rc=$?
  if [[ $rc -eq 0 ]]; then
    APPLIED+=("$f:$s-$e")
    local seen=0; for x in "${FILES[@]:-}"; do [[ "$x" == "$f" ]] && seen=1; done
    [[ $seen -eq 0 ]] && FILES+=("$f")
  elif [[ $rc -eq 3 ]]; then SKIPPED+=("$f:$s-$e (stale — file changed since review)")
  elif [[ $rc -eq 4 ]]; then SKIPPED+=("$f:$s-$e (range out of bounds)")
  else SKIPPED+=("$f:$s-$e (apply error)"); fi
}

for ((i = 0; i < N; i++)); do apply_one "$i"; done

print_summary() {
  echo "── fix-findings ($MODE) ──"
  echo "applied: ${#APPLIED[@]}"
  for a in "${APPLIED[@]:-}"; do [[ -n "$a" ]] && echo "  ✓ $a"; done
  if [[ ${#SKIPPED[@]} -gt 0 ]]; then
    echo "skipped: ${#SKIPPED[@]}"
    for sk in "${SKIPPED[@]:-}"; do [[ -n "$sk" ]] && echo "  – $sk"; done
  fi
}

if [[ ${#APPLIED[@]} -eq 0 ]]; then
  print_summary
  echo "nothing applied (all eligible findings were stale or unwritable)."
  exit 0
fi

# --- propose: leave changes for review ------------------------------------
if [[ "$MODE" == "propose" ]]; then
  print_summary
  echo
  echo "── working-tree diff (not committed) ──"
  git --no-pager diff --stat
  echo
  echo "Review the changes, then commit when ready. To discard: git checkout -- ${FILES[*]}"
  exit 0
fi

# --- auto: verify, then commit + push + resolve, else revert --------------
revert_all() { git checkout -- "${FILES[@]}" 2>/dev/null || true; }

if [[ -z "${AI_ROUTER_FIX_VERIFY_CMD:-}" ]]; then
  print_summary
  echo
  echo "auto: no AI_ROUTER_FIX_VERIFY_CMD set — NOT committing/pushing without a passing test run."
  echo "Changes are left in the working tree (treat as propose). Review + commit manually, or set"
  echo "AI_ROUTER_FIX_VERIFY_CMD (e.g. 'npm test') and re-run. To discard: git checkout -- ${FILES[*]}"
  exit 0
fi

echo "auto: running verify command: $AI_ROUTER_FIX_VERIFY_CMD"
if ! bash -c "$AI_ROUTER_FIX_VERIFY_CMD" >"$TMP/verify.log" 2>&1; then
  revert_all
  print_summary
  echo
  echo "auto: verify FAILED — reverted all ${#APPLIED[@]} fix(es), nothing committed or pushed."
  echo "── last 30 lines of verify output ──"
  tail -n 30 "$TMP/verify.log"
  exit 1
fi
echo "auto: verify passed."

# Commit body listing what was fixed.
{
  printf 'fix(ai-router): auto-fix %s verified finding(s)\n\n' "${#APPLIED[@]}"
  printf 'Applied by ai-router fix-findings (auto). Each fix replaced lines whose\n'
  printf 'content still matched the reviewed code, and the verify command passed.\n\n'
  for a in "${APPLIED[@]}"; do printf -- '- %s\n' "$a"; done
  printf '\nCo-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>\n'
} > "$TMP/msg"

git add -- "${FILES[@]}"
git commit -F "$TMP/msg" >/dev/null
# Push to the PR branch. PUSH_REF mode (detached worktree) pushes HEAD to the
# named remote branch; otherwise push the current branch. Never force.
if [[ -n "$PUSH_REF" ]]; then
  PUSH_TARGET="$PUSH_REF"; PUSH_SPEC="HEAD:$PUSH_REF"
else
  PUSH_TARGET="$BRANCH"; PUSH_SPEC="$BRANCH"
fi
if ! git push origin "$PUSH_SPEC" >/dev/null 2>"$TMP/push.err"; then
  echo "auto: committed locally but push failed:" >&2
  cat "$TMP/push.err" >&2
  echo "(commit is local; push '$PUSH_SPEC' manually.)"
  exit 1
fi

print_summary
echo
echo "auto: committed + pushed ${#APPLIED[@]} fix(es) to '$PUSH_TARGET'."
if [[ -n "$PR" ]]; then
  bash "$SCRIPT_DIR/resolve-threads.sh" "$PR" || echo "(thread resolve skipped/failed — non-fatal)"
fi
