#!/usr/bin/env bash
# test_fix_findings.sh — safety/worst-case tests for the auto-fixer.
# Hermetic: local bare remote for pushes, a `gh` stub so no real GitHub is touched.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIX="$HERE/../scripts/fix-findings.sh"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); }
bad()  { FAIL=$((FAIL+1)); echo "  ✗ $1"; }
check(){ if eval "$2"; then ok; else bad "$1 [$2]"; fi; }

# Hermetic gh stub: never reach real GitHub.
STUBDIR=$(mktemp -d)
cat > "$STUBDIR/gh" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *"repo view"*) echo "o/r" ;;
  *graphql*) echo '{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}}}}}' ;;
  *) echo '{}' ;;
esac
exit 0
STUB
chmod +x "$STUBDIR/gh"
export PATH="$STUBDIR:$PATH"

# mkrepo <branch> : fresh repo with a bare remote, on <branch> (default feat/x).
# Writes calc.py with a div-by-zero bug. Echoes the repo dir.
mkrepo() {
  local W; W=$(mktemp -d)
  ( cd "$W"; git init -q --bare o.git
    git clone -q o.git r 2>/dev/null
    cd r; git config user.email t@t.co; git config user.name t
    printf 'def d(a, b):\n    return a / b\n' > calc.py
    git add -A; git commit -qm init
    git switch -qc "${1:-feat/x}" ) >/dev/null 2>&1
  echo "$W/r"
}

vjson() {  # write a single-finding verified.json; args: dir cat file shown suggestion [start end]
  local dir=$1 cat=$2 file=$3 shown=$4 sug=$5 s=${6:-2} e=${7:-2}
  python3 - "$dir/v.json" "$cat" "$file" "$shown" "$sug" "$s" "$e" <<'PY'
import json,sys
p,cat,file,shown,sug,s,e=sys.argv[1:8]
json.dump([{"severity":"SUGGESTION","category":cat,"file":file,"start_line":int(s),"end_line":int(e),
  "issue":"i","fix":"f","suggestion":sug,
  "verify":{"status":"confirmed","resolved_file":file,"shown_code":shown}}], open(p,"w"))
PY
}

GUARD='    return a / b if b != 0 else 0'

echo "test_fix_findings.sh"

# 1. refuse on main
R=$(mkrepo main); vjson "$R" correctness calc.py '    return a / b' "$GUARD"
out=$(cd "$R" && AI_ROUTER_FIX_VERIFY_CMD=true bash "$FIX" "$R/v.json" auto 2>&1); rc=$?
check "refuse on main (exit 2)" "[ $rc -eq 2 ]"
check "refuse on main (message)" "grep -q 'refusing to fix' <<<\"\$out\""

# 2. refuse dirty target file
R=$(mkrepo); vjson "$R" correctness calc.py '    return a / b' "$GUARD"
( cd "$R" && echo "dirty" >> calc.py )
out=$(cd "$R" && AI_ROUTER_FIX_VERIFY_CMD=true bash "$FIX" "$R/v.json" auto 2>&1); rc=$?
check "refuse dirty target (exit 2)" "[ $rc -eq 2 ]"
check "refuse dirty target (message)" "grep -qi 'uncommitted' <<<\"\$out\""

# 3. propose: applies to tree, NO commit
R=$(mkrepo); vjson "$R" correctness calc.py '    return a / b' "$GUARD"
out=$(cd "$R" && bash "$FIX" "$R/v.json" propose 2>&1); rc=$?
check "propose exit 0" "[ $rc -eq 0 ]"
check "propose applied to tree" "grep -q 'if b != 0' \"$R/calc.py\""
check "propose did NOT commit" "[ \"\$(cd \"$R\" && git rev-list --count HEAD)\" = 1 ]"

# 4. auto verify-pass: commit + push
R=$(mkrepo); vjson "$R" correctness calc.py '    return a / b' "$GUARD"
out=$(cd "$R" && AI_ROUTER_FIX_VERIFY_CMD='python3 -c "import calc; assert calc.d(1,0)==0"' bash "$FIX" "$R/v.json" auto 2>&1); rc=$?
check "auto pass exit 0" "[ $rc -eq 0 ]"
check "auto pass committed (2 commits)" "[ \"\$(cd \"$R\" && git rev-list --count HEAD)\" = 2 ]"
check "auto pass pushed to origin" "[ -n \"\$(cd \"$R\" && git ls-remote --heads origin feat/x)\" ]"

