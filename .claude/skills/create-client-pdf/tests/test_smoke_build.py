"""
Smoke tests: render every examples/*.md through build_pdf() and assert it
produces a PDF with the expected page count and no exception.

This is the regression net for layout-affecting changes to build.py /
templates/. It is intentionally NOT a pixel diff — page count + a clean
build catches the regressions that matter (a component silently dropping,
a blank page appearing, a crash). For visual fidelity, follow the manual
baseline step in TESTING.md.

Needs Chromium + pypdf (unlike test_build_html.py, which is pure):

    pip install -r requirements.txt pytest pypdf
    playwright install chromium
    pytest

The suite skips (does not fail) if Chromium or pypdf is absent, so the
pure unit tests still run in a bare environment.
"""

import sys
from pathlib import Path

import pytest

SKILL_DIR = Path(__file__).resolve().parent.parent
EXAMPLES_DIR = SKILL_DIR / "examples"
sys.path.insert(0, str(SKILL_DIR))

from build import build_pdf  # noqa: E402

pypdf = pytest.importorskip("pypdf", reason="pip install pypdf to run smoke tests")

# Recorded baseline. Update deliberately (and note why in TESTING.md) if a
# change is supposed to alter page count. An unexplained change here is the
# regression signal.
EXPECTED_PAGES = {
    "test-wade-pov.md": 3,
    "test-competitive.md": 4,
    "test-lede.md": 2,
    "competitive-landscape-reference.md": 4,
}


def test_every_example_has_a_recorded_expectation():
    """A new examples/*.md must get a recorded page count, or this fails."""
    on_disk = {p.name for p in EXAMPLES_DIR.glob("*.md")}
    assert on_disk == set(EXPECTED_PAGES), (
        f"examples/ and EXPECTED_PAGES are out of sync: "
        f"only on disk={on_disk - set(EXPECTED_PAGES)}, "
        f"only recorded={set(EXPECTED_PAGES) - on_disk}"
    )


@pytest.mark.parametrize("name,expected", sorted(EXPECTED_PAGES.items()))
def test_example_builds_with_expected_page_count(name, expected, tmp_path):
    src = EXAMPLES_DIR / name
    out = tmp_path / f"{src.stem}.pdf"
    try:
        result = build_pdf(str(src), output_path=str(out))
    except Exception as e:  # noqa: BLE001
        if "Executable doesn't exist" in str(e) or "playwright install" in str(e):
            pytest.skip("Chromium not installed: run `playwright install chromium`")
        raise
    assert Path(result).exists(), f"{name}: build_pdf did not produce {result}"
    pages = len(pypdf.PdfReader(str(result)).pages)
    assert pages == expected, (
        f"{name}: rendered {pages} pages, expected {expected}. "
        f"If this change is intentional, update EXPECTED_PAGES and note it "
        f"in TESTING.md; otherwise the change regressed the layout."
    )
