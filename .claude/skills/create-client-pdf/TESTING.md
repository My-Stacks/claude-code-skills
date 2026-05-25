# Testing & regression baseline

Two layers. Run both before changing `build.py` or `templates/`.

## 1. Pure unit tests — `tests/test_build_html.py`

No Chromium needed (the render pipeline up to, but not including, the
Playwright PDF step). Fast. Covers the fragile regex transforms:
frontmatter parsing, lede anchoring, section numerals, admonitions, tier
rows, long-table flow, autoescaping.

```bash
pip install -r requirements.txt pytest
pytest tests/test_build_html.py
```

## 2. Smoke tests — `tests/test_smoke_build.py`

Renders every `examples/*.md` through `build_pdf()` and asserts it
produces a PDF with the **recorded page count** and no exception. This is
the regression net for layout-affecting changes. Needs Chromium + pypdf;
skips (does not fail) if either is absent.

```bash
pip install -r requirements.txt pytest "pypdf==4.*"
playwright install chromium
pytest tests/test_smoke_build.py
```

> **Baseline is macOS-calibrated.** Page counts depend on font metrics.
> macOS has Georgia + a usable Inter fallback; on a host that substitutes
> fonts (typical Linux CI) the counts can shift and the smoke test will
> report a "regression" that is really a font difference. For CI either
> install Georgia/Inter on the runner, or treat `test_smoke_build.py` as
> macOS/local-only and gate it out of the Linux pipeline. The pure unit
> tests (`test_build_html.py`) are font-independent and safe everywhere.

Recorded baseline (in `EXPECTED_PAGES`):

| Example | Pages |
|---|---|
| `test-wade-pov.md` | 3 |
| `test-competitive.md` | 4 |
| `test-lede.md` | 2 |
| `competitive-landscape-reference.md` | 4 |

A new `examples/*.md` with no recorded expectation fails the suite by
design — add its page count to `EXPECTED_PAGES` deliberately.

## 3. Manual visual baseline — `examples/competitive-landscape-reference.md`

`competitive-landscape-reference.md` is the **rendered-and-approved**
spec-compliant doc (signed off May 2026). It exercises every design
component: branded cover with eyebrow + italic accent, lede, numbered
sections, a long flowing table, three dark tier bars, the dark
bottom-line block, and the methodology footnote.

**After any change to `build.py` or `templates/`:** rebuild it and
visually compare to the prior PDF.

```bash
python build.py examples/competitive-landscape-reference.md --keep-html
```

If the layout diverges from the approved baseline, the change needs
review before it lands — page count alone (test 2) will not catch a
subtle visual regression.