# 5. auto verify-fail: revert, no commit, exit 1
R=$(mkrepo); vjson "$R" correctness calc.py '    return a / b' "$GUARD"
out=$(cd "$R" && AI_ROUTER_FIX_VERIFY_CMD=false bash "$FIX" "$R/v.json" auto 2>&1); rc=$?
check "auto fail exit 1" "[ $rc -eq 1 ]"
check "auto fail reverted file" "! grep -q 'if b != 0' \"$R/calc.py\""
check "auto fail no new commit" "[ \"\$(cd \"$R\" && git rev-list --count HEAD)\" = 1 ]"

# 6. auto no verify cmd: applies, no push, exit 0 (downgrade)
R=$(mkrepo); vjson "$R" correctness calc.py '    return a / b' "$GUARD"
out=$(cd "$R" && bash "$FIX" "$R/v.json" auto 2>&1); rc=$?
check "auto no-verify exit 0" "[ $rc -eq 0 ]"
check "auto no-verify did NOT push" "[ -z \"\$(cd \"$R\" && git ls-remote --heads origin feat/x)\" ]"
check "auto no-verify message" "grep -qi 'not committing' <<<\"\$out\""

# 7. trivial verify -> warning
R=$(mkrepo); vjson "$R" correctness calc.py '    return a / b' "$GUARD"
out=$(cd "$R" && AI_ROUTER_FIX_VERIFY_CMD=true bash "$FIX" "$R/v.json" auto 2>&1)
check "trivial verify warns" "grep -qi 'trivial' <<<\"\$out\""

# 8. allowlist: security category excluded from auto
R=$(mkrepo); vjson "$R" security calc.py '    return a / b' "$GUARD"
out=$(cd "$R" && AI_ROUTER_FIX_VERIFY_CMD=true bash "$FIX" "$R/v.json" auto 2>&1)
check "security excluded (not applied)" "! grep -q 'if b != 0' \"$R/calc.py\""
check "security excluded (no eligible)" "grep -qi 'no auto-eligible' <<<\"\$out\""

# 9. denylist path excluded (config-ish path)
R=$(mkrepo)
( cd "$R" && printf 'X = 1\n' > settings.py && git add -A && git commit -qm s )
vjson "$R" correctness settings.py 'X = 1' 'X = 2' 1 1
out=$(cd "$R" && AI_ROUTER_FIX_VERIFY_CMD=true bash "$FIX" "$R/v.json" auto 2>&1)
check "denylist path excluded" "grep -qi 'no auto-eligible' <<<\"\$out\""

# 10. oversized range excluded (range > 20)
R=$(mkrepo); vjson "$R" correctness calc.py '    return a / b' "$GUARD" 1 25
out=$(cd "$R" && AI_ROUTER_FIX_VERIFY_CMD=true bash "$FIX" "$R/v.json" auto 2>&1)
check "oversized range excluded" "grep -qi 'no auto-eligible' <<<\"\$out\""

# 11. stale finding skipped (shown_code no longer matches)
R=$(mkrepo); vjson "$R" correctness calc.py '    WRONG' "$GUARD"
out=$(cd "$R" && AI_ROUTER_FIX_VERIFY_CMD=true bash "$FIX" "$R/v.json" auto 2>&1)
check "stale finding skipped" "grep -qi 'stale' <<<\"\$out\""
check "stale: file untouched" "! grep -q 'if b != 0' \"$R/calc.py\""

# 12. detached worktree push-by-ref (PUSH_REF)
R=$(mkrepo); ( cd "$R" && git push -q origin feat/x )
WT=$(mktemp -d)
( cd "$R" && git worktree add -q --detach "$WT" origin/feat/x )
vjson "$WT" correctness calc.py '    return a / b' "$GUARD"
out=$(cd "$WT" && AI_ROUTER_FIX_PUSH_REF=feat/x AI_ROUTER_FIX_VERIFY_CMD='python3 -c "import calc; assert calc.d(1,0)==0"' bash "$FIX" "$WT/v.json" auto 2>&1); rc=$?
check "detached push-by-ref exit 0" "[ $rc -eq 0 ]"
check "detached push-by-ref updated branch" "cd \"$R\" && git fetch -q origin && git show origin/feat/x:calc.py | grep -q 'if b != 0'"

echo "  fix-findings: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
