#!/usr/bin/env bash
# test_config.sh — config.sh getters, focused on openai_reasoning_effort.
# The escape hatch matters: `off`/`none` must print NOTHING so build-body.py
# omits `reasoning_effort`, which non-reasoning models (gpt-4o, gpt-4.1) reject
# with a 400. Also asserts the function never returns non-zero — call-provider.sh
# runs under `set -euo pipefail` and calls it in an `&&` list — so the probe shells
# below enable `set -euo pipefail` too, to actually reproduce that context.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$HERE/../scripts/lib"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); }
bad(){ FAIL=$((FAIL+1)); echo "  ✗ $1"; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
CFG="$WORK/config.json"

# effort <json-value> -> prints resolved effort; sets EFF_RC / EFF_ERR
effort() {
  printf '{"openai_reasoning_effort": %s}\n' "$1" > "$CFG"
  EFF_OUT=$(AI_ROUTER_CONFIG="$CFG" bash -c 'set -euo pipefail; . "$1"/config.sh; openai_reasoning_effort' _ "$LIB" 2>"$WORK/err")
  EFF_RC=$?
  EFF_ERR=$(cat "$WORK/err")
}

expect() { # expect <json> <want-effort> <want-stderr-nonempty:0|1> <label>
  effort "$1"
  if [[ "$EFF_OUT" != "$2" ]]; then bad "$4: effort='$EFF_OUT' want='$2'"; return; fi
  if (( EFF_RC != 0 )); then bad "$4: rc=$EFF_RC want 0 (set -e safety)"; return; fi
  if (( $3 == 1 )) && [[ -z "$EFF_ERR" ]]; then bad "$4: expected a stderr warning"; return; fi
  if (( $3 == 0 )) && [[ -n "$EFF_ERR" ]]; then bad "$4: unexpected stderr: $EFF_ERR"; return; fi
  ok
}

# Valid values pass through untouched.
expect '"low"'    low    0 "low passes through"
expect '"medium"' medium 0 "medium passes through"
expect '"high"'   high   0 "high passes through"

# Unset / null / empty fall back to the documented default, silently.
expect '""'   medium 0 "empty string -> medium"
expect 'null' medium 0 "null -> medium"

# THE ESCAPE HATCH: off/none must yield empty, not medium.
expect '"off"'  "" 0 "off -> empty (omit path)"
expect '"none"' "" 0 "none -> empty (omit path)"

# Typos warn on stderr instead of being silently swallowed.
expect '"hihg"'      medium 1 "typo warns + falls back"
expect '"xhigh"'     medium 1 "unsupported-for-openai warns"
expect '"MEDIUM"'    medium 1 "wrong case warns (not silently accepted)"

# Missing key entirely (no field at all) -> medium.
echo '{}' > "$CFG"
out=$(AI_ROUTER_CONFIG="$CFG" bash -c 'set -euo pipefail; . "$1"/config.sh; openai_reasoning_effort' _ "$LIB" 2>/dev/null)
if [[ "$out" == "medium" ]]; then ok; else bad "absent key -> medium (got '$out')"; fi

# Unreadable config -> medium, no crash.
out=$(AI_ROUTER_CONFIG="$WORK/nope.json" bash -c 'set -euo pipefail; . "$1"/config.sh; openai_reasoning_effort' _ "$LIB" 2>/dev/null)
if [[ "$out" == "medium" ]]; then ok; else bad "missing config -> medium (got '$out')"; fi

# End-to-end: `off` must produce a body with NO reasoning_effort key.
printf '{"openai_reasoning_effort": "off"}\n' > "$CFG"
E=$(AI_ROUTER_CONFIG="$CFG" bash -c 'set -euo pipefail; . "$1"/config.sh; openai_reasoning_effort' _ "$LIB")
BODY=$(echo "prompt" | python3 "$LIB/build-body.py" openai gpt-4o 100 "$E")
if echo "$BODY" | grep -q reasoning_effort; then
  bad "off: body still carries reasoning_effort: $BODY"
else ok; fi

# End-to-end: `medium` must produce a body WITH reasoning_effort.
printf '{"openai_reasoning_effort": "medium"}\n' > "$CFG"
E=$(AI_ROUTER_CONFIG="$CFG" bash -c 'set -euo pipefail; . "$1"/config.sh; openai_reasoning_effort' _ "$LIB")
BODY=$(echo "prompt" | python3 "$LIB/build-body.py" openai gpt-5.6-sol 100 "$E")
if echo "$BODY" | grep -q '"reasoning_effort":"medium"'; then ok
else bad "medium: body missing reasoning_effort: $BODY"; fi

# Anthropic/Gemini never receive the field regardless of config.
for prov in anthropic gemini; do
  BODY=$(echo "prompt" | python3 "$LIB/build-body.py" "$prov" some-model 100 "")
  if echo "$BODY" | grep -q reasoning_effort; then
    bad "$prov body carries reasoning_effort"; else ok; fi
done

echo "  config: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
