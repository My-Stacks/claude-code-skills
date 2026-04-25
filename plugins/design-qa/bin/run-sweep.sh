#!/usr/bin/env bash
# run-sweep.sh <url> <preset>
# Runs the breakpoint screenshot matrix and writes screenshots + manifest.json
# to .claude/design-qa/reports/<timestamp>/screenshots/

set -euo pipefail

URL="${1:?usage: run-sweep.sh <url> [preset]}"
PRESET="${2:-agency-default}"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
REPORT_DIR=".claude/design-qa/reports/$TS"

mkdir -p "$REPORT_DIR/screenshots"

echo "[sweep] url=$URL preset=$PRESET"
echo "[sweep] writing to $REPORT_DIR"

DESIGN_QA_URL="$URL" \
DESIGN_QA_PRESET="$PRESET" \
DESIGN_QA_REPORT_DIR="$REPORT_DIR" \
DESIGN_QA_BYPASS="${DESIGN_QA_BYPASS:-${VERCEL_AUTOMATION_BYPASS_SECRET:-}}" \
node "$PLUGIN_ROOT/scripts/breakpoint-sweep.mjs"

echo "[sweep] done. report at $REPORT_DIR"
