#!/usr/bin/env bash
# curl wrapper that captures HTTP status + body separately.
# Source from other scripts: . "$SCRIPT_DIR/lib/http.sh"

# do_post <url> <response-out-path> <timeout-s> <header1> [<header2>...] -- <body-file>
# Writes response body to response-out-path. Prints HTTP status to stdout.
# Returns: 0 on 2xx, 4 on non-2xx HTTP, 5 on curl error/timeout, 64 on bad args.
#
# Headers (including API keys) are passed via a mode-600 curl --config file so
# they never appear in argv and are not visible to local `ps` callers.
do_post() {
  local url=$1 out=$2 timeout=$3
  shift 3

  local cfg
  cfg=$(mktemp "${AI_ROUTER_TMPDIR:-${TMPDIR:-/tmp}}/ai-router-curl.XXXXXX") || {
    echo "do_post: mktemp failed" >&2; return 64
  }
  chmod 600 "$cfg"
  # Cleanup on every return path.
  local _cleanup
  _cleanup="rm -f '$cfg'"
  trap "$_cleanup" RETURN

  while (( $# > 0 )) && [[ "$1" != "--" ]]; do
    # curl config "header" syntax escapes \ and "; safe for keys/version strings.
    local h=${1//\\/\\\\}
    h=${h//\"/\\\"}
    printf 'header = "%s"\n' "$h" >> "$cfg"
    shift
  done
  if [[ "${1:-}" != "--" ]]; then
    echo "do_post: missing -- separator before body file" >&2
    return 64
  fi
  shift
  local body_file=${1:-}
  [[ -n "$body_file" ]] || { echo "do_post: missing body file" >&2; return 64; }

  printf 'header = "content-type: application/json"\n' >> "$cfg"

  local status
  status=$(curl -sS \
    --max-time "$timeout" --connect-timeout 10 \
    -o "$out" -w "%{http_code}" \
    --config "$cfg" \
    -d "@$body_file" \
    "$url" 2>/dev/null) || {
      echo "curl failed (network or timeout)" >&2
      return 5
    }

  printf '%s\n' "$status"
  if [[ "$status" =~ ^2 ]]; then
    return 0
  fi
  return 4
}
