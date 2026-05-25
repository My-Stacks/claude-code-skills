---
name: create-client-pdf
version: "1.2.1"
description: "Convert a Markdown file with YAML frontmatter into a client-presentable PDF, branded for either Stacklab or Stacklist. Letter-sized with a cream cover page, editorial serif headings, an optional dark bottom-line closer, and a brand-aware footer."
trigger: "when the user asks to create a client PDF, Stacklab PDF, or Stacklist PDF; turn markdown into a client deliverable; produce a client-facing POV, competitive landscape, strategy memo, or briefing; or points at a markdown file destined for a client meeting"
---

## Version Check
To check for updates: `curl -s https://raw.githubusercontent.com/My-Stacks/claude-code-skills/refs/heads/main/versions.yaml`
Compare against this file's version in frontmatter.

# create-client-pdf

A repeatable skill that turns a Markdown file with YAML frontmatter into a client-presentable PDF, branded for either **Stacklab** or **Stacklist**.

## When to use this skill

For any markdown destined to be opened in front of a client or sent as a deliverable:

- Strategy POVs and working-session docs
- Competitive landscapes and prompt analyses
- Briefings, memos, and one-pagers

Do NOT use for internal scratch notes, README files, or technical documentation.

## Usage

```bash
python build.py path/to/doc.md
python build.py path/to/doc.md --brand stacklist        # override brand
python build.py path/to/doc.md --output out.pdf
python build.py path/to/doc.md --template default       # select template
python build.py --list-brands
python build.py --list-templates
```

The output PDF is written next to the input file. If frontmatter contains `filename:`, that name is used.

## Brand selection

The skill ships with two brands. Selecting one fills in the wordmark across the cover, the "Prepared by" field, and the footer. The design system (typography, color, layout) is the same for both.

| Brand | Label rendered |
|---|---|
| `stacklab` | Stacklab |
| `stacklist` | Stacklist |

**To pick a brand**, set it in frontmatter:

```yaml
---
brand: stacklab
project: "Move with WADE"
title_main: "Website Redesign"
title_accent: "POV"
---
```

Or override per-build via CLI:

```bash
python build.py doc.md --brand stacklist
```

