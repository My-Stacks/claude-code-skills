#!/usr/bin/env python3
"""finding_key.py — the single source of truth for a finding's stable id.

key = sha1("<file>:<start>:<end>:<category>")[:12]
where <file> = verify.resolved_file if present else file, <end> falls back to
<start>, and <category> falls back to "".

The key is embedded in each inline comment's marker by build-review-payload.py
(which imports `key_from_finding`) and recomputed by fix-findings.sh (which calls
the CLI form) so the fixer resolves exactly the threads it fixed. Both paths go
through THIS file — there is no second implementation to drift out of sync.

Import:  from finding_key import finding_key, key_from_finding
CLI:     python3 finding_key.py <file> <start> [<end>] [<category>]   -> prints key
"""
import hashlib
import sys


def finding_key(file, start, end=None, category=None):
    if end is None or end == "":
        end = start
    return hashlib.sha1(f"{file}:{start}:{end}:{category or ''}".encode()).hexdigest()[:12]


def key_from_finding(f):
    path = (f.get("verify") or {}).get("resolved_file") or f.get("file") or ""
    return finding_key(path, f.get("start_line"), f.get("end_line"), f.get("category"))


if __name__ == "__main__":
    a = sys.argv[1:]
    file = a[0] if len(a) > 0 else ""
    start = a[1] if len(a) > 1 else ""
    end = a[2] if len(a) > 2 else ""
    category = a[3] if len(a) > 3 else ""
    print(finding_key(file, start, end, category))
