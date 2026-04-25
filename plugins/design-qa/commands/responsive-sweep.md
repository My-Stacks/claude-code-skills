---
description: Just the breakpoint screenshot matrix without the full review. Useful for quick visual diffs.
argument-hint: <url>
allowed-tools: Bash, Read, Write, mcp__playwright__*
---

Run only the responsive breakpoint sweep against `$1`.

1. Resolve the breakpoint preset from `${user_config.breakpointPreset}`.
2. Run `bash ${CLAUDE_PLUGIN_ROOT}/bin/run-sweep.sh "$1" "${user_config.breakpointPreset}"`.
3. The script writes screenshots to `.claude/design-qa/reports/<timestamp>/screenshots/` and a manifest at `manifest.json`.
4. After the sweep completes, scan the screenshots for:
   - Horizontal overflow (the script flags this in `manifest.json`).
   - Layout collapses at "grey area" widths (700, 900, 1180).
   - Text truncation, illegible sizes.
5. Report findings as a short markdown table, one row per (width, theme, page) with status: ✅ ok / ⚠️ overflow / ❌ broken.

Do NOT run a11y, Lighthouse, or SEO checks. This is a fast pass.
