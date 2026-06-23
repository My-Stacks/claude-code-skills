"""finding_key.py — single source of truth for the per-finding key.

Covers: import-vs-CLI parity (the load-bearing contract), determinism, a golden
value (catches any algorithm change that would break existing markers), end/
category fallbacks, resolved_file precedence, and key distinctness.
"""
import os
import sys
import unittest

from _util import run

sys.path.insert(0, os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "scripts", "lib")))
import finding_key as fk  # noqa: E402


def cli(*args):
    rc, out, err = run("finding_key.py", args=[str(a) for a in args], lib=True)
    assert rc == 0, err
    return out.strip()


class TestFindingKey(unittest.TestCase):
    def test_cli_matches_import(self):
        # The contract that makes by-key resolve work: build-review-payload (import)
        # and fix-findings (CLI) must produce identical keys.
        imp = fk.finding_key("demo.py", 3, 3, "correctness")
        self.assertEqual(cli("demo.py", 3, 3, "correctness"), imp)

    def test_key_from_finding_matches_cli(self):
        f = {"file": "demo.py", "start_line": 3, "end_line": 3,
             "category": "correctness", "verify": {"resolved_file": "demo.py"}}
        self.assertEqual(fk.key_from_finding(f), cli("demo.py", 3, 3, "correctness"))

    def test_golden_value(self):
        # Regression anchor — if this changes, existing posted markers stop matching.
        self.assertEqual(fk.finding_key("demo.py", 3, 3, "correctness"), "5f7ea1ab1252")

    def test_is_twelve_hex(self):
        k = fk.finding_key("a.py", 1, 1, "x")
        self.assertEqual(len(k), 12)
        self.assertTrue(all(c in "0123456789abcdef" for c in k))

    def test_deterministic(self):
        self.assertEqual(fk.finding_key("a.py", 1, 2, "perf"), fk.finding_key("a.py", 1, 2, "perf"))

    def test_end_falls_back_to_start(self):
        self.assertEqual(fk.finding_key("a.py", 5, None, "c"), fk.finding_key("a.py", 5, 5, "c"))
        # CLI: omitted end arg also falls back to start
        self.assertEqual(cli("a.py", 5), cli("a.py", 5, 5))

    def test_category_falls_back_to_empty(self):
        self.assertEqual(fk.finding_key("a.py", 1, 1, None), fk.finding_key("a.py", 1, 1, ""))
        self.assertEqual(cli("a.py", 1, 1), cli("a.py", 1, 1, ""))

    def test_resolved_file_precedence(self):
        f1 = {"file": "wrong.py", "start_line": 1, "end_line": 1, "category": "c",
              "verify": {"resolved_file": "right.py"}}
        self.assertEqual(fk.key_from_finding(f1), fk.finding_key("right.py", 1, 1, "c"))

    def test_distinct_inputs_distinct_keys(self):
        keys = {
            fk.finding_key("a.py", 1, 1, "c"),
            fk.finding_key("a.py", 1, 2, "c"),
            fk.finding_key("a.py", 2, 2, "c"),
            fk.finding_key("b.py", 1, 1, "c"),
            fk.finding_key("a.py", 1, 1, "security"),
        }
        self.assertEqual(len(keys), 5)


if __name__ == "__main__":
    unittest.main()
