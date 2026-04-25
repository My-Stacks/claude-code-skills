#!/usr/bin/env bash
# run-playwright-baseline.sh <url>
# Captures Playwright screenshot baselines using toHaveScreenshot as the Argos fallback.

set -euo pipefail

URL="${1:?usage: run-playwright-baseline.sh <url>}"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# Validate URL scheme — Playwright will accept it, but reject obviously wrong inputs early
case "$URL" in
  http://*|https://*) ;;
  *) echo "[baseline] error: URL must start with http:// or https://" >&2; exit 1 ;;
esac

echo "[baseline] capturing Playwright baselines for ${URL%%\?*}..."

TEST_DIR=".claude/design-qa/playwright-tests"
mkdir -p "$TEST_DIR"

# Quoted heredoc — nothing in this block is interpolated by the shell, so $URL
# never reaches the generated TypeScript. The spec reads the URL from env at
# runtime instead, which closes the code-injection vector.
cat > "$TEST_DIR/baseline.spec.ts" <<'EOF'
import { test, expect } from '@playwright/test';

const widths = [375, 768, 1024, 1440, 1920];
const url = process.env.DESIGN_QA_BASELINE_URL;
if (!url) throw new Error('DESIGN_QA_BASELINE_URL must be set');

for (const w of widths) {
  test(`baseline @ ${w}px`, async ({ page }) => {
    await page.setViewportSize({ width: w, height: Math.round(w * 0.625) });
    await page.goto(url, { waitUntil: 'networkidle' });
    await page.evaluate(() => document.fonts.ready);
    await page.addStyleTag({
      content: '*,*::before,*::after { animation-duration: 0s !important; transition-duration: 0s !important; }'
    });
    await page.waitForTimeout(200);
    await expect(page).toHaveScreenshot(`${w}.png`, { fullPage: true, maxDiffPixelRatio: 0.01 });
  });
}
EOF

DESIGN_QA_BASELINE_URL="$URL" \
npx playwright test "$TEST_DIR/baseline.spec.ts" --update-snapshots=missing --reporter=list

echo "[baseline] done. Baselines stored under $TEST_DIR/__screenshots__/"
echo "[baseline] commit these to git so the team shares the baseline."
