#!/usr/bin/env python3
"""Budget math for a model across every provider serving it. Reads /v1/models on stdin."""
import json
import sys


def main() -> int:
    if len(sys.argv) != 5:
        print("usage: cost.py <org/model> <in_tokens> <out_tokens> <calls>", file=sys.stderr)
        return 2
    want = sys.argv[1].lower()
    i_tok, o_tok, calls = (float(x.replace(",", "")) for x in sys.argv[2:5])

    models = json.load(sys.stdin).get("data", [])
    model = next((m for m in models if m["id"].lower() == want), None)
    if model is None:
        print("not found — check the id with: hf.sh models <substring>")
        return 1

    rows = []
    for p in model.get("providers", []):
        pr = p.get("pricing") or {}
        if pr.get("input") is None or pr.get("output") is None:
            continue
        per = (i_tok * pr["input"] + o_tok * pr["output"]) / 1e6
        rows.append({
            "total": per * calls, "per": per, "prov": p.get("provider") or "?",
            "struct": p.get("supports_structured_output"),
            "ctx": p.get("context_length"), "tps": p.get("throughput"),
        })
    if not rows:
        print(f"{model['id']}: no provider publishes pricing")
        return 1
    rows.sort(key=lambda r: r["total"])

    print(f"{model['id']}  |  {i_tok:,.0f} in + {o_tok:,.0f} out  x  {calls:,.0f} calls")
    print()
    print(f"  {'PROVIDER':14s} {'TOTAL':>12s} {'PER CALL':>12s} {'STRUCT':>7s} {'CTX':>10s} {'TOK/S':>7s}")
    for r in rows:
        ctx = f"{r['ctx']:,}" if r["ctx"] else "-"
        flag = "  << input exceeds context" if r["ctx"] and i_tok > r["ctx"] else ""
        tps = f"{r['tps']:.0f}" if r["tps"] else "-"
        struct = str(r["struct"]) if r["struct"] is not None else "-"
        total = "$" + format(r["total"], ",.2f")
        per = "$" + format(r["per"], ".6f")
        print(f"  {r['prov']:14s} {total:>12s} {per:>12s} {struct:>7s} {ctx:>10s} {tps:>7s}{flag}")

    lo, hi = rows[0], rows[-1]
    print()
    print(f"  cheapest: {lo['prov']} ${lo['total']:,.2f}   priciest: {hi['prov']} ${hi['total']:,.2f}"
          + (f"   spread {hi['total'] / lo['total']:.1f}x" if lo["total"] else ""))
    if any(r["struct"] is False for r in rows):
        bad = [r["prov"] for r in rows if r["struct"] is False]
        print(f"  no structured output on: {', '.join(bad)} — pin a provider if you parse a schema")
    return 0


if __name__ == "__main__":
    sys.exit(main())
