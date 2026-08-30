#!/usr/bin/env python3
"""Exit 0 if the whoami-v2 payload shows a token carrying the inference scope.

A 200 from whoami-v2 only proves the token is valid — a read-only token also
returns 200 and then fails at first inference call. Fine-grained tokens enumerate
their permissions, so check them properly; classic read/write tokens don't, so
pass them through and let the first real call decide.

Deliberately fails OPEN on any shape we can't read: rejecting a working token
because HF renamed a field is worse than deferring the error to the first call.
Only a fine-grained token that positively lacks the scope is rejected.
"""
import json
import sys

NEEDED = "inference.serverless.write"


def main() -> int:
    try:
        payload = json.load(open(sys.argv[1]))
    except (OSError, ValueError, IndexError):
        return 1
    token = (payload.get("auth") or {}).get("accessToken") or {}
    fine = token.get("fineGrained")
    if fine is None:
        return 0
    perms = set(fine.get("global") or [])
    for scope in fine.get("scoped") or []:
        perms |= set(scope.get("permissions") or [])
    return 0 if NEEDED in perms else 1


if __name__ == "__main__":
    sys.exit(main())
