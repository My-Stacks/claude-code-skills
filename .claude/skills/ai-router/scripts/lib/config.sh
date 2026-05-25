#!/usr/bin/env bash
# Config helpers for ai-router scripts.
# Source from other scripts: . "$SCRIPT_DIR/lib/config.sh"

AI_ROUTER_CONFIG="${AI_ROUTER_CONFIG:-$HOME/.orchestrator-config.json}"

config_path() {
  printf '%s\n' "$AI_ROUTER_CONFIG"
}

config_exists() {
  [[ -r "$AI_ROUTER_CONFIG" ]]
}

# Read a string field from the config; empty string if missing.
# Usage: get_field anthropic_api_key
get_field() {
  local field=$1
  python3 - "$AI_ROUTER_CONFIG" "$field" <<'PY'
import json, sys
try:
    with open(sys.argv[1]) as f:
        cfg = json.load(f)
    v = cfg.get(sys.argv[2], "")
    print(v if v else "")
except Exception:
    print("")
PY
}

# Per-provider key + default-model getters.
anthropic_key()  { get_field anthropic_api_key; }
openai_key()     { get_field openai_api_key; }
gemini_key()     { get_field gemini_api_key; }

default_model() {
  local provider=$1 field
  case "$provider" in
    anthropic) field=default_anthropic_model ;;
    openai)    field=default_openai_model ;;
    gemini)    field=default_gemini_model ;;
    *) return 1 ;;
  esac
  get_field "$field"
}

# Redact a key: first 6 + last 4 chars if long enough, else first 3 + "..."
redact_key() {
  local k=$1
  local n=${#k}
  if (( n > 12 )); then
    printf '%s...%s\n' "${k:0:6}" "${k: -4}"
  elif (( n > 0 )); then
    printf '%s...\n' "${k:0:3}"
  else
    printf -- '-\n'
  fi
}
