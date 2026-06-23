"""verify-findings.py — ground findings against the reviewed diff.

Covers: confirmed/partial/unverified/invalid, path resolution (exact, safe
suffix, wrong-dir-same-basename rejected, empty path), schema gate, line
normalization, added-vs-context, malformed JSON, empty input, usage error.
"""
import json
import os
import tempfile
import unittest

from _util import run

DIFF = (
    "## File: 'src/auth.py'\n\n"
    "@@ ... @@ def login(user):\n"
    "__new hunk__\n"
    "10      ctx_before\n"
    "11 +    added_one\n"
    "12 +    added_two\n"
    "13      ctx_after\n"
    "## File: 'pkg/util.py'\n\n"
    "@@ ... @@\n"
    "__new hunk__\n"
    "5 +    only_added\n"
)


def verify(findings, diff=DIFF):
    with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as f:
        f.write(diff)
        path = f.name
    try:
        rc, out, err = run("verify-findings.py", args=["--diff", path], stdin=json.dumps(findings))
        return rc, out, err
    finally:
        os.unlink(path)


def verify_ok(findings, diff=DIFF):
    rc, out, err = verify(findings, diff)
    assert rc == 0, f"exit {rc}: {err}"
    return json.loads(out)


def F(**kw):
    base = {"severity": "NIT", "category": "correctness", "file": "src/auth.py",
            "start_line": 11, "end_line": 11, "issue": "x"}
    base.update(kw)
    return base


class TestVerifyFindings(unittest.TestCase):
    def test_confirmed_all_lines_shown(self):
        v = verify_ok([F(start_line=11, end_line=12)])[0]["verify"]
        self.assertEqual(v["status"], "confirmed")
        self.assertEqual(v["lines_grounded"], [11, 12])
        self.assertEqual(v["added_lines"], [11, 12])
        self.assertIn("added_one", v["shown_code"])

    def test_partial_some_lines_shown(self):
        # 12,13,14 -> 12,13 in diff, 14 not -> partial
        v = verify_ok([F(start_line=12, end_line=14)])[0]["verify"]
        self.assertEqual(v["status"], "partial")
        self.assertEqual(v["lines_grounded"], [12, 13])

    def test_context_line_grounded_but_not_added(self):
        # line 10 is context (shown, not '+')
        v = verify_ok([F(start_line=10, end_line=10)])[0]["verify"]
        self.assertEqual(v["status"], "confirmed")
        self.assertEqual(v["added_lines"], [])
        self.assertEqual(v["lines_grounded"], [10])

    def test_unverified_file_not_in_diff(self):
        v = verify_ok([F(file="src/ghost.py")])[0]["verify"]
        self.assertEqual(v["status"], "unverified")
        self.assertIn("not in the PR diff", v["reason"])

    def test_unverified_lines_not_shown(self):
        v = verify_ok([F(start_line=99, end_line=99)])[0]["verify"]
        self.assertEqual(v["status"], "unverified")

    def test_invalid_missing_file(self):
        f = F(); del f["file"]
        v = verify_ok([f])[0]["verify"]
        self.assertEqual(v["status"], "invalid")
        self.assertIn("file", v["reason"])

    def test_invalid_missing_start_line(self):
        f = F(); del f["start_line"]
        v = verify_ok([f])[0]["verify"]
        self.assertEqual(v["status"], "invalid")
        self.assertIn("start_line", v["reason"])

    def test_invalid_non_int_start_line(self):
        v = verify_ok([F(start_line="abc")])[0]["verify"]
        self.assertEqual(v["status"], "invalid")

    def test_invalid_start_line_zero(self):
        v = verify_ok([F(start_line=0, end_line=0)])[0]["verify"]
        self.assertEqual(v["status"], "invalid")

    def test_end_before_start_swapped(self):
        v = verify_ok([F(start_line=12, end_line=11)])[0]["verify"]
        self.assertEqual(v["status"], "confirmed")
        self.assertEqual(v["lines_grounded"], [11, 12])

    def test_path_exact_match_resolved(self):
        v = verify_ok([F(file="src/auth.py", start_line=11, end_line=11)])[0]["verify"]
        self.assertEqual(v["status"], "confirmed")
        self.assertEqual(v["resolved_file"], "src/auth.py")

    def test_path_safe_suffix_match(self):
        # finding cites a prefix-trimmed path -> resolves to the diff path
        v = verify_ok([F(file="auth.py", start_line=11, end_line=11)])[0]["verify"]
        self.assertEqual(v["status"], "confirmed")
        self.assertEqual(v["resolved_file"], "src/auth.py")

    def test_path_wrong_dir_same_basename_not_matched(self):
        # 'other/auth.py' must NOT ground to 'src/auth.py'
        v = verify_ok([F(file="other/auth.py", start_line=11, end_line=11)])[0]["verify"]
        self.assertEqual(v["status"], "unverified")

    def test_path_partial_filename_not_matched(self):
        # 'th.py' is a substring of 'auth.py' but not a path-boundary suffix
        v = verify_ok([F(file="th.py", start_line=11, end_line=11)])[0]["verify"]
        self.assertEqual(v["status"], "unverified")

    def test_malformed_json_exit_65(self):
        rc, out, err = verify("not json at all")  # passed as raw stdin via json.dumps? no
        # send raw malformed via direct run
        import tempfile as _t
        with _t.NamedTemporaryFile("w", suffix=".txt", delete=False) as fh:
            fh.write(DIFF); p = fh.name
        try:
            rc, out, err = run("verify-findings.py", args=["--diff", p], stdin="{not json")
        finally:
            os.unlink(p)
        self.assertEqual(rc, 65)

    def test_non_array_json_exit_65(self):
        with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as fh:
            fh.write(DIFF); p = fh.name
        try:
            rc, out, err = run("verify-findings.py", args=["--diff", p], stdin='{"a":1}')
        finally:
            os.unlink(p)
        self.assertEqual(rc, 65)

    def test_empty_input_empty_array(self):
        with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as fh:
            fh.write(DIFF); p = fh.name
        try:
            rc, out, err = run("verify-findings.py", args=["--diff", p], stdin="")
        finally:
            os.unlink(p)
        self.assertEqual(rc, 0)
        self.assertEqual(json.loads(out), [])

    def test_missing_diff_arg_usage_error(self):
        rc, out, err = run("verify-findings.py", stdin="[]")
        self.assertEqual(rc, 64)


if __name__ == "__main__":
    unittest.main()
