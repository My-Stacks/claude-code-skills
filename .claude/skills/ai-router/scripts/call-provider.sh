#!/usr/bin/env bash
# call-provider.sh — send a prompt to a single external model API.
#
# Usage:
#   echo "$PROMPT" | bash call-provider.sh <provider> [--model X] [--max-tokens N] [--timeout S]
#
# stdin:   UTF-8 prompt
# stdout:  response text, then "---USAGE---", then JSON usage object
# stderr:  human-readable errors (never the API key)
#
# Exit codes:
#   0  ok
#   2  not configured (missing or empty key)
#   3  missing dependency (curl/jq/python3)
#   4  HTTP non-200
#   5  network/timeout
#  64  usage error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib/config.sh"
. "$SCRIPT_DIR/lib/http.sh"

PROVIDER=""
MODEL=""
MAX_TOKENS=""
TIMEOUT=""

# Defaults — overridden by config + flags.
DEFAULT_MAX_TOKENS_ANTHROPIC=4096
DEFAULT_MAX_TOKENS_OPENAI=16384
DEFAULT_MAX_TOKENS_GEMINI=8192
DEFAULT_TIMEOUT_ANTHROPIC=120
DEFAULT_TIMEOUT_OPENAI=300
DEFAULT_TIMEOUT_GEMINI=120

usage() {
  cat >&2 <<'EOF'
usage: call-provider.sh <anthropic|openai|gemini> [--model ID] [--max-tokens N] [--timeout S]
       prompt is read from stdin
EOF
  exit 64
}

[[ $# -lt 1 ]] && usage
PROVIDER=$1; shift

require_value() {
  local flag=$1 remaining=$2
  (( remaining >= 2 )) || { echo "$flag requires a value" >&2; usage; }
}

while (( $# > 0 )); do
  case "$1" in
    --model)       require_value --model "$#";       MODEL=$2;      shift 2 ;;
    --max-tokens)  require_value --max-tokens "$#";  MAX_TOKENS=$2; shift 2 ;;
    --timeout)     require_value --timeout "$#";     TIMEOUT=$2;    shift 2 ;;
    -h|--help)     usage ;;
    *) echo "unknown flag: $1" >&2; usage ;;
  esac
done

# Validate model name (whitelist).
validate_model() {
  [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "invalid model id: $1" >&2; exit 64; }
}

validate_positive_int() {
  local label=$1 value=$2
  [[ "$value" =~ ^[1-9][0-9]*$ ]] || { echo "$label must be a positive integer, got: $value" >&2; exit 64; }
}

# Dependency check.
for bin in curl python3; do
  command -v "$bin" >/dev/null 2>&1 || { echo "missing dependency: $bin" >&2; exit 3; }
done

# Get key + default model from config.
case "$PROVIDER" in
  anthropic) KEY=$(anthropic_key); [[ -z "$MODEL" ]] && MODEL=$(default_model anthropic);
             [[ -z "$MAX_TOKENS" ]] && MAX_TOKENS=$DEFAULT_MAX_TOKENS_ANTHROPIC
             [[ -z "$TIMEOUT" ]]    && TIMEOUT=$DEFAULT_TIMEOUT_ANTHROPIC ;;
  openai)    KEY=$(openai_key);    [[ -z "$MODEL" ]] && MODEL=$(default_model openai);
             [[ -z "$MAX_TOKENS" ]] && MAX_TOKENS=$DEFAULT_MAX_TOKENS_OPENAI
             [[ -z "$TIMEOUT" ]]    && TIMEOUT=$DEFAULT_TIMEOUT_OPENAI ;;
  gemini)    KEY=$(gemini_key);    [[ -z "$MODEL" ]] && MODEL=$(default_model gemini);
             [[ -z "$MAX_TOKENS" ]] && MAX_TOKENS=$DEFAULT_MAX_TOKENS_GEMINI
             [[ -z "$TIMEOUT" ]]    && TIMEOUT=$DEFAULT_TIMEOUT_GEMINI ;;
  *) echo "unknown provider: $PROVIDER" >&2; usage ;;
esac

[[ -z "$KEY" ]]   && { echo "$PROVIDER: not configured (missing key in $(config_path))" >&2; exit 2; }
[[ -z "$MODEL" ]] && { echo "$PROVIDER: no model in config and none passed via --model" >&2; exit 64; }
validate_model "$MODEL"
validate_positive_int max-tokens "$MAX_TOKENS"
validate_positive_int timeout "$TIMEOUT"

