#!/usr/bin/env bash
# validate-key.sh — minimal API call to verify a provider's key.
#
# Usage: bash validate-key.sh <anthropic|openai|gemini>
# stdout: HTTP status code (e.g. "200") or "ERROR"
# stderr: human-readable error
# exit 0 on HTTP 2xx, non-zero otherwise.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ $# -eq 1 ]] || { echo "usage: validate-key.sh <provider>" >&2; exit 64; }
PROVIDER=$1

# Use call-provider.sh with a small "hi" prompt and a short timeout. Thinking
# models (Opus 5, Gemini 3.6 Flash) spend the budget on reasoning and may return
# a 2xx with empty text — call-provider exits 6 for that, which still proves the
# key: only the HTTP status matters here. Capture rc immediately so it can't be
# overwritten by subsequent commands.
rc=0
# Redirect order: `2>&1 >/dev/null` is INTENTIONAL (and order-sensitive).
# Shell processes redirects left-to-right:
#   1. `2>&1` → stderr is duplicated to wherever stdout currently points,
#      i.e. into the $(...) capture.
#   2. `>/dev/null` → stdout is then redirected to /dev/null, severing the
#      captured pipe — so the response body (we don't care about it here)
#      is discarded while error messages still reach $OUT.
# Swapping to `>/dev/null 2>&1` would discard BOTH and we'd lose the HTTP
# status line we parse out of stderr below.
OUT=$(printf 'hi' | bash "$SCRIPT_DIR/call-provider.sh" "$PROVIDER" --max-tokens 256 --timeout 30 2>&1 >/dev/null) || rc=$?

if (( rc == 0 || rc == 6 )); then   # 6 = 2xx but empty text (thinking ate the budget) — key is valid
  echo 200
  exit 0
fi

# call-provider.sh prints "<provider>: HTTP <code>" on stderr for non-2xx.
STATUS=$(printf '%s\n' "$OUT" | sed -n 's/.*HTTP \([0-9][0-9][0-9]\).*/\1/p' | head -1)
if [[ -n "$STATUS" ]]; then
  echo "$STATUS"
else
  echo "ERROR"
  printf '%s\n' "$OUT" >&2
fi
exit "$rc"
