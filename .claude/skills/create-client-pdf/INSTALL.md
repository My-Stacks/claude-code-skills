# Install

One-time setup for `create-client-pdf`.

## Requirements

- Python 3.10 or newer
- macOS, Linux, or Windows
- ~400 MB disk for Chromium (downloaded once by Playwright)

## Steps

```bash
# cd into this skill directory (path depends on where it's installed,
# e.g. .claude/skills/create-client-pdf/ in the repo, or
# ~/.claude/skills/create-client-pdf/ once copied into your config)
cd "$(dirname "$0")" 2>/dev/null || cd .claude/skills/create-client-pdf

pip install -r requirements.txt
playwright install chromium
```

Test it:

```bash
python build.py examples/test-wade-pov.md
```

If it prints `Wrote .../Move-with-WADE-Website-Redesign-POV.pdf`, you're set.

## Font fidelity (read this)

The design system uses **Georgia** (serif headings/lede) and **Inter** (body).
Neither is embedded — the template relies on the host having them. macOS ships
Georgia and a usable Inter fallback, so output is faithful there. On **Linux /
CI**, headless Chromium has neither and silently substitutes generic fonts, so
the PDF will look noticeably off. Run this skill on macOS for client
deliverables, or install Georgia + Inter on the rendering host before relying
on the output.

## Optional: virtualenv

```bash
cd create-client-pdf
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
playwright install chromium
```

Then `source .venv/bin/activate` before running `build.py`.

## Using from another script (e.g. Beacon)

```python
import sys
sys.path.insert(0, "/path/to/create-client-pdf")
from build import build_pdf

output_path = build_pdf(
    "path/to/input.md",
    brand="stacklab",           # optional; otherwise read from frontmatter
    template="default",         # optional; defaults to "default"
)
```

Or shell out:

```python
import subprocess
subprocess.run(
    ["python", "/path/to/create-client-pdf/build.py", "input.md", "--brand", "stacklab"],
    check=True,
)
```
