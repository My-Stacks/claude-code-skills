"""build-review-payload.py — verified findings → GitHub review payload.

Covers: confirmed → inline (+committable suggestion + key marker), multi-line
contiguous vs non-contiguous targeting, partial → plain comment, unverified/
invalid → excluded (never inline), context-only → excluded, empty input.
"""
import json
import os
import tempfile
import unittest

from _util import run


def build(findings, version="1.9", run_id="t"):
    with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False) as fh:
        fh.write("## Summary\n")
        body = fh.name
    try:
        rc, out, err = run("build-review-payload.py", lib=True, stdin=json.dumps(findings),
                           args=["--commit", "deadbeef", "--body-file", body,
                                 "--version", version, "--run-id", run_id])
        assert rc == 0, f"exit {rc}: {err}"
        return json.loads(out)
    finally:
        os.unlink(body)


def vf(status="confirmed", added=None, grounded=None, file="m.py", code="    code"):
    return {"status": status, "resolved_file": file,
            "added_lines": added if added is not None else [],
            "lines_grounded": grounded if grounded is not None else (added or []),
            "shown_code": code}


class TestBuildPayload(unittest.TestCase):
    def test_payload_envelope(self):
        p = build([])
        self.assertEqual(p["event"], "COMMENT")
        self.assertEqual(p["commit_id"], "deadbeef")
        self.assertIn("## Summary", p["body"])
        self.assertEqual(p["comments"], [])

    def test_confirmed_single_line_committable_suggestion_and_key(self):
        f = {"severity": "CRITICAL", "category": "correctness", "file": "m.py",
             "start_line": 5, "end_line": 5, "issue": "bug", "fix": "do x",
             "suggestion": "    fixed()", "verify": vf("confirmed", [5])}
        p = build([f])
        self.assertEqual(len(p["comments"]), 1)
        c = p["comments"][0]
        self.assertEqual(c["path"], "m.py")
        self.assertEqual(c["line"], 5)
        self.assertNotIn("start_line", c)  # single line
        self.assertIn("```suggestion", c["body"])
        self.assertIn("ai-router-finding key=", c["body"])

    def test_confirmed_multiline_contiguous_sets_start_line(self):
        f = {"severity": "NIT", "category": "correctness", "file": "m.py",
             "start_line": 5, "end_line": 6, "issue": "x", "fix": "y",
             "verify": vf("confirmed", [5, 6])}
        c = build([f])["comments"][0]
        self.assertEqual(c["start_line"], 5)
        self.assertEqual(c["line"], 6)

    def test_non_contiguous_added_single_line_only(self):
        # added lines 5 and 8 (gap) -> must NOT span 5..8; single line at max
        f = {"severity": "NIT", "category": "correctness", "file": "m.py",
             "start_line": 5, "end_line": 8, "issue": "x", "fix": "y",
             "verify": vf("confirmed", [5, 8])}
        c = build([f])["comments"][0]
        self.assertEqual(c["line"], 8)
        self.assertNotIn("start_line", c)

    def test_partial_no_committable_suggestion(self):
        f = {"severity": "NIT", "category": "correctness", "file": "m.py",
             "start_line": 5, "end_line": 5, "issue": "x", "fix": "y",
             "suggestion": "    fixed()", "verify": vf("partial", [5])}
        c = build([f])["comments"][0]
        self.assertNotIn("```suggestion", c["body"])  # suggestion only on confirmed

    def test_unverified_excluded_not_inline(self):
        f = {"severity": "NIT", "category": "correctness", "file": "ghost.py",
             "start_line": 1, "end_line": 1, "issue": "halluc", "fix": "y",
             "verify": {"status": "unverified", "reason": "not in diff",
                        "added_lines": [], "lines_grounded": []}}
        p = build([f])
        self.assertEqual(p["comments"], [])
        self.assertIn("Not grounded", p["body"])
        self.assertIn("ghost.py", p["body"])

    def test_invalid_excluded_not_inline(self):
        f = {"severity": "NIT", "category": "correctness", "file": "m.py",
             "start_line": 1, "end_line": 1, "issue": "x", "fix": "y",
             "verify": {"status": "invalid", "reason": "missing field",
                        "added_lines": [], "lines_grounded": []}}
        p = build([f])
        self.assertEqual(p["comments"], [])
        self.assertIn("Not grounded", p["body"])

    def test_confirmed_but_no_added_line_excluded(self):
        # grounded only on context (no '+' lines) -> nothing to attach to
        f = {"severity": "NIT", "category": "correctness", "file": "m.py",
             "start_line": 5, "end_line": 5, "issue": "x", "fix": "y",
             "verify": vf("confirmed", added=[], grounded=[5])}
        p = build([f])
        self.assertEqual(p["comments"], [])

    def test_sources_attribution_in_body(self):
        f = {"severity": "CRITICAL", "category": "security", "file": "m.py",
             "start_line": 5, "end_line": 5, "issue": "x", "fix": "y",
             "sources": ["anthropic", "openai"], "verify": vf("confirmed", [5])}
        c = build([f])["comments"][0]
        self.assertIn("anthropic", c["body"])
        self.assertIn("openai", c["body"])


if __name__ == "__main__":
    unittest.main()
