#!/usr/bin/env bash
# resolve-threads.sh — resolve ai-router's own inline review threads on a PR.
#
# Usage: bash resolve-threads.sh <pr-number> [--all]
#   default : resolve only OUTDATED ai-router threads — the code they point at has
#             changed since (the finding was almost certainly addressed). This is
#             the re-review hygiene path: stale threads don't pile up across pushes.
#   --all   : resolve ALL unresolved ai-router threads (manual cleanup).
#
# Only threads whose first comment carries the `<!-- ai-router-finding -->` marker
# are ever touched, so human threads are never resolved. Uses the GraphQL API —
# the REST API cannot resolve review threads.
#
# Exit codes:
#   0  ok (including nothing to resolve)
#   2  bad args
#   3  missing dependency (gh / jq)
#  10  a GraphQL call failed

set -euo pipefail

# Prefix match — identifies ai-router's own threads whether the marker is the
# old generic form or the new keyed form (`<!-- ai-router-finding key=... -->`).
MARKER='<!-- ai-router-finding'

[[ $# -ge 1 ]] || { echo "usage: resolve-threads.sh <pr-number> [--all | --keys <file>]" >&2; exit 2; }
PR=$1; shift
[[ "$PR" =~ ^[1-9][0-9]*$ ]] || { echo "invalid PR number: $PR" >&2; exit 2; }

# MODE: outdated (default, manual hygiene) | all (manual) | keys (precise — used
# by fix-findings to resolve exactly the threads it verified-fixed).
MODE=outdated
KEYFILE=""
while (( $# > 0 )); do
  case "$1" in
    --all)  MODE=all; shift ;;
    --keys) MODE=keys; KEYFILE=${2:-}; shift 2 ;;
    *) echo "unknown flag: $1 (use --all or --keys <file>)" >&2; exit 2 ;;
  esac
done
[[ "$MODE" != "keys" || -r "$KEYFILE" ]] || { echo "--keys file unreadable: $KEYFILE" >&2; exit 2; }
command -v gh >/dev/null 2>&1 || { echo "missing dependency: gh" >&2; exit 3; }
command -v jq >/dev/null 2>&1 || { echo "missing dependency: jq" >&2; exit 3; }

REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
[[ "$REPO" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || { echo "invalid repo: $REPO" >&2; exit 2; }
OWNER=${REPO%/*}
NAME=${REPO#*/}

READ_Q='query($owner:String!,$name:String!,$pr:Int!,$cursor:String){
  repository(owner:$owner,name:$name){
    pullRequest(number:$pr){
      reviewThreads(first:100,after:$cursor){
        pageInfo{ hasNextPage endCursor }
        nodes{ id isResolved isOutdated comments(first:1){ nodes{ body } } }
      }
    }
  }
}'

# Paginate all review threads into one array.
threads='[]'
cursor=""
while :; do
  if [[ -z "$cursor" ]]; then
    page=$(gh api graphql -f query="$READ_Q" -f owner="$OWNER" -f name="$NAME" -F pr="$PR") \
      || { echo "resolve-threads.sh: GraphQL read failed" >&2; exit 10; }
  else
    page=$(gh api graphql -f query="$READ_Q" -f owner="$OWNER" -f name="$NAME" -F pr="$PR" -f cursor="$cursor") \
      || { echo "resolve-threads.sh: GraphQL read failed" >&2; exit 10; }
  fi
  nodes=$(jq '.data.repository.pullRequest.reviewThreads.nodes' <<<"$page")
  threads=$(jq -n --argjson a "$threads" --argjson b "$nodes" '$a + $b')
  [[ "$(jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage' <<<"$page")" == "true" ]] || break
  cursor=$(jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.endCursor' <<<"$page")
done

# Select unresolved ai-router (marker) threads per mode:
#   keys     — only threads whose marker key is in KEYFILE (the precise, verified
#              path: exactly the findings fix-findings applied + tested).
#   all      — every ai-router thread (manual cleanup).
#   outdated — only stale ones GitHub flagged isOutdated (manual hygiene).
case "$MODE" in
  keys)
    keys_json=$(jq -R . "$KEYFILE" | jq -s 'map(select(length > 0))')
    ids=$(jq -r --arg m "$MARKER" --argjson keys "$keys_json" \
      '[.[]
        | select(.isResolved | not)
        | (.comments.nodes[0].body // "") as $b
        | select($b | contains($m))
        | select(any($keys[]; . as $k | $b | contains("key=" + $k)))
        | .id] | .[]' <<<"$threads")
    ;;
  all)
    ids=$(jq -r --arg m "$MARKER" \
      '[.[] | select(.isResolved | not) | select((.comments.nodes[0].body // "") | contains($m)) | .id] | .[]' <<<"$threads")
    ;;
  *)
    ids=$(jq -r --arg m "$MARKER" \
      '[.[] | select(.isResolved | not) | select(.isOutdated) | select((.comments.nodes[0].body // "") | contains($m)) | .id] | .[]' <<<"$threads")
    ;;
esac

MUT='mutation($id:ID!){ resolveReviewThread(input:{threadId:$id}){ thread{ isResolved } } }'
count=0
while IFS= read -r tid; do
  [[ -z "$tid" ]] && continue
  if gh api graphql -f query="$MUT" -f id="$tid" >/dev/null; then
    count=$((count + 1))
  else
    echo "resolve-threads.sh: failed to resolve thread $tid" >&2
  fi
done <<<"$ids"

echo "resolved $count ai-router thread(s) on PR #$PR (mode: $MODE)"
