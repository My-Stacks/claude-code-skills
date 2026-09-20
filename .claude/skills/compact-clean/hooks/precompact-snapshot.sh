#!/usr/bin/env bash
# PreCompact hook for /compact-clean — evidence snapshot only.
#
# A command hook has no model, so it CANNOT certify authorship. It records the
# candidate set and the moment of compaction so /mise-en-place can report
# accurately; it does not preserve the ability to land work. Only running
# /compact-clean does that.
#
# Exits 0 on every path. Failing a compaction to protect a bookkeeping file has
# its priorities backwards.

set -u

payload=$(cat 2>/dev/null || true)

# cwd and session_id arrive ONLY in the stdin payload — there is no
# CLAUDE_SESSION_ID env var, so reading one would silently write empty ids.
# Emitted one field per LINE and read with sed: `read a b` word-splits, so a
# cwd containing spaces would otherwise bleed into the session id.
fields=$(printf '%s' "$payload" | python3 -c 'import json,sys
try: d = json.load(sys.stdin) or {}
except Exception: d = {}
def clean(v): return str(v or "").replace("\n", " ").replace("\r", " ")
print(clean(d.get("cwd")))
print(clean(d.get("session_id")))' 2>/dev/null || printf '\n\n')

cd_dir=$(printf '%s\n' "$fields" | sed -n '1p')
sess_id=$(printf '%s\n' "$fields" | sed -n '2p')
# Exit 0, never fall through: continuing in the launch directory would key the
# ledger to whatever repo happens to be there and file this compaction under it.
[ -n "${cd_dir:-}" ] && { cd "$cd_dir" 2>/dev/null || exit 0; }

git rev-parse --show-toplevel >/dev/null 2>&1 || exit 0
root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0

# Key derivation — byte-identical to preflight Step 3 and mise-en-place Phase 0.
raw=$(git remote get-url origin 2>/dev/null | head -1); [ -z "$raw" ] && raw=$root
canon=$(printf '%s' "$raw" | tr 'A-Z' 'a-z' \
  | sed -E 's#^([a-z]+://([^/@]+@)?[^/:]+):[0-9]+/#\1/#; s#^[a-z]+://##; s#^[^@/]+@##; s#:#/#; s#/+$##; s#\.git$##; s#/+$##')
stem=$(printf '%s' "$canon" | tr -c 'a-z0-9._-' '-' | sed -E 's#-+#-#g; s#^[-.]+##; s#[-.]+$##')
hash=$(printf '%s' "$canon" | { shasum 2>/dev/null || sha1sum 2>/dev/null; } | cut -c1-12)
key="${stem:-repo}-${hash}"
tree=$(printf '%s' "$root" | { shasum 2>/dev/null || sha1sum 2>/dev/null; } | cut -c1-12)

dir="$HOME/.claude/compact-clean"
mkdir -p "$dir" 2>/dev/null || exit 0
ledger="$dir/${key}.ledger.jsonl"
tmp="$dir/.${key}.${tree}.porcelain.$$"
trap 'rm -f "$tmp"' EXIT

# EXACTLY preflight's flags. -uall: without it a new file inside a new directory
# collapses to "?? newdir/", which never compares equal to the baseline's full path,
# so every such file reads as a candidate. --no-optional-locks: this runs unattended
# and must not take .git/index.lock from an in-flight commit or rebase.
git --no-optional-locks status --porcelain -z -uall >"$tmp" 2>/dev/null || : >"$tmp"

python3 - "$ledger" "$tmp" "$root" \
  "$HOME/.claude/preflight/${key}.${tree}.session-start.json" \
  "$HOME/.claude/preflight" \
  "$(git rev-parse --verify HEAD 2>/dev/null || echo '')" \
  "$(date +%s)" "${sess_id:-}" <<'PY' 2>/dev/null || exit 0
import json, re, sys

ledger, porc, root, basef, basedir, head, now, sess = sys.argv[1:9]

def rd(p):
    try: return open(p, encoding='utf-8', errors='replace').read()
    except OSError: return ''

# NUL-split, never newline-split: a filename may legally contain a newline.
entries = [e for e in rd(porc).split('\0') if e]

# The baseline is per-tree as of preflight 5.3. Fall back to a root-scan so a
# pre-5.3 (un-treed) baseline is still found; match on the "root" FIELD, never on
# the filename, because one key is shared by every worktree of an origin.
def load_baseline():
    import glob, os
    for f in [basef] + sorted(glob.glob(os.path.join(basedir, '*.session-start.json'))):
        try:
            d = json.load(open(f))
        except Exception:
            continue
        if d.get('root') == root and d.get('schema') == 1:
            return d.get('porcelain', []), True
    return [], False

base_entries, has_base = load_baseline()

was = set(base_entries)
# Only real status entries; a rename's source field carries no "XY " prefix.
cand = [e[3:] for e in entries if e not in was and re.match(r'^..[ ]', e)]

rec = {'schema': 1, 'writer': 'compact-clean 1.0 (hook)', 'root': root,
       'session_id': sess,
       'written_at': int(now), 'head_sha': head, 'certified': False,
       'paths': [], 'candidates': cand, 'baseline': has_base, 'notes': None,
       'trigger': 'precompact-hook'}

line = json.dumps(rec, ensure_ascii=False)
if line.strip():
    with open(ledger, 'a', encoding='utf-8') as fh:
        fh.write(line + '\n')
PY

exit 0
