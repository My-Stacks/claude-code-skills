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
2. Severity:
   - **Blocker:** Missing `<title>`, missing canonical on a page that needs one, malformed JSON-LD, missing `<html lang>`.
   - **High:** Missing og:image, og:image broken/wrong size, missing meta description, no viewport meta.
   - **Medium:** Missing Twitter Card, suboptimal title/description length, h1 issues.
   - **Nitpicks:** Title not matching brand pattern, missing favicon variants.
3. Report as markdown with a checklist per category and the actual values pulled from the page.
