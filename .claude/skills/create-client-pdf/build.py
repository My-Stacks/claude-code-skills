#!/usr/bin/env python3
"""
create-client-pdf

Convert a Markdown file with YAML frontmatter into a client-presentable PDF,
branded for either Stacklab or Stacklist.

Usage:
    python build.py input.md
    python build.py input.md --output out.pdf
    python build.py input.md --brand stacklist           # override frontmatter
    python build.py input.md --template default          # select template
    python build.py input.md --keep-html                 # keep intermediate HTML
"""

import argparse
import functools
import html as html_lib
import re
import shutil
import sys
import tempfile
import uuid
from pathlib import Path

import yaml
from jinja2 import Environment, FileSystemLoader
from markdown_it import MarkdownIt

SCRIPT_DIR = Path(__file__).parent
TEMPLATES_DIR = SCRIPT_DIR / "templates"
BRANDS_DIR = SCRIPT_DIR / "brands"
DEFAULT_TEMPLATE = "default"


# ─────────────────────────────────────────────────────────────
# Frontmatter
# ─────────────────────────────────────────────────────────────
def parse_frontmatter(text):
    """Return (frontmatter_dict, body_text)."""
    if not re.match(r"^---\s*\n", text):
        return {}, text
    pattern = re.compile(r"^---\s*$", re.MULTILINE)
    matches = list(pattern.finditer(text))
    if len(matches) < 2:
        return {}, text
    fm_text = text[matches[0].end():matches[1].start()]
    body = text[matches[1].end():].lstrip("\n")
    try:
        fm = yaml.safe_load(fm_text) or {}
    except yaml.YAMLError as e:
        print(f"Warning: YAML parse error: {e}", file=sys.stderr)
        fm = {}
    if not isinstance(fm, dict):
        print(
            f"Warning: frontmatter is not a mapping ({type(fm).__name__}); ignoring.",
            file=sys.stderr,
        )
        fm = {}
    return fm, body


# ─────────────────────────────────────────────────────────────
# Brand resolution
# ─────────────────────────────────────────────────────────────
@functools.lru_cache(maxsize=1)
def available_brands():
    return sorted(p.stem for p in BRANDS_DIR.glob("*.yml"))


def load_brand(brand_name):
    """Return the brand config dict, or None if brand_name is falsy."""
    if not brand_name:
        return None
    # Validate against the discovered set rather than building a path from
    # the raw name — blocks `../x` style traversal out of BRANDS_DIR.
    if brand_name not in available_brands():
        raise ValueError(
            f"Brand '{brand_name}' not found. "
            f"Available: {', '.join(available_brands()) or '(none)'}"
        )
    data = yaml.safe_load((BRANDS_DIR / f"{brand_name}.yml").read_text(encoding="utf-8")) or {}
    if not isinstance(data, dict):
        raise ValueError(f"Brand '{brand_name}' config is not a mapping.")
    return data


def derived_title(fm):
    """Compose a single title string from title / title_main / title_accent."""
    if fm.get("title"):
        return fm["title"]
    parts = [p for p in (fm.get("title_main"), fm.get("title_accent")) if p]
    return " ".join(parts) if parts else ""


def apply_brand_defaults(fm, brand_override=None):
    """
    Fill in prepared_by, eyebrow, and footer from the selected brand.
    Explicit frontmatter values always win.

    Precedence (most specific → least specific):
        1. Explicit frontmatter field (e.g. prepared_by: "Custom")
        2. CLI --brand flag (brand_override)
        3. Frontmatter `brand:` field
        4. No brand applied
    """
    fm = dict(fm)  # don't mutate the caller's dict
    brand_name = brand_override or fm.get("brand")
    if not brand_name:
        return fm

    brand = load_brand(brand_name)
    label = brand.get("label", brand_name)
    project = fm.get("project")
    title = derived_title(fm)

    # prepared_by → brand label
    fm.setdefault("prepared_by", label)

    # eyebrow → "{project} · {label}", or just "{label}" if no project
    if "eyebrow" not in fm:
        fm["eyebrow"] = f"{project} · {label}" if project else label

    # footer → "{project} · {title} · Prepared by {label}"
    if "footer" not in fm:
        parts = [p for p in (project, title) if p]
        parts.append(f"Prepared by {label}")
        fm["footer"] = " · ".join(parts)

    return fm


