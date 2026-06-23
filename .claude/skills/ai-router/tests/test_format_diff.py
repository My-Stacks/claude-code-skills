"""format-diff.py — diff → line-numbered, hunk-split grounded form.

Covers: line numbering, new/deleted/renamed/binary files, quoted (C-escaped)
paths, no-newline marker, multiple files/hunks, empty input, stdin-only, --help.
"""
import unittest

from _util import run


def fmt(diff):
    rc, out, err = run("format-diff.py", stdin=diff)
    assert rc == 0, f"exit {rc}: {err}"
    return out


class TestFormatDiff(unittest.TestCase):
    def test_modify_numbers_new_hunk_and_keeps_old(self):
        diff = (
            "diff --git a/src/auth.py b/src/auth.py\n"
            "--- a/src/auth.py\n+++ b/src/auth.py\n"
            "@@ -10,3 +10,4 @@ def login(user):\n"
            "     token = make(user)\n"
            "-    cache.set(user.id, token)\n"
            "+    cache.set(user.id, token, ttl=1)\n"
            "+    audit(user.id)\n"
            "     return token\n"
        )
        out = fmt(diff)
        self.assertIn("## File: 'src/auth.py'", out)
        self.assertIn("__new hunk__", out)
        self.assertIn("__old hunk__", out)
        # absolute new-file line numbers, added lines marked
        self.assertIn("10      token = make(user)", out)
        self.assertIn("11 +    cache.set(user.id, token, ttl=1)", out)
        self.assertIn("12 +    audit(user.id)", out)
        self.assertIn("13      return token", out)
        # removed line only in old hunk, no number
        self.assertIn("-    cache.set(user.id, token)", out)
        self.assertIn("@@ ... @@ def login(user):", out)

    def test_new_file_has_no_old_hunk(self):
        diff = (
            "diff --git a/new.py b/new.py\nnew file mode 100644\n"
            "--- /dev/null\n+++ b/new.py\n@@ -0,0 +1,2 @@\n+a = 1\n+b = 2\n"
        )
        out = fmt(diff)
        self.assertIn("## File: 'new.py'", out)
        self.assertIn("1 +a = 1", out)
        self.assertIn("2 +b = 2", out)
        self.assertNotIn("__old hunk__", out)

    def test_deleted_file_keeps_old_hunk(self):
        diff = (
            "diff --git a/gone.txt b/gone.txt\ndeleted file mode 100644\n"
            "--- a/gone.txt\n+++ /dev/null\n@@ -1,2 +0,0 @@\n-one\n-two\n"
        )
        out = fmt(diff)
        self.assertIn("## File: 'gone.txt'", out)
        self.assertIn("__old hunk__", out)
        self.assertIn("-one", out)

    def test_binary_file_skipped(self):
        diff = (
            "diff --git a/logo.png b/logo.png\n"
            "Binary files a/logo.png and b/logo.png differ\n"
        )
        out = fmt(diff)
        self.assertNotIn("logo.png", out)
        self.assertEqual(out.strip(), "")

    def test_quoted_unicode_path_decoded(self):
        # git C-quotes non-ASCII: "b/src/na\303\251me.py" -> src/naéme.py
        diff = (
            'diff --git "a/src/na\\303\\251me.py" "b/src/na\\303\\251me.py"\n'
            '--- "a/src/na\\303\\251me.py"\n+++ "b/src/na\\303\\251me.py"\n'
            "@@ -1 +1,2 @@\n x = 1\n+y = 2\n"
        )
        out = fmt(diff)
        self.assertIn("## File: 'src/naéme.py'", out)
        self.assertNotIn('"', out)

    def test_quoted_tab_path_on_deletion_uses_a_side(self):
        diff = (
            'diff --git "a/od\\tfile.txt" "b/od\\tfile.txt"\ndeleted file mode 100644\n'
            '--- "a/od\\tfile.txt"\n+++ /dev/null\n@@ -1 +0,0 @@\n-gone\n'
        )
        out = fmt(diff)
        self.assertIn("## File: 'od\tfile.txt'", out)

    def test_no_newline_marker_ignored(self):
        diff = (
            "diff --git a/f.txt b/f.txt\n--- a/f.txt\n+++ b/f.txt\n"
            "@@ -1 +1 @@\n-old\n+new\n\\ No newline at end of file\n"
        )
        out = fmt(diff)
        self.assertIn("1 +new", out)
        self.assertNotIn("No newline", out)

    def test_multiple_files_and_hunks(self):
        diff = (
            "diff --git a/x.py b/x.py\n--- a/x.py\n+++ b/x.py\n"
            "@@ -1 +1 @@\n-a\n+A\n"
            "@@ -5 +5 @@\n-b\n+B\n"
            "diff --git a/y.py b/y.py\n--- a/y.py\n+++ b/y.py\n"
            "@@ -1 +1 @@\n-c\n+C\n"
        )
        out = fmt(diff)
        self.assertEqual(out.count("## File:"), 2)
        self.assertIn("## File: 'x.py'", out)
        self.assertIn("## File: 'y.py'", out)
        self.assertEqual(out.count("__new hunk__"), 3)

    def test_empty_input_empty_output(self):
        rc, out, err = run("format-diff.py", stdin="")
        self.assertEqual(rc, 0)
        self.assertEqual(out, "")

    def test_non_diff_text_yields_nothing(self):
        # robustness: garbage in -> no hunks announced, no crash
        rc, out, err = run("format-diff.py", stdin="just some\nrandom text\n")
        self.assertEqual(rc, 0)
        self.assertEqual(out.strip(), "")

    def test_stdin_only_rejects_file_arg(self):
        rc, out, err = run("format-diff.py", args=["/etc/hosts"])
        self.assertEqual(rc, 64)
        self.assertIn("stdin-only", err)

    def test_help_exits_zero(self):
        rc, out, err = run("format-diff.py", args=["--help"])
        self.assertEqual(rc, 0)


if __name__ == "__main__":
    unittest.main()
