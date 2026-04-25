---
name: visual-regression
description: Use when comparing the current page against a stored visual baseline. Uses Argos when an Argos token is configured, otherwise falls back to Playwright's built-in toHaveScreenshot.
---

# Visual Regression

You're comparing the current screenshot matrix against an established baseline.

## Decide which engine

- If `${user_config.argosToken}` is set: use Argos. Cloud-hosted baselines, no committed PNGs, GitHub PR check.
- Otherwise: use Playwright's `toHaveScreenshot`. Local PNGs in `__screenshots__/`. Works for solo dev, struggles in teams.

## Argos path

1. Run the responsive sweep first (see `responsive-design-sweep` skill).
2. Run `bash ${CLAUDE_PLUGIN_ROOT}/bin/run-argos-upload.sh <reportDir>`. The script:
   - Reads PNGs from the report directory.
   - Uploads to Argos via `@argos-ci/cli` with `argos upload`.
   - Tags the build with the current git branch and commit SHA.
   - Returns the Argos build URL.
3. If this is the first run on the branch, Argos will auto-mark it as the baseline (or compare against the main-branch baseline if one exists).
4. Wait for the Argos build to complete (typically 30-60s). Poll the Argos API or check the build URL.
5. Pull the diff list. For each diff:
   - Surface the changed image, the % pixel difference, and Argos's AI-generated summary of the change.
   - Severity: 
     - **Blocker:** Difference > 5% on a non-dynamic element (header, hero, footer, primary CTA).
     - **High:** Difference > 1% on any element.
     - **Medium:** Difference > 0.1% on any element.
     - **Nitpicks:** Sub-pixel differences (font rendering, anti-aliasing).

## Playwright fallback path

1. Run the existing Playwright tests with `--reporter=html` and capture the diff.
2. If running for the first time, Playwright will fail with "no baseline found" and write the current screenshot as the baseline. Tell the user to commit the baseline directory.
3. On subsequent runs, Playwright generates `<n>-diff.png` files for each mismatch.
4. Default tolerances:
   - `maxDiffPixelRatio: 0.01` (1% of pixels can differ).
   - `threshold: 0.2` (per-pixel color tolerance).
   - These are stricter than Argos defaults; loosen if false positives are noisy.
5. Surface the diff images and the mismatch ratio.

## Anti-flakiness checklist

Before any screenshot for visual regression:
1. `await page.waitForLoadState('networkidle')`.
2. `await page.evaluate(() => document.fonts.ready)`.
3. Disable animations (CSS injection).
4. Mask known-dynamic regions (timestamps, user avatars, ads): `mask: [page.locator('[data-dynamic]')]` in Playwright.
5. For Argos, the script automatically injects Argos's stabilization helper which masks dynamic content.

## Output

```markdown
## Visual Regression (Argos build #1234)

- Build: https://app.argos-ci.com/stacks-inc/project/builds/1234
- Status: completed in 47s
- Total screenshots compared: 108
- Diffs detected: 6

### Blockers (1)
- `1440-light-default.png` — header logo size changed by 24% (likely accidental). Diff: ...

### High (3)
...

Approve the build in Argos to update the baseline if these changes are intentional.
```
