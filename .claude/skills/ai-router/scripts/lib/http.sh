#!/usr/bin/env bash
# curl wrapper that captures HTTP status + body separately.
# Source from other scripts: . "$SCRIPT_DIR/lib/http.sh"

# do_post <url> <response-out-path> <timeout-s> <header1> [<header2>...] -- <body-file>
# Writes response body to response-out-path. Prints HTTP status to stdout.
# Returns: 0 on 2xx, 4 on non-2xx HTTP, 5 on curl error/timeout.
do_post() {
  local url=$1 out=$2 timeout=$3
  shift 3

  local headers=()
  while (( $# > 0 )) && [[ "$1" != "--" ]]; do
    headers+=(-H "$1")
    shift
  done
  if [[ "${1:-}" != "--" ]]; then
    echo "do_post: missing -- separator before body file" >&2
    return 64
  fi
  shift
  local body_file=$1

  local status
  status=$(curl -sS \
    --max-time "$timeout" --connect-timeout 10 \
    -o "$out" -w "%{http_code}" \
    "${headers[@]}" \
    -H "content-type: application/json" \
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