TMPDIR_BASE="${AI_ROUTER_TMPDIR:-${TMPDIR:-/tmp}}"
# BSD mktemp (macOS) rejects templates with characters after the trailing X's
# (`ai-router-body-XXXXXX.json` fails with "too few X's"). Trailing-only X's
# work on both BSD and GNU.
BODY_FILE=$(mktemp "$TMPDIR_BASE/ai-router-body.XXXXXX")
RESP_FILE=$(mktemp "$TMPDIR_BASE/ai-router-resp.XXXXXX")
trap 'rm -f "$BODY_FILE" "$RESP_FILE"' EXIT

# Build request body from stdin via python json.dumps (safe escaping).
python3 "$SCRIPT_DIR/lib/build-body.py" "$PROVIDER" "$MODEL" "$MAX_TOKENS" > "$BODY_FILE"

rc=0
case "$PROVIDER" in
  anthropic)
    STATUS=$(do_post \
      "https://api.anthropic.com/v1/messages" \
      "$RESP_FILE" "$TIMEOUT" \
      "x-api-key: $KEY" "anthropic-version: 2023-06-01" \
      -- "$BODY_FILE") || rc=$?
    ;;
  openai)
    STATUS=$(do_post \
      "https://api.openai.com/v1/chat/completions" \
      "$RESP_FILE" "$TIMEOUT" \
      "Authorization: Bearer $KEY" \
      -- "$BODY_FILE") || rc=$?
    ;;
  gemini)
    STATUS=$(do_post \
      "https://generativelanguage.googleapis.com/v1beta/models/$MODEL:generateContent" \
      "$RESP_FILE" "$TIMEOUT" \
      "x-goog-api-key: $KEY" \
      -- "$BODY_FILE") || rc=$?
    ;;
esac

if (( rc != 0 )); then
  if [[ -s "$RESP_FILE" ]]; then
    echo "$PROVIDER: HTTP $STATUS" >&2
    head -c 500 "$RESP_FILE" >&2
    echo >&2
  fi
  exit "$rc"
fi

# Parse response by provider. Use .get() chains so safety-blocked responses,
# empty choices, or error-shaped 2xx payloads degrade gracefully to empty text
# rather than crashing with KeyError/IndexError.
python3 - "$PROVIDER" "$MODEL" "$RESP_FILE" <<'PY'
import json, sys

provider, model, resp_path = sys.argv[1:]
try:
    with open(resp_path) as f:
        r = json.load(f)
except Exception as e:
    print(f"{provider}: response not valid JSON ({e})", file=sys.stderr)
    sys.exit(4)

text = ""
usage = {"input": 0, "output": 0}

if provider == "anthropic":
    blocks = r.get("content") or []
    text = "".join(b.get("text", "") for b in blocks if isinstance(b, dict) and b.get("type") == "text")
    u = r.get("usage") or {}
    usage = {"input": u.get("input_tokens", 0), "output": u.get("output_tokens", 0)}
elif provider == "openai":
    choices = r.get("choices") or []
    if choices:
        msg = (choices[0] or {}).get("message") or {}
        text = msg.get("content") or ""
    u = r.get("usage") or {}
    usage = {"input": u.get("prompt_tokens", 0), "output": u.get("completion_tokens", 0)}
elif provider == "gemini":
    cands = r.get("candidates") or []
    if cands:
        parts = ((cands[0] or {}).get("content") or {}).get("parts") or []
        text = "".join(p.get("text", "") for p in parts if isinstance(p, dict))
    u = r.get("usageMetadata") or {}
    usage = {"input": u.get("promptTokenCount", 0), "output": u.get("candidatesTokenCount", 0)}
else:
    print(f"unknown provider in parser: {provider}", file=sys.stderr)
    sys.exit(64)

if not text:
    finish = ""
    if provider == "openai" and (r.get("choices") or []):
        finish = ((r["choices"][0] or {}).get("finish_reason")) or ""
    elif provider == "anthropic":
        finish = r.get("stop_reason") or ""
    elif provider == "gemini" and (r.get("candidates") or []):
        finish = ((r["candidates"][0] or {}).get("finishReason")) or ""
    print(f"{provider}: empty response text (finish_reason={finish!r}); shape may be safety-blocked or error envelope returned as 2xx", file=sys.stderr)
    # Still exit 0 — caller can decide whether empty text is acceptable.

usage["provider"] = provider
usage["model"] = model

sys.stdout.write(text)
if not text.endswith("\n"):
    sys.stdout.write("\n")
sys.stdout.write("---USAGE---\n")
sys.stdout.write(json.dumps(usage) + "\n")
PY
