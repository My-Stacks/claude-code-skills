#!/usr/bin/env bash
# run-pa11y.sh <url>
# Pa11y scan at the configured breakpoint preset's mobile/tablet/desktop widths.

set -euo pipefail

URL="${1:?usage: run-pa11y.sh <url>}"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
REPORT_DIR="${DESIGN_QA_REPORT_DIR:-.claude/design-qa/reports/$(date -u +%Y%m%dT%H%M%SZ)}"
PRESET="${DESIGN_QA_PRESET:-agency-default}"

# Reject report-dir paths that escape the workspace before any mkdir runs.
RESOLVED_REPORT_DIR="$(node -e '
const p = require("node:path");
const cwd = process.cwd();
const resolved = p.resolve(cwd, process.argv[1]);
if (resolved !== cwd && !resolved.startsWith(cwd + p.sep)) {
  console.error(`DESIGN_QA_REPORT_DIR must stay inside the workspace; got ${resolved}`);
  process.exit(2);
}
process.stdout.write(resolved);
' "$REPORT_DIR")" || exit 1

mkdir -p "$REPORT_DIR/pa11y"

case "$PRESET" in
  fast)            WIDTHS="375 768 1440" ;;
  agency-default)  WIDTHS="375 768 1440" ;;
  thorough)        WIDTHS="375 768 1440 1920" ;;
  *)               WIDTHS="375 768 1440" ;;
esac

echo "[pa11y] url=${URL%%\?*} preset=$PRESET widths=$WIDTHS"

# pa11y has no header CLI flag; pass them via a private config file with mode
# 600 so the bypass secret never lands in the report tree.
PA11Y_CONFIG_ARGS=()
PA11Y_CONFIG_FILE=""
if [ -n "${DESIGN_QA_BYPASS:-}" ]; then
  PA11Y_CONFIG_FILE="$(mktemp -t design-qa-pa11y-config.XXXXXX)"
  trap '[ -n "$PA11Y_CONFIG_FILE" ] && rm -f "$PA11Y_CONFIG_FILE"' EXIT
  # Write via node so the bypass value is JSON-encoded safely.
  BYPASS="$DESIGN_QA_BYPASS" node -e '
    const fs = require("node:fs");
    const cfg = {
      headers: {
        "x-vercel-protection-bypass": process.env.BYPASS,
        "x-vercel-set-bypass-cookie": "true"
      }
    };
    fs.writeFileSync(process.argv[1], JSON.stringify(cfg));
  ' "$PA11Y_CONFIG_FILE"
  PA11Y_CONFIG_ARGS=(--config "$PA11Y_CONFIG_FILE")
fi

for w in $WIDTHS; do
  if [ "$w" -le 600 ]; then h=812; else h=900; fi
  echo "[pa11y] $w..."
  npx pa11y "$URL" \
    --standard WCAG2AA \
    --reporter json \
    --viewport "${w},${h}" \
    "${PA11Y_CONFIG_ARGS[@]}" \
    > "$REPORT_DIR/pa11y/${w}.json" \
    2> "$REPORT_DIR/pa11y/${w}.stderr.log" \
    || echo "  (pa11y exited non-zero — see ${w}.json + ${w}.stderr.log)"
done

echo "[pa11y] done. results in $REPORT_DIR/pa11y/"
