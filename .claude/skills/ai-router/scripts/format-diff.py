#!/usr/bin/env python3
"""format-diff.py — reformat a unified diff into a line-numbered, hunk-split form.

Why: feeding a raw `git diff` to a model invites hallucinated line numbers and
"this might break X" guesses about code the model can't see. This reformat is the
anti-hallucination grounding primitive (technique adapted from PR-Agent, Apache-2.0):

  - Each file is announced with `## File: '<path>'`.
  - Each hunk is split into a `__new hunk__` section (the post-change code) and an
    optional `__old hunk__` section (the removed code).
  - Every `__new hunk__` line is prefixed with its ABSOLUTE new-file line number,
    so the model cites real lines and a later verify pass can map findings back to
    the working tree. The numbers are reference-only, not part of the code.

Deterministic, stdlib-only, read-only. No network, no writes, no LLM.

Usage:
    git diff -U8 <range> | python3 format-diff.py
    python3 format-diff.py < some.diff

Input:  a unified diff on stdin — `git diff` / `gh pr diff`.
Output: the reformatted diff on stdout.

stdin-only by design: it does not accept a file-path argument, so the
allowlisted invocation can't be turned into an arbitrary-file reader.

Exit codes:
    0  ok (including empty input -> empty output)
   64  usage error
"""
import re
import sys

HUNK_RE = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@(.*)$")


_OCTAL = set("01234567")
_C_ESCAPES = {"a": 7, "b": 8, "t": 9, "n": 10, "v": 11, "f": 12, "r": 13, '"': 34, "\\": 92}


def _unquote_git_path(p: str) -> str:
    # Git wraps paths containing special or non-ASCII bytes in double quotes and
    # C-escapes the contents (e.g. `"b/na\303\251me"`, `"a/with\ttab"`). Decode
    # back to a real path so the `## File:` header and `file:line` citations stay
    # accurate. Non-quoted paths pass through untouched.
    if not (len(p) >= 2 and p[0] == '"' and p[-1] == '"'):
        return p
    s = p[1:-1]
    out = bytearray()
    i = 0
    while i < len(s):
        c = s[i]
        if c == "\\" and i + 1 < len(s):
            nxt = s[i + 1]
            if nxt in _C_ESCAPES:
                out.append(_C_ESCAPES[nxt])
                i += 2
                continue
            if nxt in _OCTAL:
                j, digits = i + 1, ""
                while j < len(s) and len(digits) < 3 and s[j] in _OCTAL:
                    digits += s[j]
                    j += 1
                out.append(int(digits, 8) & 0xFF)
                i = j
                continue
            out.append(0x5C)  # unknown escape — keep the backslash
            i += 1
            continue
        out.extend(c.encode("utf-8"))
        i += 1
    try:
        return out.decode("utf-8")
    except UnicodeDecodeError:
        return out.decode("latin-1")


def _src_path(line: str) -> str:
    # "diff --git a/foo b/foo" -> "foo". Best-effort initial guess only: for quoted
    # or space-containing paths this line is ambiguous, so the authoritative path is
    # taken from the +++/--- markers in reformat(). Falls back to the a/ side.
    rest = line[len("diff --git ") :]
    idx = rest.rfind(" b/")
    if idx != -1:
        return _unquote_git_path(rest[idx + 1 :].strip())[2:]
    if rest.startswith("a/"):
        return _unquote_git_path(rest[2:].strip())
    return _unquote_git_path(rest.strip())


def _path_from_marker(line: str) -> str:
    # "+++ b/foo" / "--- a/foo" -> "foo"; "/dev/null" stays as-is. Dequote first,
    # because git wraps the whole token (prefix included): `+++ "b/na\303\251me"`.
    p = _unquote_git_path(line[4:].strip())
    if p.startswith(("a/", "b/")):
        p = p[2:]
    return p


