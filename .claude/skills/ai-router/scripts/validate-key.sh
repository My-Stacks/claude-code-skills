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

# Use call-provider.sh with a 16-token "hi" prompt and a short timeout.
# (--max-tokens 1 can falsely reject keys for reasoning models that need
# headroom for the thinking budget.) Capture rc immediately so it can't be
# overwritten by subsequent commands.
rc=0
OUT=$(printf 'hi' | bash "$SCRIPT_DIR/call-provider.sh" "$PROVIDER" --max-tokens 16 --timeout 15 2>&1 >/dev/null) || rc=$?

if (( rc == 0 )); then
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
