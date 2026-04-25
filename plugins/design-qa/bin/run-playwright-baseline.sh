#!/usr/bin/env bash
# run-playwright-baseline.sh <url>
# Captures Playwright screenshot baselines using toHaveScreenshot as the Argos fallback.

set -euo pipefail

URL="${1:?usage: run-playwright-baseline.sh <url>}"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

echo "[baseline] capturing Playwright baselines for $URL..."

# Generate a temp test file that uses the project's playwright.config or a default
TEST_DIR=".claude/design-qa/playwright-tests"
mkdir -p "$TEST_DIR"
cat > "$TEST_DIR/baseline.spec.ts" <<EOF
import { test, expect } from '@playwright/test';

const widths = [375, 768, 1024, 1440, 1920];
const url = '$URL';

for (const w of widths) {
  test(\`baseline @ \${w}px\`, async ({ page }) => {
    await page.setViewportSize({ width: w, height: Math.round(w * 0.625) });
    await page.goto(url, { waitUntil: 'networkidle' });
    await page.evaluate(() => document.fonts.ready);
    await page.addStyleTag({
      content: '*,*::before,*::after { animation-duration: 0s !important; transition-duration: 0s !important; }'
    });
    await page.waitForTimeout(200);
    await expect(page).toHaveScreenshot(\`\${w}.png\`, { fullPage: true, maxDiffPixelRatio: 0.01 });
  });
}
EOF

npx playwright test "$TEST_DIR/baseline.spec.ts" --update-snapshots=missing --reporter=list

echo "[baseline] done. Baselines stored under $TEST_DIR/__screenshots__/"
echo "[baseline] commit these to git so the team shares the baseline."