**What the brand auto-populates** (only if you don't set the field explicitly):

| Field | Derived value |
|---|---|
| `prepared_by` | `Stacklab` (the brand label) |
| `eyebrow` | `{project} · Stacklab` if `project` is set, else just `Stacklab` |
| `footer` | `{project} · {title} · Prepared by Stacklab` |

Explicit fields always win. If you set `prepared_by: "Stacklab, with Beacon"` in frontmatter, that's what renders.

## Markdown authoring contract

### Frontmatter (the cover page)

```yaml
---
brand: stacklab                                # stacklab | stacklist
project: "Move with WADE"                      # engagement / client; used in eyebrow + footer
title_main: "Competitive Landscape & Prompt"   # main title (Georgia serif)
title_accent: "Targets"                        # optional italic burnt-orange accent
subtitle: "Companion to the Website Redesign POV"
prepared_for: "WADE Advisory · working session"
date: "May 17, 2026"
status: "Directional · built on live AI-visibility data"
meta:                                          # optional extra cover key/values
  - label: "Data window"
    value: "Apr 17 – May 17, 2026"
  - label: "Engines"
    value: "ChatGPT · Perplexity · Google AI Overview"
filename: "output.pdf"                         # optional; otherwise derived from title
template: "default"                            # optional; default is "default"
---
```

All fields are optional. `brand` is recommended; `project` is recommended when you want the eyebrow and footer to mention the engagement.

### Numbered sections

`## 1 · Section name` renders with an italic burnt-orange numeral marker. Pattern: `## <digits> · <name>`. The middle dot character is required.

### Lede paragraph

The first paragraph after the H1, if wrapped entirely in italics (`*...*` or `_..._`), renders as a bordered serif lede block.

### Admonition blocks

GitHub-style admonitions, four types:

```markdown
> [!callout]
> **The resolution:** Mystery for humans. Clarity for machines.

> [!canonical] Canonical sentence · citable, machine-first
> "WADE Advisory is an operator-led advisory firm for..."

> [!bottom-line] Bottom line for the redesign
> The category is wide open.

> [!footnote]
> Methodology: Peec AI brand-visibility tracking, 30-day window...
```

| Admonition | Visual | When to use |
|---|---|---|
| `callout` | Cream bg, burnt-orange left rail | Pull quotes, rules, key resolutions |
| `canonical` | Bordered box with uppercase label | Canonical statements, citable sentences |
| `bottom-line` | Dark inverted block | Closing "so what" of a doc |
| `footnote` | Hairline + small italic gray | Methodology, sources, fine print |

### Tables

Standard markdown tables. Two extensions:

**Tier separator rows** (for grouped tables like Tier 1 / Tier 2 / Tier 3):

```markdown
| # | Prompt | Volume |
|---|--------|--------|
| [tier] Tier 1 · Anchor *· own these first* |||
| 1 | First prompt | High |
```

**Auto-flow** — tables with more than 6 body rows automatically break across pages with the column header repeated.

For row highlighting or other one-off styling, drop in raw HTML inside the markdown.

## Input trust boundary

Raw HTML in the markdown is rendered **as-is** (`html=True` + `body|safe`) — this is what enables row-highlighting and one-off styling. Consequently this skill is designed for **markdown you author or curate**, not adversarial input. Inline styles in the source apply; **scripts do not execute** (the renderer runs with JavaScript disabled). As a safety net the renderer also blocks all network requests and restricts local-file access to the document's own temporary render directory, so a malicious doc cannot exfiltrate via remote subresources or include arbitrary local files (e.g. `file:///etc/passwd`). If you must process untrusted client-supplied markdown, sanitize it first (e.g. strip/allowlist HTML).

## Template extensibility

Templates live in `templates/` as Jinja2 files. The skill ships with one:

| Template | Layout |
|---|---|
| `default` | Letter portrait, cream cover with left rail, editorial serif |

To add a new template later (horizontal, clean B&W, etc.):

1. Drop `templates/<name>.html.j2` in the folder. Use `templates/default.html.j2` as a starting point.
2. Reference it via frontmatter (`template: <name>`) or CLI (`--template <name>`).

No build.py changes required. The skill auto-discovers templates.

## Brand extensibility

Brands live in `brands/` as YAML files. The skill ships with two (`stacklab.yml`, `stacklist.yml`), each defining a single `label:` field for now.

To add a new brand:

1. Drop `brands/<name>.yml` with at minimum `label: "Display Name"`.
2. Reference it via frontmatter (`brand: <name>`) or CLI (`--brand <name>`).

To extend what a brand controls (e.g. brand-specific accent color, logo path):

1. Add the new field to the brand YAML.
2. Update `templates/default.html.j2` to consume it. Today only `label` is read by `build.py` and surfaced via `prepared_by` / `eyebrow` / `footer`; the full brand dict is **not** yet exposed to the template. Wiring additional brand fields through to the template (passing the brand dict into `template.render`) is a small follow-up in `build_html`.

## Files

```text
create-client-pdf/
├── SKILL.md              this file
├── README.md             usage notes + design tokens
├── INSTALL.md            setup steps
├── requirements.txt      Python deps
├── build.py              CLI + library (build_pdf() importable)
├── templates/
│   └── default.html.j2   the canonical Stacks layout
├── brands/
│   ├── stacklab.yml
│   └── stacklist.yml
└── examples/
    ├── test-wade-pov.md
    └── test-competitive.md
```

## Examples

See `examples/`:

- `test-wade-pov.md` — brand + project, numbered sections, canonical box, bottom-line
- `test-competitive.md` — brand + project, flowing table with tier rows, methodology footnote

## Troubleshooting

**`playwright._impl._errors.Error: Executable doesn't exist`** — Run `playwright install chromium` once.

**`Brand 'xxx' not found`** — Run `python build.py --list-brands` to see available brands. Add a `<name>.yml` file in `brands/` to define new ones.

**`Template 'xxx' not found`** — Run `python build.py --list-templates`. Add a `<name>.html.j2` file in `templates/` to define new ones.

**Brand doesn't show up in the rendered PDF** — Check that `brand:` is set in frontmatter, or pass `--brand` on the CLI. Also confirm you haven't explicitly set `prepared_by`, `eyebrow`, and `footer` — those override brand-derived values.

**Admonition not rendering** — Every line of the block must start with `> ` with no blank line breaking it.

**Title accent doesn't appear** — Both `title_main` and `title_accent` are required for the italic accent; setting only `title` falls back to a plain title.
