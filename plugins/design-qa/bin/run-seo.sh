#!/usr/bin/env bash
# run-seo.sh <url>
# Validates SEO basics: title, meta description, OG, Twitter Card, JSON-LD, headings, alt text.

set -euo pipefail

URL="${1:?usage: run-seo.sh <url>}"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
REPORT_DIR="${DESIGN_QA_REPORT_DIR:-.claude/design-qa/reports/$(date -u +%Y%m%dT%H%M%SZ)}"

mkdir -p "$REPORT_DIR/seo"

DESIGN_QA_URL="$URL" \
DESIGN_QA_BASE_URL="$URL" \
DESIGN_QA_REPORT_DIR="$REPORT_DIR" \
DESIGN_QA_BYPASS="${DESIGN_QA_BYPASS:-${VERCEL_AUTOMATION_BYPASS_SECRET:-}}" \
node "$PLUGIN_ROOT/scripts/run-seo.mjs"
