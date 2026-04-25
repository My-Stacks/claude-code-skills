#!/usr/bin/env bash
# run-argos-baseline.sh <url>
# Captures a fresh sweep and uploads as a reference build.

set -euo pipefail

URL="${1:?usage: run-argos-baseline.sh <url>}"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
REPORT_DIR=".claude/design-qa/baselines/$TS"

mkdir -p "$REPORT_DIR/screenshots"

echo "[baseline] capturing sweep at $URL..."
DESIGN_QA_REPORT_DIR="$REPORT_DIR" \
bash "$PLUGIN_ROOT/bin/run-sweep.sh" "$URL" "${DESIGN_QA_PRESET:-agency-default}"

echo "[baseline] uploading to Argos as reference..."
DESIGN_QA_ARGOS_REFERENCE=true \
bash "$PLUGIN_ROOT/bin/run-argos-upload.sh" "$REPORT_DIR"

echo "[baseline] done. Mark this build as 'approved' in Argos UI to set as baseline."
