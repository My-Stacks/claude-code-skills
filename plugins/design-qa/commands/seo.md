---
description: SEO, Open Graph, Twitter Card, and JSON-LD validation.
argument-hint: <url>
allowed-tools: Bash, Read, Write, mcp__playwright__*
---

Run SEO/meta checks against `$1`.

1. Run `bash ${CLAUDE_PLUGIN_ROOT}/bin/run-seo.sh "$1"`. The script:
   - Navigates to the URL and extracts all `<meta>` tags, `<link rel="canonical">`, `<html lang>`, `<title>`, and JSON-LD blocks.
   - Validates Open Graph completeness (title, description, image, url, type).
   - Validates Twitter Card (card type, title, image).
   - Fetches the og:image URL and verifies it exists, is the right MIME type, and meets recommended dimensions (1200×630 for og:image, 1200×675 for Twitter summary_large_image).
   - Parses each JSON-LD block. Validates against schema.org shapes (Organization, WebSite, Article, Product, BreadcrumbList — pick based on `@type`).
   - Checks viewport meta correctness (`width=device-width, initial-scale=1`).
   - Checks heading hierarchy (one h1, no skipped levels).
   - Checks alt text presence for all `<img>` tags (empty alt OK for decorative).
   - Outputs `.claude/design-qa/reports/<timestamp>/seo/report.json`.
2. Severity (matches what `run-seo.mjs` actually emits):
   - **Blocker:** Missing `<title>`, missing `<html lang>`, malformed JSON-LD.
   - **High:** Missing meta description, missing canonical, missing viewport meta (or `user-scalable=no`), missing `og:image`, `og:image` not reachable, missing or multiple `<h1>`.
   - **Medium:** Suboptimal title/description length, missing Twitter card, missing other OG tags, images without `alt`, `target="_blank"` links missing `rel="noopener"`.
   - **Nitpicks:** none emitted by the runner today; flag manually if you spot brand-pattern misses or missing favicon variants.
3. Report as markdown with a checklist per category and the actual values pulled from the page.