# ─────────────────────────────────────────────────────────────
# Template resolution
# ─────────────────────────────────────────────────────────────
@functools.lru_cache(maxsize=1)
def available_templates():
    return sorted(p.name.replace(".html.j2", "") for p in TEMPLATES_DIR.glob("*.html.j2"))


# Autoescape is on: all frontmatter values are escaped. The rendered body is
# trusted HTML and is injected via `{{ body|safe }}` in the template.
_JINJA_ENV = Environment(
    loader=FileSystemLoader(str(TEMPLATES_DIR)),
    autoescape=True,
)


def load_template(template_name):
    """Load the named template, or raise with a helpful message."""
    template_name = template_name or DEFAULT_TEMPLATE
    # Validate against the discovered set — blocks `../x` traversal.
    if template_name not in available_templates():
        raise ValueError(
            f"Template '{template_name}' not found. "
            f"Available: {', '.join(available_templates()) or '(none)'}"
        )
    return _JINJA_ENV.get_template(f"{template_name}.html.j2")


# ─────────────────────────────────────────────────────────────
# Admonition extraction
# ─────────────────────────────────────────────────────────────
ADMONITION_RE = re.compile(
    r"^> \[!(?P<type>[a-z-]+)\](?:[ \t]+(?P<label>[^\n]+))?[ \t]*\n"
    r"(?P<content>(?:>[^\n]*(?:\n|$))+)",
    re.MULTILINE,
)


def extract_admonitions(text):
    """Return (text_with_placeholders, blocks, sentinel).

    The sentinel is a per-call random token so a placeholder can never
    collide with literal document content, nor with another admonition's
    rendered HTML.
    """
    blocks = []
    sentinel = uuid.uuid4().hex

    def replace(m):
        idx = len(blocks)
        content_lines = m.group("content").splitlines()
        content = "\n".join(
            re.sub(r"^>[ \t]?", "", line) for line in content_lines
        ).strip()
        blocks.append({
            "type": m.group("type"),
            "label": (m.group("label") or "").strip(),
            "content": content,
        })
        return f"\n\n%%ADM-{sentinel}-{idx}%%\n\n"

    return ADMONITION_RE.sub(replace, text), blocks, sentinel


def render_admonitions(html, blocks, md, sentinel):
    for i, block in enumerate(blocks):
        inner_html = md.render(block["content"])
        css_class = f"adm-{block['type']}"
        label_html = ""
        if block["label"]:
            label_html = f'<div class="adm-label">{html_lib.escape(block["label"])}</div>'
        adm_html = f'<div class="{css_class}">{label_html}{inner_html}</div>'
        token = f"%%ADM-{sentinel}-{i}%%"
        html = html.replace(f"<p>{token}</p>", adm_html)
        html = html.replace(token, adm_html)
    return html


# ─────────────────────────────────────────────────────────────
# Section number markers
# ─────────────────────────────────────────────────────────────
SECTION_RE = re.compile(r"<h2>(\d+)\s*·\s*(.+?)</h2>", re.DOTALL)


def transform_sections(html):
    return SECTION_RE.sub(r'<h2><span class="sec-num">\1</span>\2</h2>', html)


# ─────────────────────────────────────────────────────────────
# Lede
# ─────────────────────────────────────────────────────────────
# The lede is the first paragraph, when fully italic. Per the authoring
# contract it follows the H1, so anchor on the first </h1> (or document
# start, for H1-less docs). `^` is offset-0 only — without this anchor the
# rule never fired on the documented (H1-first) case.
LEDE_RE = re.compile(
    r"(?P<lead>(?:^|</h1>)\s*)<p><em>(?P<text>.+?)</em></p>",
    re.DOTALL,
)


def transform_lede(html):
    return LEDE_RE.sub(
        lambda m: f'{m.group("lead")}<p class="lede">{m.group("text")}</p>',
        html,
        count=1,
    )


# ─────────────────────────────────────────────────────────────
# Tables: tier rows + auto-flow for long tables
# ─────────────────────────────────────────────────────────────
TABLE_RE = re.compile(r"<table>.*?</table>", re.DOTALL)
TIER_ROW_RE = re.compile(
    r"<tr>\s*<td[^>]*>\s*\[tier\]\s*(?P<text>.+?)</td>(?:\s*<td[^>]*>.*?</td>)*\s*</tr>",
    re.DOTALL,
)


