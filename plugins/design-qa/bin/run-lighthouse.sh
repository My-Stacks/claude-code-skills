#!/usr/bin/env bash
# run-lighthouse.sh <url>
# Lighthouse runs at mobile + desktop profiles.

set -euo pipefail

URL="${1:?usage: run-lighthouse.sh <url>}"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
REPORT_DIR="${DESIGN_QA_REPORT_DIR:-.claude/design-qa/reports/$(date -u +%Y%m%dT%H%M%SZ)}"

mkdir -p "$REPORT_DIR/lighthouse/mobile" "$REPORT_DIR/lighthouse/desktop"

echo "[lighthouse] url=$URL"

DESIGN_QA_URL="$URL" \
DESIGN_QA_BASE_URL="$URL" \
DESIGN_QA_REPORT_DIR="$REPORT_DIR" \
DESIGN_QA_BYPASS="${DESIGN_QA_BYPASS:-${VERCEL_AUTOMATION_BYPASS_SECRET:-}}" \
node "$PLUGIN_ROOT/scripts/run-lighthouse.mjs"

echo "[lighthouse] done. reports in $REPORT_DIR/lighthouse/"
