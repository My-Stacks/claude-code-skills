"""
Pure-function tests for the create-client-pdf render pipeline.

These cover everything up to (not including) the Playwright PDF step, so they
run with just the pip deps — no Chromium needed:

    pip install -r requirements.txt pytest
    pytest

Bug #1 (the lede rule never firing when an H1 is present) would have been
caught by test_lede_renders_after_h1.
"""

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from build import (  # noqa: E402
    apply_brand_defaults,
    build_footer,
    build_html,
    load_brand,
    load_template,
    parse_frontmatter,
    resolve_output_path,
    transform_sections,
    transform_tables,
)


def test_parse_frontmatter_splits_yaml_and_body():
    fm, body = parse_frontmatter("---\ntitle: Hi\n---\n\n# Heading\n")
    assert fm == {"title": "Hi"}
    assert body.startswith("# Heading")


def test_parse_frontmatter_no_frontmatter():
    fm, body = parse_frontmatter("# Just a heading\n")
    assert fm == {}
    assert body == "# Just a heading\n"


def test_lede_renders_after_h1():
    # Regression: the lede must style the first italic paragraph that
    # follows the H1 (the documented case), not only an H1-less doc.
    html = build_html({}, "# Title\n\n*This is the lede.*\n\nNormal paragraph.")
    assert '<p class="lede">This is the lede.</p>' in html


def test_lede_only_first_paragraph():
    html = build_html({}, "# Title\n\nPlain intro.\n\n*Not the lede.*")
    assert 'class="lede"' not in html


def test_section_numeral_marker():
    out = transform_sections("<h2>1 · The case</h2>")
    assert '<h2><span class="sec-num">1</span>' in out
    assert "The case</h2>" in out


def test_admonition_callout_and_label_escaped():
    html = build_html(
        {}, '# T\n\n> [!canonical] A & B <tag>\n> "Citable sentence."\n'
    )
    assert 'class="adm-canonical"' in html
    # Label is escaped, not injected raw.
    assert "A &amp; B &lt;tag&gt;" in html
    assert "<tag>" not in html


def test_long_table_gets_flowing_class():
    rows = "\n".join(f"| r{i} | v{i} |" for i in range(8))
    table_md = f"| A | B |\n|---|---|\n{rows}\n"
    html = build_html({}, f"# T\n\n{table_md}")
    assert '<table class="flowing">' in html


def test_short_table_not_flowing():
    table_md = "| A | B |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |\n"
    html = build_html({}, f"# T\n\n{table_md}")
    assert "<table>" in html
    assert 'class="flowing"' not in html


def test_tier_row_spans_all_columns():
    html = transform_tables(
        "<table><thead><tr><th>A</th><th>B</th><th>C</th></tr></thead>"
        "<tbody><tr><td>[tier] Tier 1</td><td></td><td></td></tr>"
        "<tr><td>x</td><td>y</td><td>z</td></tr></tbody></table>"
    )
    assert '<tr class="tier"><td colspan="3">Tier 1</td></tr>' in html


def test_frontmatter_values_are_autoescaped():
    # A normal client title with & / < must not produce broken markup.
    html = build_html({"title": "Q1 < Q2 & Bain"}, "# Body\n")
    assert "Q1 &lt; Q2 &amp; Bain" in html
    assert "<title>Q1 < Q2 & Bain</title>" not in html


# ── security / robustness hardening (ensemble review) ──────────────────


@pytest.mark.parametrize(
    "evil",
    ["~/.ssh/id_rsa", "/etc/passwd", "../../secret", "../x.pdf", "a/b/c.pdf", "~"],
)
def test_frontmatter_filename_cannot_escape_source_dir(evil, tmp_path):
    md = tmp_path / "doc.md"
    md.write_text("# t\n")
    out = resolve_output_path(md.resolve(), {"filename": evil}, None)
    # Always lands inside the markdown's own directory, basename only.
    assert out.parent == md.resolve().parent
    # Basename is preserved (possibly with a `.pdf` suffix appended) — never
    # any directory parts from `evil`.
    expected_base = Path(evil).name
    if not expected_base.lower().endswith(".pdf"):
        expected_base += ".pdf"
    assert out.name == expected_base
    assert ".." not in out.parts


