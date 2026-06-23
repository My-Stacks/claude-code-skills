"""apply-fix.py — apply ONE replacement to a file, only if it still matches.

Covers: match applies, stale refuses (exit 3), out-of-range (4), bad range (2),
final-newline preservation (with/without), line-count growth/shrink, expected
trailing-newline tolerance.
"""
import os
import tempfile
import unittest

from _util import run


def apply(content, start, end, expected, replacement):
    d = tempfile.mkdtemp()
    fp = os.path.join(d, "f.txt")
    ep = os.path.join(d, "expected")
    rp = os.path.join(d, "repl")
    with open(fp, "w") as fh: fh.write(content)
    with open(ep, "w") as fh: fh.write(expected)
    with open(rp, "w") as fh: fh.write(replacement)
    rc, out, err = run("apply-fix.py", args=[
        "--file", fp, "--start", str(start), "--end", str(end),
        "--expected", ep, "--replacement", rp])
    with open(fp) as fh: result = fh.read()
    return rc, result, err


class TestApplyFix(unittest.TestCase):
    def test_single_line_match_applies(self):
        rc, result, _ = apply("a\nb\nc\n", 2, 2, "b", "B")
        self.assertEqual(rc, 0)
        self.assertEqual(result, "a\nB\nc\n")

    def test_multiline_replacement_grows(self):
        rc, result, _ = apply("a\nb\nc\n", 2, 2, "b", "x\ny\nz")
        self.assertEqual(rc, 0)
        self.assertEqual(result, "a\nx\ny\nz\nc\n")

    def test_multiline_range_shrinks(self):
        rc, result, _ = apply("a\nb\nc\nd\n", 2, 3, "b\nc", "B")
        self.assertEqual(rc, 0)
        self.assertEqual(result, "a\nB\nd\n")

    def test_stale_mismatch_refuses_no_write(self):
        rc, result, err = apply("a\nb\nc\n", 2, 2, "DIFFERENT", "B")
        self.assertEqual(rc, 3)
        self.assertEqual(result, "a\nb\nc\n")  # untouched
        self.assertIn("STALE", err)

    def test_out_of_range_refuses(self):
        rc, result, _ = apply("a\nb\n", 5, 5, "b", "B")
        self.assertEqual(rc, 4)
        self.assertEqual(result, "a\nb\n")

    def test_bad_range_start_zero(self):
        rc, result, _ = apply("a\nb\n", 0, 0, "a", "A")
        self.assertEqual(rc, 2)

    def test_bad_range_end_lt_start(self):
        rc, result, _ = apply("a\nb\nc\n", 3, 2, "b", "B")
        self.assertEqual(rc, 2)

    def test_preserves_no_final_newline(self):
        # file without trailing newline stays that way
        rc, result, _ = apply("a\nb", 2, 2, "b", "B")
        self.assertEqual(rc, 0)
        self.assertEqual(result, "a\nB")

    def test_preserves_final_newline(self):
        rc, result, _ = apply("a\nb\n", 2, 2, "b", "B")
        self.assertEqual(rc, 0)
        self.assertTrue(result.endswith("\n"))

    def test_expected_trailing_newline_tolerated(self):
        # expected blob may have a trailing newline; still matches
        rc, result, _ = apply("a\nb\nc\n", 2, 2, "b\n", "B")
        self.assertEqual(rc, 0)
        self.assertEqual(result, "a\nB\nc\n")

    def test_indentation_sensitive(self):
        # whitespace matters — a mismatch in indentation is stale
        rc, result, _ = apply("def f():\n    return 1\n", 2, 2, "  return 1", "    return 2")
        self.assertEqual(rc, 3)  # "  return 1" != "    return 1"
        self.assertEqual(result, "def f():\n    return 1\n")


if __name__ == "__main__":
    unittest.main()