def transform_tables(html):
    def per_table(m):
        table = m.group(0)
        # Count columns/rows on the original markup, before tier rows are
        # rewritten. Scope rows to <tbody> (excludes any header row, even
        # multi-row headers) and drop tier separators so they don't push a
        # short table over the flow threshold.
        cols = len(re.findall(r"<th[\s>]", table)) or 1
        tb = re.search(r"<tbody>(.*?)</tbody>", table, re.DOTALL)
        tbody = tb.group(1) if tb else table
        body_rows = len(re.findall(r"<tr[\s>]", tbody)) - len(
            re.findall(r"\[tier\]", tbody)
        )

        def tier_replace(tm):
            return (
                f'<tr class="tier"><td colspan="{cols}">'
                f'{tm.group("text").strip()}</td></tr>'
            )

        table = TIER_ROW_RE.sub(tier_replace, table)
        if body_rows > 6:
            table = table.replace("<table>", '<table class="flowing">', 1)
        return table

    return TABLE_RE.sub(per_table, html)


# ─────────────────────────────────────────────────────────────
# Render pipeline
# ─────────────────────────────────────────────────────────────
def build_html(fm, body_md, template_name=None):
    md = MarkdownIt("commonmark", {"html": True, "breaks": False, "linkify": True})
    md.enable("table")
    md.enable("strikethrough")

    body_md, admonitions, sentinel = extract_admonitions(body_md)
    body_html = md.render(body_md)
    body_html = render_admonitions(body_html, admonitions, md, sentinel)
    body_html = transform_sections(body_html)
    body_html = transform_lede(body_html)
    body_html = transform_tables(body_html)

    template_name = template_name or fm.get("template") or DEFAULT_TEMPLATE
    template = load_template(template_name)

    # Build the context as a dict to avoid two crash modes:
    #   - non-string YAML keys (e.g. `1: value`) blow up `**fm`.
    #   - a frontmatter `body:` collides with the rendered-body kwarg.
    context = dict(fm)
    for key in context:
        if not isinstance(key, str):
            raise ValueError(
                f"Frontmatter keys must be strings; got {type(key).__name__}: {key!r}"
            )
    if "body" in context:
        raise ValueError(
            "Frontmatter key 'body' is reserved (used for the rendered document body)"
        )
    context["body"] = body_html
    return template.render(context)


# ─────────────────────────────────────────────────────────────
# PDF render via Playwright
# ─────────────────────────────────────────────────────────────
def build_footer(text):
    safe = html_lib.escape(text or "", quote=True)
    return (
        '<div style="font-size:7pt; font-family:-apple-system, \'Helvetica Neue\', '
        'Arial, sans-serif; color:#6b6b6b; width:100%; padding: 0 0.85in; '
        "display:flex; justify-content:space-between; letter-spacing:0.08em; "
        'text-transform:uppercase;">'
        f"<span>{safe}</span>"
        '<span><span class="pageNumber"></span> / <span class="totalPages"></span></span>'
        "</div>"
    )


def render_pdf(html_path, pdf_path, footer_text):
    # Sync API (not asyncio) so build_pdf() is safe to call from any host,
    # including one already running an event loop. Path.as_uri() handles
    # spaces / non-ASCII in the path that a raw "file://" + str would break.
    from playwright.sync_api import sync_playwright

    # Restrict subresources to file:// URIs inside the same temp dir as the
    # rendered HTML — blocks BOTH remote loads (SSRF / exfiltration) AND
    # arbitrary local file embeds like `<iframe src="file:///etc/passwd">`
    # that a plain `file:` allowlist would let through. Resolve symlinks on
    # both sides so a /var → /private/var (macOS) mismatch doesn't abort the
    # navigation itself.
    resolved_html = Path(html_path).resolve()
    allowed_root = resolved_html.parent.as_uri()
    if not allowed_root.endswith("/"):
        allowed_root += "/"

    with sync_playwright() as p:
        browser = p.chromium.launch()
        try:
            # JS off: the template is static; disabling JS limits blast
            # radius if raw HTML in the markdown body contains <script>.
            context = browser.new_context(java_script_enabled=False)
            page = context.new_page()
            page.route(
                "**/*",
                lambda r: r.continue_()
                if r.request.url.startswith(allowed_root)
                else r.abort(),
            )
            try:
                page.goto(resolved_html.as_uri(), wait_until="load", timeout=15_000)
                page.pdf(
                    path=str(pdf_path),
                    format="Letter",
                    print_background=True,
                    display_header_footer=True,
                    header_template="<div></div>",
                    footer_template=build_footer(footer_text),
                    margin={"top": "0.5in", "bottom": "0.5in", "left": "0in", "right": "0in"},
                    prefer_css_page_size=True,
                )
            except Exception as exc:
                raise RuntimeError(
                    f"PDF render failed for {html_path}: {exc}"
                ) from exc
            finally:
                context.close()
        finally:
            browser.close()


