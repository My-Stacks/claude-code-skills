#!/usr/bin/env bash
# run-lighthouse.sh <url>
# Lighthouse runs at mobile + desktop profiles, each in a SEPARATE Node process.
#
# Why two processes: chrome-launcher's state can leak between back-to-back
# launches in the same Node, causing the first profile's categories to come
# back null. Each profile runs cleanly in a fresh process.

set -euo pipefail

URL="${1:?usage: run-lighthouse.sh <url>}"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
REPORT_DIR="${DESIGN_QA_REPORT_DIR:-.claude/design-qa/reports/$(date -u +%Y%m%dT%H%M%SZ)}"

# Don't mkdir at the wrapper layer — run-lighthouse.mjs validates the path
# (rejects anything that escapes the workspace) before creating directories.

echo "[lighthouse] url=${URL%%\?*}"

# Run each profile in its own Node process. Pass DESIGN_QA_REPORT_DIR through
# explicitly so each invocation lands writes in the same place.
for profile in mobile desktop; do
  echo "[lighthouse] starting $profile profile (separate Node process)"
  DESIGN_QA_URL="$URL" \
  DESIGN_QA_BASE_URL="$URL" \
  DESIGN_QA_REPORT_DIR="$REPORT_DIR" \
  DESIGN_QA_BYPASS="${DESIGN_QA_BYPASS:-${VERCEL_AUTOMATION_BYPASS_SECRET:-}}" \
  node "$PLUGIN_ROOT/scripts/run-lighthouse.mjs" --profile "$profile"
done

# Merge the two single-profile result.json files into the shared summary.json
# shape that the reporters consume. The merge step also computes the
# instrumentation-suspect flag (mobile metric / desktop metric > 8 → flag).
echo "[lighthouse] merging mobile + desktop results"
DESIGN_QA_REPORT_DIR="$REPORT_DIR" \
node "$PLUGIN_ROOT/scripts/run-lighthouse.mjs" --merge

echo "[lighthouse] done. reports in $REPORT_DIR/lighthouse/"
