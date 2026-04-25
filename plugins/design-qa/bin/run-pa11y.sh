#!/usr/bin/env bash
# run-pa11y.sh <url>
# Pa11y scan at the same widths as run-axe.

set -euo pipefail

URL="${1:?usage: run-pa11y.sh <url>}"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
REPORT_DIR="${DESIGN_QA_REPORT_DIR:-.claude/design-qa/reports/$(date -u +%Y%m%dT%H%M%SZ)}"

mkdir -p "$REPORT_DIR/pa11y"

echo "[pa11y] url=$URL"

for w in 375 768 1440; do
  echo "[pa11y] $w..."
  npx pa11y "$URL" \
    --standard WCAG2AA \
    --reporter json \
    --viewport "${w},$([ "$w" -le 600 ] && echo 812 || echo 900)" \
    > "$REPORT_DIR/pa11y/${w}.json" 2>/dev/null || echo "  (pa11y exited non-zero — see ${w}.json)"
done

echo "[pa11y] done. results in $REPORT_DIR/pa11y/"