def reformat(diff_text: str) -> str:
    lines = diff_text.splitlines()
    out = []
    i = 0
    n = len(lines)
    cur_path = None          # path announced via "## File:"
    pending_path = None      # from "diff --git", confirmed/overridden by +++/---
    pending_minus = None     # a-side path from "--- ", used for deletions
    file_is_binary = False
    in_file_header = False

    def announce(path):
        nonlocal cur_path
        if path and path != cur_path:
            if out:
                out.append("")
            out.append(f"## File: '{path}'")
            cur_path = path

    while i < n:
        line = lines[i]

        if line.startswith("diff --git "):
            pending_path = _src_path(line)   # fallback; overridden by +++/--- below
            pending_minus = None
            file_is_binary = False
            in_file_header = True
            i += 1
            continue

        # Within a file header, the +++/--- markers are the authoritative path
        # source — each names exactly one path, unlike the ambiguous "diff --git"
        # line (which breaks on quoted or space-containing names). The b-side (+++)
        # wins; for deletions (+++ /dev/null) we fall back to the a-side (---).
        # `---` precedes `+++` in the stream, so pending_minus is set in time.
        if in_file_header and line.startswith("--- "):
            p = _path_from_marker(line)
            if p and p != "/dev/null":
                pending_minus = p
            i += 1
            continue
        if in_file_header and line.startswith("+++ "):
            p = _path_from_marker(line)
            if p and p != "/dev/null":
                pending_path = p
            elif pending_minus:
                pending_path = pending_minus
            i += 1
            continue
        if line.startswith("Binary files ") or line.startswith("GIT binary patch"):
            file_is_binary = True
            i += 1
            continue
        if in_file_header and (
            line.startswith("index ")
            or line.startswith("old mode ")
            or line.startswith("new mode ")
            or line.startswith("new file mode ")
            or line.startswith("deleted file mode ")
            or line.startswith("similarity index ")
            or line.startswith("dissimilarity index ")
            or line.startswith("rename from ")
            or line.startswith("rename to ")
            or line.startswith("copy from ")
            or line.startswith("copy to ")
        ):
            i += 1
            continue

        m = HUNK_RE.match(line)
        if m:
            in_file_header = False
            if file_is_binary:
                i += 1
                continue
            announce(pending_path)
            new_line = int(m.group(1))
            section = m.group(3).rstrip()
            header = "@@ ... @@" + (f"{section}" if section else "")

            # Collect the body of this hunk.
            new_hunk = []
            old_hunk = []
            i += 1
            while i < n:
                bl = lines[i]
                if bl.startswith("@@ ") and HUNK_RE.match(bl):
                    break
                if bl.startswith("diff --git "):
                    break
                if bl.startswith("\\ "):  # "\ No newline at end of file"
                    i += 1
                    continue
                if not bl:
                    # Blank line inside a hunk == an unchanged empty line (" " eaten).
                    new_hunk.append(f"{new_line} ")
                    old_hunk.append(" ")
                    new_line += 1
                    i += 1
                    continue
                tag = bl[0]
                if tag == " ":
                    new_hunk.append(f"{new_line} {bl}")
                    old_hunk.append(bl)
                    new_line += 1
                elif tag == "+":
                    new_hunk.append(f"{new_line} {bl}")
                    new_line += 1
                elif tag == "-":
                    old_hunk.append(bl)
                else:
                    # Unexpected line; treat as context to stay robust.
                    new_hunk.append(f"{new_line}  {bl}")
                    old_hunk.append(f" {bl}")
                    new_line += 1
                i += 1

            out.append("")
            out.append(header)
            out.append("__new hunk__")
            out.extend(new_hunk)
            if any(l.startswith("-") for l in old_hunk):
                out.append("__old hunk__")
                out.extend(old_hunk)
            continue

        # Any other line outside a hunk (e.g. stray context) — skip quietly.
        i += 1

    # Trim leading blank line if present.
    while out and out[0] == "":
        out.pop(0)
    return "\n".join(out) + ("\n" if out else "")


def main(argv):
    if len(argv) == 2 and argv[1] in ("-h", "--help"):
        sys.stderr.write(__doc__ + "\n")
        return 0
    if len(argv) > 1:
        # stdin-only by design — no file-path argument. This keeps the
        # `format-diff.py:*` auto-mode allow-rule from being usable to read an
        # arbitrary file into the session.
        sys.stderr.write(
            "usage: format-diff.py < diff   (reads a unified diff from stdin)\n"
            "note: stdin-only — does not accept a file-path argument.\n"
        )
        return 64
    data = sys.stdin.read()
    sys.stdout.write(reformat(data))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
