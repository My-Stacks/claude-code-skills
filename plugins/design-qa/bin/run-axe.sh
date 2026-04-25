#!/usr/bin/env bash
# run-axe.sh <url>
# Runs axe-core via @axe-core/playwright at multiple widths × themes × interaction states.

set -euo pipefail

URL="${1:?usage: run-axe.sh <url>}"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
REPORT_DIR="${DESIGN_QA_REPORT_DIR:-.claude/design-qa/reports/$(date -u +%Y%m%dT%H%M%SZ)}"

mkdir -p "$REPORT_DIR/axe"

echo "[axe] url=$URL"

DESIGN_QA_URL="$URL" \
DESIGN_QA_REPORT_DIR="$REPORT_DIR" \
DESIGN_QA_BYPASS="${DESIGN_QA_BYPASS:-${VERCEL_AUTOMATION_BYPASS_SECRET:-}}" \
node "$PLUGIN_ROOT/scripts/run-axe.mjs"

echo "[axe] done. results in $REPORT_DIR/axe/"
