#!/usr/bin/env python3
"""Interactive model picker. Reads /v1/models on stdin, prints the chosen id to stdout.

The menu and prompt go to stderr so the choice can be captured:
    MODEL=$(hf.sh pick qwen)
Reads the answer from /dev/tty when available, so it still works inside $(...).
Set HF_PICK to answer non-interactively (used by tests).
"""
import json
import os
import sys

CURATED = {
    "openai/gpt-oss-120b": "fast + cheap, but reasoning inflates output",
    "openai/gpt-oss-20b": "cheapest usable",
    "Qwen/Qwen3-4B-Instruct-2507": "tiny, no reasoning — best for schema filling",
    "deepseek-ai/DeepSeek-V4-Flash-0731": "cheap 1M context",
    "zai-org/GLM-5.3-Flash": "1M context, whole-corpus reads",
    "google/gemma-3-12b-it": "cheapest vision + tools + schema",
    "Qwen/Qwen3-Coder-Next": "mechanical code work",
    "deepseek-ai/DeepSeek-V4-Pro": "strong all-round, MIT",
    "zai-org/GLM-5.3": "security / long-horizon reasoning",
    "moonshotai/Kimi-K3": "best open agentic + tool use",
}


def rows_from(data, needle):
    out = []
    for m in data:
        if needle and needle not in m["id"].lower():
            continue
        priced = [p for p in m.get("providers", []) if (p.get("pricing") or {}).get("input") is not None]
        if not priced:
            continue
        cheap = min(priced, key=lambda p: p["pricing"]["input"])
        ctxs = [p.get("context_length") for p in m.get("providers", []) if p.get("context_length")]
        arch = m.get("architecture") or {}
        out.append({
            "id": m["id"],
            "in": cheap["pricing"]["input"],
            "out": cheap["pricing"].get("output") or 0,
            "ctx": max(ctxs) if ctxs else 0,
            "vision": "image" in (arch.get("input_modalities") or []),
            "struct": any(p.get("supports_structured_output") for p in m.get("providers", [])),
        })
    out.sort(key=lambda r: r["in"])
    return out


def main() -> int:
    needle = (sys.argv[1].lower() if len(sys.argv) > 1 else "")
    data = json.load(sys.stdin).get("data", [])
    rows = rows_from(data, needle)
    if not needle:
        # no filter: show the curated shortlist, and say how to see everything
        keep = [r for r in rows if r["id"] in CURATED]
        rows = keep or rows
    if not rows:
        print(f"nothing matches {needle!r} — try `hf.sh models` to browse", file=sys.stderr)
        return 1

    e = sys.stderr
    print(f"\n  {'#':>3}  {'MODEL':44s} {'IN':>7s} {'OUT':>7s} {'CTX':>6s}  CAPS", file=e)
    for i, r in enumerate(rows, 1):
        caps = ("V" if r["vision"] else "·") + ("S" if r["struct"] else "·")
        ctx = f"{r['ctx']//1000}k" if r["ctx"] else "-"
        note = CURATED.get(r["id"], "")
        print(f"  {i:>3}  {r['id']:44s} {r['in']:7.3f} {r['out']:7.2f} {ctx:>6s}  {caps}"
              + (f"  {note}" if note else ""), file=e)
    if not needle:
        print("\n  (shortlist — `hf.sh pick <filter>` or `hf.sh models` for all)", file=e)
    print(f"\n  in/out = USD per 1M tokens, cheapest provider. V=vision S=structured-output", file=e)
    print(f"  pick 1-{len(rows)} (or q): ", end="", file=e)
    e.flush()

    forced = os.environ.get("HF_PICK")
    if forced is not None:
        ans = forced
        print(ans, file=e)
    else:
        try:
            with open("/dev/tty") as tty:
                ans = tty.readline()
        except OSError:
            ans = sys.stdin.readline()
    ans = (ans or "").strip()
    if not ans or ans.lower().startswith("q"):
        print("cancelled", file=e)
        return 1
    if not ans.isdigit() or not (1 <= int(ans) <= len(rows)):
        print(f"not a valid choice: {ans}", file=e)
        return 1
    print(rows[int(ans) - 1]["id"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
