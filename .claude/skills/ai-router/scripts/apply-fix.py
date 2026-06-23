#!/usr/bin/env python3
"""apply-fix.py — apply ONE finding's suggested replacement to a file, safely.

The safety contract: replace lines [start, end] of <file> with <replacement> ONLY
if the file's current content at those lines still exactly matches <expected> (the
grounded `shown_code` from verify-findings.py). If the file has changed since the
review — lines shifted, already edited, wrong branch checked out — the match fails
and nothing is written. This is what makes the fixer safe to run unattended: it can
never blindly overwrite the wrong lines.

Inputs are passed as files (not args) to avoid any shell-escaping of code:
  --file F           the file to edit (edited in place)
  --start N          1-based first line of the range (inclusive)
  --end M            1-based last line of the range (inclusive)
  --expected E       file holding the expected current content of [start, end]
  --replacement R    file holding the new content for those lines

Exit codes:
  0  applied
  2  usage error
  3  stale — current content != expected (nothing written)
  4  range out of bounds (nothing written)
"""
import argparse
import sys


def _read(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def main(argv):
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--file", required=True)
    ap.add_argument("--start", required=True, type=int)
    ap.add_argument("--end", required=True, type=int)
    ap.add_argument("--expected", required=True)
    ap.add_argument("--replacement", required=True)
    try:
        a = ap.parse_args(argv[1:])
    except SystemExit:
        return 2

    if a.start < 1 or a.end < a.start:
        sys.stderr.write(f"apply-fix.py: bad range {a.start}-{a.end}\n")
        return 2

    try:
        content = _read(a.file)
        expected = _read(a.expected)
        replacement = _read(a.replacement)
    except OSError as e:
        sys.stderr.write(f"apply-fix.py: {e}\n")
        return 2

    # Split keeping a trailing-newline marker so we can rebuild byte-faithfully.
    had_final_nl = content.endswith("\n")
    lines = content.split("\n")
    if had_final_nl:
        lines = lines[:-1]  # drop the empty element after the final newline

    if a.end > len(lines):
        sys.stderr.write(
            f"apply-fix.py: range {a.start}-{a.end} exceeds file length {len(lines)}\n"
        )
        return 4

    current = "\n".join(lines[a.start - 1:a.end])
    # Compare ignoring a single trailing newline difference on the expected blob.
    exp = expected[:-1] if expected.endswith("\n") else expected
    if current != exp:
        sys.stderr.write(
            "apply-fix.py: STALE — current content does not match expected; not writing.\n"
            f"--- expected ---\n{exp}\n--- current ---\n{current}\n"
        )
        return 3

    repl = replacement[:-1] if replacement.endswith("\n") else replacement
    new_lines = lines[:a.start - 1] + repl.split("\n") + lines[a.end:]
    out = "\n".join(new_lines)
    if had_final_nl:
        out += "\n"
    with open(a.file, "w", encoding="utf-8") as f:
        f.write(out)
    sys.stderr.write(f"apply-fix.py: applied to {a.file} lines {a.start}-{a.end}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