def slugify(text):
    text = re.sub(r"[^\w\s-]", "", text or "").strip()
    text = re.sub(r"[\s_-]+", "-", text)
    return text or "deliverable"


def resolve_output_path(markdown_path, fm, output_path):
    """Decide where the PDF lands. A frontmatter `filename:` is reduced to
    its basename so a client-supplied doc cannot write outside the source
    directory (e.g. `filename: ~/.ssh/id_rsa` or `/etc/x`)."""
    if output_path is not None:
        return Path(output_path).expanduser().resolve()
    fm_name = fm.get("filename")
    if fm_name:
        safe = Path(str(fm_name)).name  # strips dirs / absolute / ~ prefix
        if not safe or safe in (".", ".."):
            raise ValueError(f"Invalid frontmatter filename: {fm_name!r}")
        if not safe.lower().endswith(".pdf"):
            safe += ".pdf"
        return (markdown_path.parent / safe).resolve()
    title = derived_title(fm)
    if title:
        return (markdown_path.parent / f"{slugify(title)}.pdf").resolve()
    return markdown_path.with_suffix(".pdf").resolve()


# ─────────────────────────────────────────────────────────────
# Entry point
# ─────────────────────────────────────────────────────────────
def build_pdf(markdown_path, output_path=None, brand=None, template=None, keep_html=False):
    markdown_path = Path(markdown_path).expanduser().resolve()
    text = markdown_path.read_text(encoding="utf-8")
    fm, body = parse_frontmatter(text)

    fm = apply_brand_defaults(fm, brand_override=brand)
    title = derived_title(fm)

    output_path = resolve_output_path(markdown_path, fm, output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    html = build_html(fm, body, template_name=template)
    footer_text = fm.get("footer") or title or "Client deliverable"

    # Render from a temp dir so we never clobber a same-named .html the user
    # owns, and nothing is left behind if rendering crashes mid-way.
    with tempfile.TemporaryDirectory(prefix="create-client-pdf-") as tmp:
        html_path = Path(tmp) / "doc.html"
        html_path.write_text(html, encoding="utf-8")
        render_pdf(html_path, output_path, footer_text)
        if keep_html:
            shutil.copyfile(html_path, output_path.with_suffix(".html"))

    return output_path


def main():
    parser = argparse.ArgumentParser(
        description="create-client-pdf — markdown to client-presentable PDF"
    )
    parser.add_argument("input", nargs="?", help="Path to .md file with YAML frontmatter")
    parser.add_argument("-o", "--output", help="Output PDF path (optional)")
    parser.add_argument(
        "--brand",
        help=f"Output brand. Available: {', '.join(available_brands()) or '(none)'}",
    )
    parser.add_argument(
        "--template",
        help=f"Layout template. Available: {', '.join(available_templates()) or '(none)'}",
    )
    parser.add_argument(
        "--keep-html", action="store_true", help="Don't delete intermediate HTML"
    )
    parser.add_argument(
        "--list-brands", action="store_true", help="List available brands and exit"
    )
    parser.add_argument(
        "--list-templates", action="store_true", help="List available templates and exit"
    )
    args = parser.parse_args()

    if args.list_brands:
        for b in available_brands():
            print(b)
        return
    if args.list_templates:
        for t in available_templates():
            print(t)
        return

    if not args.input:
        parser.error("input is required (unless using --list-brands / --list-templates)")

    out = build_pdf(
        args.input,
        args.output,
        brand=args.brand,
        template=args.template,
        keep_html=args.keep_html,
    )
    print(f"Wrote {out}")


if __name__ == "__main__":
    main()
