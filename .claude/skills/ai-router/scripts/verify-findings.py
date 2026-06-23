#!/usr/bin/env python3
"""verify-findings.py — deterministically ground ensemble review findings.

Phase 2 of the grounded-review pipeline. PR-Agent can only *approximate* this with
an LLM self-reflection pass because it has no repo access. ai-router runs in the repo,
so it can check findings against the actual reviewed code — for free, no LLM, no
network. This is the anti-hallucination guarantee: a finding is only trusted if it
cites a line the model was actually shown.

Ground truth = the grounded diff produced by format-diff.py (the exact bytes the
models reviewed). We verify against the diff, NOT the working tree, because a review
of a PR *number* may run from a different branch — the diff is always correct, the
working tree may not be.

Input:  findings JSON array on stdin, each:
          {"severity","category","file","start_line","end_line","issue","fix",
           "suggestion"(optional),"sources"(optional)}
Args:   --diff <path>   the grounded diff from format-diff.py (required)

Output: the same array on stdout, each finding annotated with:
          "verify": {
            "status": "confirmed" | "partial" | "unverified",
            "lines_grounded": [int,...],     # cited lines that were in the diff
            "added_lines":     [int,...],    # subset that were '+' (safe for inline)
            "shown_code": "...",             # the real code at the grounded lines
            "reason": "..."
          }

status: confirmed = every cited line was in the diff; partial = some were;
unverified = file not in the PR diff, or none of the cited lines were shown
(the usual signature of a hallucinated or out-of-scope finding).

Deterministic, stdlib-only, read-only. Exit 0 on success; 64 on usage error;
65 on malformed findings JSON.
"""
import argparse
import json
import re
import sys

FILE_RE = re.compile(r"^## File: '(.*)'$")
NUM_RE = re.compile(r"^(\d+) (.*)$")


def index_diff(diff_text):
    """path -> {line_no: {'code': str, 'added': bool}} for every shown __new hunk__ line."""
    index = {}
    cur = None
    in_new = False
    for line in diff_text.splitlines():
        m = FILE_RE.match(line)
        if m:
            cur = m.group(1)
            index.setdefault(cur, {})
            in_new = False
            continue
        if line == "__new hunk__":
            in_new = True
            continue
        if line == "__old hunk__" or line.startswith("@@ ") or line.startswith("## File:"):
            in_new = False
            continue
        if in_new and cur is not None:
            nm = NUM_RE.match(line)
            if nm:
                n = int(nm.group(1))
                body = nm.group(2)            # marker + code, e.g. "+    x = 1" or "  x = 1"
                added = body[:1] == "+"
                code = body[1:] if body[:1] in ("+", " ") else body
                index[cur][n] = {"code": code, "added": added}
    return index


def resolve_path(file_field, index):
    """Match a finding's file to a diff path: exact, else unique suffix/basename match."""
    if file_field in index:
        return file_field
    # tolerate a leading ./ or differing prefix depth
    cands = [p for p in index if p.endswith(file_field) or file_field.endswith(p)]
    if len(cands) == 1:
        return cands[0]
    base = file_field.rsplit("/", 1)[-1]
    cands = [p for p in index if p.rsplit("/", 1)[-1] == base]
    if len(cands) == 1:
        return cands[0]
    return None


def verify_one(f, index):
    file_field = str(f.get("file", "")).strip()
    try:
        start = int(f.get("start_line"))
        end = int(f.get("end_line", f.get("start_line")))
    except (TypeError, ValueError):
        return {"status": "unverified", "lines_grounded": [], "added_lines": [],
                "shown_code": "", "reason": "finding has no usable start_line/end_line"}
    if end < start:
        start, end = end, start

    path = resolve_path(file_field, index)
    if path is None:
        return {"status": "unverified", "lines_grounded": [], "added_lines": [],
                "shown_code": "",
                "reason": f"file '{file_field}' is not in the PR diff (not reviewed)"}

    shown = [n for n in range(start, end + 1) if n in index[path]]
    added = [n for n in shown if index[path][n]["added"]]
    code = "\n".join(index[path][n]["code"] for n in shown)
    span = end - start + 1

    if not shown:
        return {"status": "unverified", "lines_grounded": [], "added_lines": [],
                "shown_code": "",
                "reason": f"lines {start}-{end} of '{path}' were not in the shown diff"}
    if len(shown) == span:
        reason = f"all {span} cited line(s) present in the diff"
        status = "confirmed"
    else:
        reason = f"{len(shown)}/{span} cited lines present in the diff"
        status = "partial"
    return {"status": status, "lines_grounded": shown, "added_lines": added,
            "shown_code": code, "reason": reason, "resolved_file": path}


def main(argv):
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--diff", required=True, help="grounded diff from format-diff.py")
    try:
        args = ap.parse_args(argv[1:])
    except SystemExit:
        return 64

    try:
        with open(args.diff, "r", encoding="utf-8", errors="replace") as fh:
            diff_text = fh.read()
    except OSError as e:
        sys.stderr.write(f"verify-findings.py: cannot read diff {args.diff}: {e}\n")
        return 64

    raw = sys.stdin.read()
    if not raw.strip():
        sys.stdout.write("[]")
        return 0
    try:
        findings = json.loads(raw)
        if not isinstance(findings, list):
            raise ValueError("findings JSON must be an array")
    except (json.JSONDecodeError, ValueError) as e:
        sys.stderr.write(f"verify-findings.py: bad findings JSON: {e}\n")
        return 65

    index = index_diff(diff_text)
    for f in findings:
        if isinstance(f, dict):
            f["verify"] = verify_one(f, index)
    sys.stdout.write(json.dumps(findings, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
