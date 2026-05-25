# create-client-pdf

Stacks Inc.'s repeatable PDF builder. Markdown in, client-presentable PDF out. Branded for either **Stacklab** or **Stacklist**, same design system either way.

## What you get

- **Cover page** — cream (#f8f7f4) with a 6pt black left rail. Eyebrow → serif title (Georgia) with optional italic burnt-orange accent on the last word → italic serif subtitle → meta grid (Prepared for, Prepared by, Date, Status, plus any custom fields).
- **Body** — Inter sans body, Georgia serif headings, italic burnt-orange numbered-section markers (`## 1 · Name`), bordered italic lede paragraph, four admonition components (callout, canonical, bottom-line, footnote), styled tables with tier-row support and auto-flow for long tables.
- **Footer** — uppercase project mark on the left, page X / Y on the right, on every body page. Project mark auto-reflects the selected brand.

## Quick start

```bash
# default brand from frontmatter
python build.py path/to/doc.md

# override brand
python build.py path/to/doc.md --brand stacklist

# see what's available
python build.py --list-brands
python build.py --list-templates
```

See `SKILL.md` for the full markdown authoring contract and `INSTALL.md` for setup.

## Files

```
create-client-pdf/
├── SKILL.md              skill metadata + authoring contract
├── README.md             this file
├── INSTALL.md            one-time setup
├── requirements.txt      Python deps
├── build.py              CLI + library
├── templates/
│   └── default.html.j2   canonical Stacks layout (cream cover, editorial serif)
├── brands/
│   ├── stacklab.yml      label: Stacklab
│   └── stacklist.yml     label: Stacklist
└── examples/
    ├── test-wade-pov.md
    └── test-competitive.md
```

## Architecture

Two extension points, both auto-discovered. No build.py changes needed to add either.

### Brands (`brands/`)

YAML files. Selecting a brand fills in `prepared_by`, the cover eyebrow, and the per-page footer from the brand's `label`. Today each brand defines just one field:

```yaml
label: "Stacklab"
```

The brand dict is passed into the Jinja template, so future fields (logo path, brand-specific accent color, alt typography) can be added to the YAML and consumed in the template without touching build.py.

### Templates (`templates/`)

Jinja2 files named `<name>.html.j2`. The skill ships with `default`. Future variants (horizontal, clean B&W, single-page summary, etc.) drop in alongside and become available via `--template <name>` or `template: <name>` in frontmatter.

## Brand precedence

Most specific wins:

1. Explicit frontmatter field (`prepared_by: "Custom"`)
2. CLI `--brand` flag
3. Frontmatter `brand:` field
4. No brand applied (those cover fields are simply omitted)

## How it works

`build.py` does six things in order:

1. Parse YAML frontmatter
2. Apply brand defaults (from selected brand → `prepared_by`, `eyebrow`, `footer`)
3. Extract admonition blocks (`> [!type]`) and stash as placeholders
4. Render markdown body through markdown-it-py
5. Reinject admonitions as styled HTML, then transform numbered sections, lede, and tables
6. Substitute into the selected template, then render with headless Chromium (Playwright) to PDF

## Design tokens

| Token | Value | Where it shows up |
|---|---|---|
| Accent | `#7a3d1f` | Italic accent on title, section numerals, callout left rail, list markers |
| Cover bg | `#f8f7f4` | Cover page, callout fill |
| Dark bg | `#0a0a0a` | Bottom-line block, tier rows |
| Dark accent | `#d4b896` | Italic emphasis inside bottom-line block |
| Display font | Georgia | Title, h1/h2, lede, canonical body, callout label |
| Body font | Inter (system fallback) | Everything else |

All live in `templates/default.html.j2`. Edit there, every future deliverable inherits.

## Known limitations

- No automatic em-dash replacement. Per Stacks style, em dashes should be authored as colons or restructured at write time.
- Lede detection looks at the first paragraph only and requires the entire paragraph to be italic.
- Tier rows are detected by the `[tier]` marker as the first non-whitespace content of the first cell in a markdown table.
- Row highlighting and other per-row class targeting require raw HTML inside the markdown.
- Today, brands only control text labels. Brand-specific color or typography would require adding fields to the brand YAML and consuming them in the template.
