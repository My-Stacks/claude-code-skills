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
    python3 format-diff.py some.diff

Input:  a unified diff on stdin (or a file path arg) — `git diff` / `gh pr diff`.
Output: the reformatted diff on stdout.

Exit codes:
    0  ok (including empty input -> empty output)
   64  usage error
"""
import re
import sys

HUNK_RE = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@(.*)$")


def _src_path(line: str) -> str:
    # "diff --git a/foo b/foo" -> "foo". Handles paths with spaces by taking the
    # b/ side from the last " b/" occurrence; falls back to the a/ side.
    rest = line[len("diff --git ") :]
    idx = rest.rfind(" b/")
    if idx != -1:
        return rest[idx + 3 :].strip()
    if rest.startswith("a/"):
        return rest[2:].strip()
    return rest.strip()


def _path_from_marker(line: str) -> str:
    # "+++ b/foo" / "--- a/foo" -> "foo"; "/dev/null" stays as-is.
    p = line[4:].strip()
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
            pending_path = _src_path(line)
            file_is_binary = False
            in_file_header = True
            i += 1
            continue

        # Within a file header, learn the real path and skip git metadata lines.
        if in_file_header and line.startswith("+++ "):
            p = _path_from_marker(line)
            if p and p != "/dev/null":
                pending_path = p
            i += 1
            continue
        if in_file_header and line.startswith("--- "):
            # For deletions (+++ /dev/null) the a/ path is the meaningful one.
            p = _path_from_marker(line)
            if p and p != "/dev/null":
                pending_path = pending_path or p
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
    if len(argv) > 2:
        sys.stderr.write("usage: format-diff.py [diff-file]   (or pipe diff on stdin)\n")
        return 64
    if len(argv) == 2:
        if argv[1] in ("-h", "--help"):
            sys.stderr.write(__doc__)
            return 0
        try:
            with open(argv[1], "r", encoding="utf-8", errors="replace") as f:
                data = f.read()
        except OSError as e:
            sys.stderr.write(f"format-diff.py: cannot read {argv[1]}: {e}\n")
            return 64
    else:
        data = sys.stdin.read()
    sys.stdout.write(reformat(data))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