@pytest.mark.parametrize("bad", [".", "..", "/", ".pdf", ".PDF", "/.pdf"])
def test_frontmatter_filename_rejects_degenerate(bad, tmp_path):
    md = tmp_path / "doc.md"
    md.write_text("# t\n")
    with pytest.raises(ValueError):
        resolve_output_path(md.resolve(), {"filename": bad}, None)


def test_explicit_output_path_is_honored(tmp_path):
    md = tmp_path / "doc.md"
    md.write_text("# t\n")
    target = tmp_path / "sub" / "out.pdf"
    assert resolve_output_path(md.resolve(), {}, str(target)) == target.resolve()


def test_load_brand_rejects_unknown_and_traversal():
    for bad in ["does-not-exist", "../build", "../../etc/passwd"]:
        with pytest.raises(ValueError):
            load_brand(bad)


def test_load_brand_known_works():
    assert load_brand("stacklab").get("label") == "Stacklab"


def test_load_template_rejects_unknown_and_traversal():
    for bad in ["nope", "../build", "../../README"]:
        with pytest.raises(ValueError):
            load_template(bad)


def test_parse_frontmatter_non_dict_is_ignored():
    fm, body = parse_frontmatter("---\n- a\n- b\n---\n\n# H\n")
    assert fm == {}
    assert body.startswith("# H")


def test_apply_brand_defaults_precedence():
    # CLI override beats frontmatter brand; explicit fields beat brand.
    fm = apply_brand_defaults(
        {"brand": "stacklist", "prepared_by": "Custom Co"},
        brand_override="stacklab",
    )
    assert fm["prepared_by"] == "Custom Co"          # explicit wins
    assert fm["eyebrow"] == "Stacklab"               # from CLI override, not stacklist


def test_apply_brand_defaults_no_brand_is_noop():
    fm = apply_brand_defaults({"title": "x"})
    assert "prepared_by" not in fm and "eyebrow" not in fm


def test_build_footer_escapes_all_html_metacharacters():
    out = build_footer('A & B <x> "q\' end')
    for raw in ("&amp;", "&lt;", "&gt;", "&#x27;"):
        assert raw in out
    assert "<x>" not in out


def test_admonition_sentinel_survives_literal_collision_text():
    # Document literally containing the old fixed token must not break.
    html = build_html(
        {}, "# T\n\nLiteral %%ADM-0%% in prose.\n\n> [!callout]\n> Real one.\n"
    )
    assert "%%ADM-0%%" in html              # literal text preserved
    assert 'class="adm-callout"' in html    # real admonition still rendered


def test_build_html_rejects_reserved_body_key_in_frontmatter():
    # `body` is reserved for the rendered HTML; a frontmatter `body:` would
    # otherwise crash template.render with "got multiple values for keyword
    # argument 'body'". Fail loudly with a clear message instead.
    with pytest.raises(ValueError, match="reserved"):
        build_html({"body": "anything"}, "# T\n")


def test_build_html_rejects_non_string_frontmatter_keys():
    # Non-string YAML keys (e.g. `1: value`) would otherwise crash
    # template.render with "keywords must be strings".
    with pytest.raises(ValueError, match="must be strings"):
        build_html({1: "value"}, "# T\n")


def test_apply_brand_defaults_does_not_mutate_caller_dict():
    original = {"brand": "stacklab"}
    apply_brand_defaults(original)
    assert original == {"brand": "stacklab"}   # caller's dict unchanged


def test_build_html_does_not_mutate_caller_dict():
    # Symmetric to apply_brand_defaults: build_html should never write back to
    # the caller's frontmatter dict (`body` injection goes into a local copy).
    original = {"title": "Hi"}
    build_html(original, "# T\n")
    assert original == {"title": "Hi"}


def test_frontmatter_filename_gets_pdf_suffix(tmp_path):
    md = tmp_path / "doc.md"
    md.write_text("# t\n")
    # No suffix → .pdf appended.
    out = resolve_output_path(md.resolve(), {"filename": "report"}, None)
    assert out.name == "report.pdf"
    # Non-.pdf suffix → .pdf appended.
    out = resolve_output_path(md.resolve(), {"filename": "report.txt"}, None)
    assert out.name == "report.txt.pdf"
    # Existing .pdf (case-insensitive) → left alone.
    out = resolve_output_path(md.resolve(), {"filename": "report.PDF"}, None)
    assert out.name == "report.PDF"
