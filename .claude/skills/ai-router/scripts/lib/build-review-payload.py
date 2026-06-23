#!/usr/bin/env python3
"""build-review-payload.py — turn verified findings into a GitHub PR review payload.

Reads verified findings JSON (output of verify-findings.py) on stdin and emits the
JSON body for `POST /repos/{owner}/{repo}/pulls/{pr}/reviews` on stdout.

Only `confirmed`/`partial` findings become inline comments (GitHub rejects comments
on lines outside the diff — which is exactly what `unverified` means). Unverified
findings are listed in the review body so nothing is silently dropped.

A `confirmed` finding that carries a `suggestion` (replacement code for its cited
lines) is rendered as a committable ```suggestion block. `partial` findings get a
plain comment — we won't offer a one-click apply we can't place exactly.

Args:
  --commit <sha>        head commit the review attaches to (required)
  --body-file <path>    summary markdown for the review body (required)
  --version <x.y>       skill version, for the marker (optional)
  --run-id <id>         run id, for the marker (optional)

Exit 0 on success; 64 usage; 65 malformed findings JSON.
"""
import argparse
import hashlib
import json
import sys


def finding_key(f):
    """Stable per-finding id, embedded in each comment's marker. fix-findings
    recomputes the same key to resolve exactly the threads it fixed (and only
    those). Must stay byte-identical to the bash computation in fix-findings.sh:
    sha1("<file>:<start>:<end>:<category>")[:12], where end falls back to start
    and category to "" — matching jq's `.end_line // .start_line` and
    `.category // ""` (handles missing OR null, which dict.get does not)."""
    path = (f.get("verify") or {}).get("resolved_file") or f.get("file") or ""
    start = f.get("start_line")
    end = f.get("end_line")
    if end is None:
        end = start
    cat = f.get("category") or ""
    raw = f"{path}:{start}:{end}:{cat}"
    return hashlib.sha1(raw.encode()).hexdigest()[:12]


def comment_body(f):
    sev = str(f.get("severity", "")).strip()
    cat = str(f.get("category", "")).strip()
    issue = str(f.get("issue", "")).strip()
    fix = str(f.get("fix", "")).strip()
    srcs = f.get("sources") or []
    head = f"**{sev}" + (f" · {cat}" if cat else "") + "**"
    if isinstance(srcs, list) and srcs:
        head += f"  _(flagged by {', '.join(str(s) for s in srcs)})_"
    body = head + (f"\n\n{issue}" if issue else "")
    if fix:
        body += f"\n\n**Fix:** {fix}"
    sugg = f.get("suggestion")
    if f.get("verify", {}).get("status") == "confirmed" and isinstance(sugg, str) and sugg.strip():
        body += "\n\n```suggestion\n" + sugg.rstrip("\n") + "\n```"
    # Hidden marker identifying ai-router's own threads (never a human's), plus a
    # per-finding key so the fixer can resolve exactly the threads it fixed.
    # Renders as nothing on GitHub.
    body += f"\n\n<!-- ai-router-finding key={finding_key(f)} -->"
    return body


def main(argv):
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--commit", required=True)
    ap.add_argument("--body-file", required=True)
    ap.add_argument("--version", default="")
    ap.add_argument("--run-id", default="")
    try:
        args = ap.parse_args(argv[1:])
    except SystemExit:
        return 64

    try:
        with open(args.body_file, "r", encoding="utf-8", errors="replace") as fh:
            summary = fh.read().rstrip("\n")
    except OSError as e:
        sys.stderr.write(f"build-review-payload.py: cannot read body {args.body_file}: {e}\n")
        return 64

    raw = sys.stdin.read()
    try:
        findings = json.loads(raw) if raw.strip() else []
        if not isinstance(findings, list):
            raise ValueError("findings JSON must be an array")
    except (json.JSONDecodeError, ValueError) as e:
        sys.stderr.write(f"build-review-payload.py: bad findings JSON: {e}\n")
        return 65

    comments = []
    excluded = []
    for f in findings:
        if not isinstance(f, dict):
            continue
        v = f.get("verify", {}) or {}
        status = v.get("status")
        if status in ("confirmed", "partial"):
            path = v.get("resolved_file") or f.get("file")
            # Only attach to verified ADDED lines (review-only-+code), never to
            # context lines that happen to be grounded.
            lines = sorted(set(v.get("added_lines") or []))
            if not path or not lines:
                excluded.append((f, "no groundable added line to attach to"))
                continue
            lo, hi = lines[0], lines[-1]
            c = {"path": path, "side": "RIGHT", "line": hi, "body": comment_body(f)}
            # Multi-line range only when the added lines are contiguous — GitHub
            # rejects a start_line..line span that isn't fully inside one hunk.
            if hi != lo and lines == list(range(lo, hi + 1)):
                c["start_line"] = lo
                c["start_side"] = "RIGHT"
            comments.append(c)
        else:
            excluded.append((f, (v.get("reason") or "not grounded")))

    body = ""
    if args.version:
        body += f"<!-- ai-router:review:inline v{args.version}"
        if args.run_id:
            body += f" run-id={args.run_id}"
        body += " -->\n\n"
    body += summary
    if excluded:
        body += "\n\n---\n### Not grounded — excluded from inline\n"
        body += "_These cite code outside the reviewed diff (often hallucinated or out of scope)._\n\n"
        for f, reason in excluded:
            sev = f.get("severity", "")
            file = (f.get("verify", {}) or {}).get("resolved_file") or f.get("file", "?")
            s, e = f.get("start_line", "?"), f.get("end_line", "?")
            issue = str(f.get("issue", "")).strip()
            body += f"- `{file}:{s}-{e}` **{sev}** — {issue}  _({reason})_\n"

    payload = {"commit_id": args.commit, "event": "COMMENT", "body": body, "comments": comments}
    sys.stdout.write(json.dumps(payload))
    # counts to stderr so the caller can report without parsing stdout
    sys.stderr.write(f"inline={len(comments)} excluded={len(excluded)}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
