#!/usr/bin/env bash
# hf-models: thin wrapper over the Hugging Face Inference Providers router.
# One script = one permissions.allow rule for Claude Code auto-mode.
set -euo pipefail

ROUTER="https://router.huggingface.co/v1"
CONFIG="${HF_MODELS_CONFIG:-$HOME/.hf-router.json}"

die() { echo "hf: $*" >&2; exit 1; }

token() {
  if [ -n "${HF_TOKEN:-}" ]; then printf '%s' "$HF_TOKEN"; return; fi
  if [ -f "$CONFIG" ]; then
    python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("hf_token",""))' "$CONFIG"
    return
  fi
  printf ''
}

need_token() {
  local t; t="$(token)"
  [ -n "$t" ] || die "no token. Set HF_TOKEN, or run: hf.sh setup <hf_xxx>"
  printf '%s' "$t"
}

cmd_setup() {
  [ $# -ge 1 ] || die "usage: hf.sh setup <hf_token>"
  local t="$1"
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 \
    -H "Authorization: Bearer $t" "https://huggingface.co/api/whoami-v2")
  [ "$code" = "200" ] || die "token rejected (HTTP $code). Needs 'Make calls to Inference Providers' permission."
  ( umask 077
    HF_TOK="$t" python3 -c '
import json,os,sys
p=sys.argv[1]
cfg={}
if os.path.exists(p):
    try: cfg=json.load(open(p))
    except Exception: cfg={}
cfg["hf_token"]=os.environ["HF_TOK"]
json.dump(cfg,open(p,"w"),indent=2)
' "$CONFIG" )
  echo "hf-models configured -> $CONFIG (chmod 600)"
}

# models [substring]  — warm models with live per-provider pricing. No auth needed.
cmd_models() {
  local filter="${1:-}"
  curl -s --max-time 45 "$ROUTER/models" | FILTER="$filter" python3 -c '
import sys,json,os
f=os.environ.get("FILTER","").lower()
rows=[]
for m in json.load(sys.stdin).get("data",[]):
    if f and f not in m["id"].lower(): continue
    best=None
    for p in m.get("providers",[]):
        pr=p.get("pricing") or {}
        i,o=pr.get("input"),pr.get("output")
        if i is None: continue
        if best is None or i<best[1]: best=(p.get("provider"),i,o,p.get("context_length"),p.get("supports_tools"))
    if best: rows.append((m["id"],)+best)
rows.sort(key=lambda r:r[2])
print(f'"'"'{"MODEL":42s} {"PROV":13s} {"IN":>7s} {"OUT":>7s} {"CTX":>9s}  TOOLS'"'"')
for id_,prov,i,o,ctx,tools in rows:
    print(f"{id_:42s} {prov:13s} {i:7.3f} {(o or 0):7.3f} {(ctx or 0):9,d}  {bool(tools)}")
print(f"\n{len(rows)} models with published pricing.")
'
}

# price <model>  — every provider serving one model.
cmd_price() {
  [ $# -ge 1 ] || die "usage: hf.sh price <org/model>"
  curl -s --max-time 45 "$ROUTER/models" | MODEL="$1" python3 -c '
import sys,json,os
want=os.environ["MODEL"].lower()
for m in json.load(sys.stdin).get("data",[]):
    if m["id"].lower()!=want: continue
    print(m["id"])
    print("  {:14s} {:>7s} {:>7s} {:>10s} {:>6s} {:>7s} {:>8s} {:>7s}  {}".format(
        "PROVIDER","IN","OUT","CTX","TOOLS","STRUCT","TTFT_MS","TOK/S","STATUS"))
    def n(v, f="{:.0f}"):
        return "-" if v is None else f.format(v)
    for p in sorted(m.get("providers",[]), key=lambda x:((x.get("pricing") or {}).get("input") is None,
                                                          (x.get("pricing") or {}).get("input") or 0)):
        pr=p.get("pricing") or {}
        print("  {:14s} {:>7s} {:>7s} {:>10s} {:>6s} {:>7s} {:>8s} {:>7s}  {}".format(
            p.get("provider") or "?",
            n(pr.get("input"),"{:.3f}"), n(pr.get("output"),"{:.3f}"),
            n(p.get("context_length"),"{:,.0f}"),
            str(p.get("supports_tools")) if p.get("supports_tools") is not None else "-",
            str(p.get("supports_structured_output")) if p.get("supports_structured_output") is not None else "-",
            n(p.get("first_token_latency_ms")), n(p.get("throughput")),
            p.get("status")))
    if p.get("is_free"): print("  (a provider is currently free — promo, do not depend on it)")
    break
else:
    print("not found — check the exact repo id with: hf.sh models <substring>")
'
}

# ask <model> [prompt-file]  — prompt from file or stdin. Never via argv.
cmd_ask() {
  [ $# -ge 1 ] || die "usage: hf.sh ask <model> [prompt-file]   (stdin if no file)"
  local model="$1"; shift
  local prompt
  if [ $# -ge 1 ] && [ -f "$1" ]; then prompt="$(cat "$1")"; else prompt="$(cat)"; fi
  [ -n "$prompt" ] || die "empty prompt"
  local t; t="$(need_token)"
  local body
  body=$(MODEL="$model" PROMPT="$prompt" SYS="${HF_SYSTEM:-}" MAXTOK="${HF_MAX_TOKENS:-4096}" \
    python3 -c '
import json,os
msgs=[]
if os.environ.get("SYS"): msgs.append({"role":"system","content":os.environ["SYS"]})
msgs.append({"role":"user","content":os.environ["PROMPT"]})
print(json.dumps({"model":os.environ["MODEL"],"messages":msgs,
                  "max_tokens":int(os.environ["MAXTOK"]),"stream":False}))')
  curl -s --max-time "${HF_TIMEOUT:-600}" "$ROUTER/chat/completions" \
    -H "Authorization: Bearer $t" -H 'Content-Type: application/json' \
    -d "$body" | python3 -c '
import sys,json
d=json.load(sys.stdin)
if "error" in d: print("API error:",json.dumps(d["error"])[:500]); raise SystemExit(1)
c=d["choices"][0]["message"]
print(c.get("content") or "")
u=d.get("usage") or {}
print("\n--- {} | in={} out={} ---".format(
    d.get("model","?"), u.get("prompt_tokens"), u.get("completion_tokens")), file=sys.stderr)
'
}

# compare <m1,m2,...> [prompt-file] — same prompt to N models, one file each.
cmd_compare() {
  [ $# -ge 1 ] || die "usage: hf.sh compare <m1,m2,...> [prompt-file]"
  local models="$1"; shift
  local tmp; tmp="$(mktemp -d "${TMPDIR:-/tmp}/hf-compare-XXXXXX")"
  if [ $# -ge 1 ] && [ -f "$1" ]; then cp "$1" "$tmp/prompt.txt"; else cat > "$tmp/prompt.txt"; fi
  echo "run dir: $tmp"
  local pids=()
  IFS=',' read -ra arr <<< "$models"
  for m in "${arr[@]}"; do
    local safe="${m//\//_}"; safe="${safe//:/-}"
    ( cmd_ask "$m" "$tmp/prompt.txt" > "$tmp/$safe.md" 2> "$tmp/$safe.err" \
      || echo "FAILED: see $tmp/$safe.err" > "$tmp/$safe.md" ) &
    pids+=("$!")
  done
  for p in "${pids[@]}"; do wait "$p" || true; done
  for f in "$tmp"/*.md; do echo; echo "===== $(basename "$f" .md) ====="; cat "$f"; done
}

# cost <model> <in_tok> <out_tok> <calls> — budget math across providers. No auth.
cmd_cost() {
  [ $# -ge 4 ] || die "usage: hf.sh cost <org/model> <in_tokens> <out_tokens> <calls>"
  curl -s --max-time 45 "$ROUTER/models" \
    | python3 "$(dirname "${BASH_SOURCE[0]}")/cost.py" "$1" "$2" "$3" "$4"
}

case "${1:-help}" in
  setup)   shift; cmd_setup "$@" ;;
  models)  shift; cmd_models "$@" ;;
  price)   shift; cmd_price "$@" ;;
  ask)     shift; cmd_ask "$@" ;;
  compare) shift; cmd_compare "$@" ;;
  cost)    shift; cmd_cost "$@" ;;
  *) cat <<'H'
hf.sh — Hugging Face Inference Providers router

  hf.sh setup <hf_token>          validate + store token in ~/.hf-router.json (0600)
  hf.sh models [substring]        warm models + live cheapest price (no auth)
  hf.sh price <org/model>         all providers for one model (no auth)
  hf.sh ask <model> [file]        one call; prompt from file or stdin
  hf.sh compare <m1,m2> [file]    same prompt to N models in parallel
  hf.sh cost <model> <in> <out> <n>       budget math across every provider

Model suffixes: :fastest (default) :cheapest :preferred or a provider (:groq, :deepinfra)
Env: HF_TOKEN, HF_SYSTEM, HF_MAX_TOKENS (4096), HF_TIMEOUT (600)
H
  ;;
esac
