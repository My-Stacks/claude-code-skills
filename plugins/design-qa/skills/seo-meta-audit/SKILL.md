---
name: seo-meta-audit
description: Use when validating SEO basics, Open Graph, Twitter Card, JSON-LD, viewport meta, lang attribute, and heading hierarchy on a deployed page. Important for marketing sites and SEO-sensitive client work.
---

# SEO & Meta Audit

You're validating the meta layer of a page: the bits that don't render visually but determine how the page appears in search results, social embeds, and assistive tech.

## How to invoke

`${CLAUDE_PLUGIN_ROOT}/bin/run-seo.sh <url>` — extracts and validates everything below. Output: `.claude/design-qa/reports/<timestamp>/seo/report.json`.

## What's checked

### Title and description
- `<title>` present, length 30–60 chars (Google truncates around 60).
- `<meta name="description">` present, length 70–160 chars.

### Canonical
- `<link rel="canonical">` present and absolute.
- Canonical doesn't point to a different domain unless explicitly intended.

### HTML attributes
- `<html lang="...">` set to a valid BCP 47 code.
- `<meta charset="utf-8">` early in `<head>`.
- `<meta name="viewport" content="width=device-width, initial-scale=1">` (no `user-scalable=no` — that's an a11y violation).

### Open Graph (Facebook, LinkedIn, Slack, Discord)
Required:
- `og:title`
- `og:description`
- `og:image` — verify URL is reachable, MIME is `image/png|jpeg|webp`, dimensions are at minimum 1200×630.
- `og:url`
- `og:type` (`website`, `article`, `product`, etc.)

Recommended:
- `og:site_name`
- `og:locale`

### Twitter Card
- `twitter:card` (`summary` or `summary_large_image`).
- `twitter:title`, `twitter:description`, `twitter:image`.
- If `summary_large_image`, image should be 1200×675 (16:9-ish).

### JSON-LD structured data
The runner (`run-seo.mjs`) parses every `<script type="application/ld+json">` block and reports whether it is valid JSON. Schema.org shape validation (e.g. checking that `Organization` has `name`/`url`/`logo`) is **not** performed automatically today — flag shape violations manually if you spot them in the extracted `data.jsonLd` array.

### Heading hierarchy
- Runner check: count of `<h1>` (zero = high; >1 = high).
- Manual check (not automated): no skipped levels (h1 → h3 without h2), and headings should be descriptive (not just "Welcome" or "About us").

### Images
- Runner check: every `<img>` has an `alt` attribute. Empty `alt=""` is OK for decorative images; missing `alt` is reported as medium.
- Manual check (not automated): decorative SVG icons should be `aria-hidden="true"` or in `<svg role="img"><title>...</title></svg>` form.

### Links
- Runner check: no `target="_blank"` without `rel="noopener"` (security + perf) — reported as medium severity.
- Manual check (not automated): link text descriptive (not "click here" or "read more" without context).

## Severity

- **Blocker:** Missing `<title>`, missing `<html lang>`, malformed JSON-LD, og:image broken.
- **High:** Missing meta description, missing og:image, missing canonical on a content page, missing viewport meta, multiple h1s.
- **Medium:** Missing Twitter Card, suboptimal title/description length, og:image wrong dimensions, missing alt text.
- **Nitpicks:** og:locale missing, JSON-LD missing optional fields, decorative images not marked aria-hidden.

## Output

```markdown
## SEO & Meta

### Required ✅/❌
- Title: ✅ "Acme — Modern accounting for studios" (52 chars)
- Description: ❌ Missing.
- Canonical: ✅ https://acme.com/
- Viewport: ✅
- HTML lang: ✅ en

### Open Graph
- og:title: ✅
- og:description: ❌
- og:image: ⚠️ Present but 800×420 (recommended 1200×630)
- og:url: ✅
- og:type: ✅ website

### Twitter Card: ❌ No twitter meta tags

### JSON-LD: ✅ 1 block valid (Organization)

### Headings: ❌ 2 h1s detected
- "Modern accounting" (hero)
- "Pricing" (section header — should be h2)

### Images: ⚠️ 3 of 14 missing alt
- /assets/hero-bg.png (line 42)
- ...
```
