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

# Use call-provider.sh with a 1-token "hi" prompt and a short timeout.
# We only care about exit code + status; suppress text output.
if OUT=$(printf 'hi' | bash "$SCRIPT_DIR/call-provider.sh" "$PROVIDER" --max-tokens 1 --timeout 15 2>&1 >/dev/null); then
  echo 200
  exit 0
fi

rc=$?
# call-provider.sh prints "<provider>: HTTP <code>" on stderr for non-2xx.
STATUS=$(printf '%s\n' "$OUT" | sed -n 's/.*HTTP \([0-9][0-9][0-9]\).*/\1/p' | head -1)
if [[ -n "$STATUS" ]]; then
  echo "$STATUS"
else
  echo "ERROR"
  printf '%s\n' "$OUT" >&2
fi
exit "$rc"
