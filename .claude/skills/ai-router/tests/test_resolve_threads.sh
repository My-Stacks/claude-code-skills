#!/usr/bin/env bash
# test_resolve_threads.sh — selection correctness + the critical safety property:
# NEVER resolve a human (un-markered) thread, in any mode. Hermetic via a gh stub
# that serves canned reviewThreads and logs which thread ids get the mutation.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RT="$HERE/../scripts/resolve-threads.sh"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); }
bad(){ FAIL=$((FAIL+1)); echo "  ✗ $1"; }
check(){ if eval "$2"; then ok; else bad "$1 [$2]"; fi; }

KA="aaaa11112222"; KB="bbbb33334444"
WORK=$(mktemp -d)
export GH_THREADS="$WORK/threads.json"
export GH_RESOLVED="$WORK/resolved.log"

# Canned reviewThreads: a fixed+outdated ours, another (not outdated) ours, an
# already-resolved ours, and a HUMAN thread (no marker).
cat > "$GH_THREADS" <<JSON
{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[
 {"id":"Tfix","isResolved":false,"isOutdated":true,"comments":{"nodes":[{"body":"bug\n<!-- ai-router-finding key=$KA -->"}]}},
 {"id":"Toth","isResolved":false,"isOutdated":false,"comments":{"nodes":[{"body":"x\n<!-- ai-router-finding key=$KB -->"}]}},
 {"id":"Tres","isResolved":true,"isOutdated":true,"comments":{"nodes":[{"body":"<!-- ai-router-finding key=$KA -->"}]}},
 {"id":"Thum","isResolved":false,"isOutdated":true,"comments":{"nodes":[{"body":"looks good to me"}]}}
]}}}}}
JSON

STUBDIR=$(mktemp -d)
cat > "$STUBDIR/gh" <<'STUB'
#!/usr/bin/env bash
args="$*"
case "$args" in *"repo view"*) echo "o/r"; exit 0 ;; esac
if [[ "$args" == *resolveReviewThread* ]]; then
  for a in "$@"; do case "$a" in id=*) echo "${a#id=}" >> "$GH_RESOLVED" ;; esac; done
  echo '{"data":{"resolveReviewThread":{"thread":{"isResolved":true}}}}'; exit 0
fi
if [[ "$args" == *reviewThreads* ]]; then cat "$GH_THREADS"; exit 0; fi
echo '{}'; exit 0
STUB
chmod +x "$STUBDIR/gh"
export PATH="$STUBDIR:$PATH"

resolved_set() { sort -u "$GH_RESOLVED" 2>/dev/null | tr '\n' ',' ; }

echo "test_resolve_threads.sh"

# --keys [KA]: resolve ONLY Tfix (Tres has KA but already resolved; Toth wrong key; Thum human)
: > "$GH_RESOLVED"; printf '%s\n' "$KA" > "$WORK/keys"
bash "$RT" 1 --keys "$WORK/keys" >/dev/null 2>&1
check "--keys resolves the fixed thread" "grep -qx Tfix \"$GH_RESOLVED\""
check "--keys does NOT resolve other-key" "! grep -qx Toth \"$GH_RESOLVED\""
check "--keys does NOT resolve resolved" "! grep -qx Tres \"$GH_RESOLVED\""
check "--keys NEVER resolves human" "! grep -qx Thum \"$GH_RESOLVED\""

# default (outdated): Tfix only (outdated+ours, unresolved). Toth not outdated; Thum no marker.
: > "$GH_RESOLVED"
bash "$RT" 1 >/dev/null 2>&1
check "default resolves outdated ours" "grep -qx Tfix \"$GH_RESOLVED\""
check "default skips non-outdated" "! grep -qx Toth \"$GH_RESOLVED\""
check "default NEVER resolves human" "! grep -qx Thum \"$GH_RESOLVED\""

# --all: every unresolved ours (Tfix + Toth); never human, never already-resolved.
: > "$GH_RESOLVED"
bash "$RT" 1 --all >/dev/null 2>&1
check "--all resolves Tfix" "grep -qx Tfix \"$GH_RESOLVED\""
check "--all resolves Toth" "grep -qx Toth \"$GH_RESOLVED\""
check "--all NEVER resolves human" "! grep -qx Thum \"$GH_RESOLVED\""
check "--all skips already-resolved" "! grep -qx Tres \"$GH_RESOLVED\""

# --keys with no matching key: resolves nothing
: > "$GH_RESOLVED"; printf 'nomatchxxxxxx\n' > "$WORK/keys"
bash "$RT" 1 --keys "$WORK/keys" >/dev/null 2>&1
check "--keys no-match resolves nothing" "[ ! -s \"$GH_RESOLVED\" ]"

# invalid PR -> usage error
bash "$RT" abc --all >/dev/null 2>&1
check "invalid PR rejected" "[ \$? -eq 2 ]"

echo "  resolve-threads: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
