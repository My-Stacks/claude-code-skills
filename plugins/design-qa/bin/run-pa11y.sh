#!/usr/bin/env bash
# run-pa11y.sh <url>
# Pa11y scan at the configured breakpoint preset's mobile/tablet/desktop widths.

set -euo pipefail

URL="${1:?usage: run-pa11y.sh <url>}"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
REPORT_DIR="${DESIGN_QA_REPORT_DIR:-.claude/design-qa/reports/$(date -u +%Y%m%dT%H%M%SZ)}"
PRESET="${DESIGN_QA_PRESET:-agency-default}"

mkdir -p "$REPORT_DIR/pa11y"

# Pa11y has its own runtime cost per width, so we scan a small representative
# subset (one mobile, one tablet, one desktop). The widths chosen here line up
# with the labels run-axe.mjs uses, so reporters can correlate findings.
case "$PRESET" in
  fast)            WIDTHS="375 768 1440" ;;
  agency-default)  WIDTHS="375 768 1440" ;;
  thorough)        WIDTHS="375 768 1440 1920" ;;
  *)               WIDTHS="375 768 1440" ;;
esac

echo "[pa11y] url=${URL%%\?*} preset=$PRESET widths=$WIDTHS"

for w in $WIDTHS; do
  if [ "$w" -le 600 ]; then h=812; else h=900; fi
  echo "[pa11y] $w..."
  # Stream pa11y stderr to a sidecar log so missing-browser / network errors
  # are visible — discarding stderr was hiding real failures.
  npx pa11y "$URL" \
    --standard WCAG2AA \
    --reporter json \
    --viewport "${w},${h}" \
    > "$REPORT_DIR/pa11y/${w}.json" \
    2> "$REPORT_DIR/pa11y/${w}.stderr.log" \
    || echo "  (pa11y exited non-zero — see ${w}.json + ${w}.stderr.log)"
done

echo "[pa11y] done. results in $REPORT_DIR/pa11y/"
