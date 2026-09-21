#!/usr/bin/env bash
# compact-clean ledger tool. The one implementation behind both the /compact-clean
# skill and the PreCompact hook, so the two cannot drift apart.
#
#   ledger.sh probe                     resolve root, key, tree and baseline; writes nothing
#   ledger.sh certify [--prior ID] [--drop PATH]... [--] [PATH...]
#                                       append one certified record; notes, if any, on stdin
#   ledger.sh evidence                  append one uncertified snapshot
#   ledger.sh hook                      PreCompact hook: JSON payload on stdin
#
# Hook mode exits 0 on every path: failing a compaction to protect a bookkeeping file
# has its priorities backwards. Manual modes exit non-zero on failure, because a model
# that believes a record was written when it was not loses the session's work.

set -u
mode=${1:-}
[ $# -gt 0 ] && shift

die() {
  [ "$mode" = hook ] && exit 0
  printf 'compact-clean: %s\n' "$*" >&2
  exit 1
}

case "$mode" in probe|certify|evidence|hook) ;; *) die "usage: ledger.sh probe|certify|evidence|hook" ;; esac
[ -n "${HOME:-}" ] || die "HOME is unset"
command -v python3 >/dev/null 2>&1 || die "python3 not found"

sess_id='' payload_trigger=''
if [ "$mode" = hook ]; then
  # cwd, session_id and trigger arrive ONLY in the stdin payload; there is no session
  # id env var. One field per line, read with sed: `read a b` word-splits, so a cwd
  # containing spaces would bleed into the next field.
  payload=$(cat 2>/dev/null || true)
  fields=$(printf '%s' "$payload" | python3 -c 'import json, sys
try: d = json.load(sys.stdin)
except Exception: d = {}
if not isinstance(d, dict): d = {}
def clean(v): return str(v or "").replace("\n", " ").replace("\r", " ")
print(clean(d.get("cwd"))); print(clean(d.get("session_id"))); print(clean(d.get("trigger")))' 2>/dev/null) || exit 0
  cwd=$(printf '%s\n' "$fields" | sed -n '1p')
  sess_id=$(printf '%s\n' "$fields" | sed -n '2p')
  payload_trigger=$(printf '%s\n' "$fields" | sed -n '3p')
  # Never fall through to the launch directory: that would file this compaction under
  # whatever repo happens to be there.
  [ -n "$cwd" ] || exit 0
  cd "$cwd" 2>/dev/null || exit 0
fi

root=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git work tree"

# Key and tree: byte-identical to /preflight Step 3 and /mise-en-place Phase 0.
raw=$(git remote get-url origin 2>/dev/null | head -1); [ -z "$raw" ] && raw=$root
canon=$(printf '%s' "$raw" | tr 'A-Z' 'a-z' \
  | sed -E 's#^([a-z]+://([^/@]+@)?[^/:]+):[0-9]+/#\1/#; s#^[a-z]+://##; s#^[^@/]+@##; s#:#/#; s#/+$##; s#\.git$##; s#/+$##')
stem=$(printf '%s' "$canon" | tr -c 'a-z0-9._-' '-' | sed -E 's#-+#-#g; s#^[-.]+##; s#[-.]+$##')
hash=$(printf '%s' "$canon" | { shasum 2>/dev/null || sha1sum 2>/dev/null; } | cut -c1-12)
case "$hash" in [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
  *) die "no working shasum/sha1sum, cannot derive the key" ;; esac
key="${stem:-repo}-${hash}"
tree=$(printf '%s' "$root" | { shasum 2>/dev/null || sha1sum 2>/dev/null; } | cut -c1-12)

read -r -d '' PY <<'PY'
import glob, json, os, secrets, subprocess, sys, time

mode, root, key, tree, sess, ptrig = sys.argv[1:7]
args = sys.argv[7:]
HOME = os.environ['HOME']
PRE = os.path.join(HOME, '.claude', 'preflight')
DIR = os.path.join(HOME, '.claude', 'compact-clean')
LEDGER = os.path.join(DIR, key + '.ledger.jsonl')
MAX_AGE = 16 * 3600
now = int(time.time())
out = []

def fail(msg):
    if mode == 'hook':
        sys.exit(0)
    sys.stderr.write('compact-clean: ' + msg + '\n')
    sys.exit(1)

def git(*a):
    return subprocess.run(['git', *a], capture_output=True)

def parse_porcelain(entries):
    """Porcelain -z records to ({path: XY}, {rename/copy sources}), or None if malformed.
    A record is 'XY <path>'. An R or C record is followed by one extra record holding
    the bare source path with no prefix, which must never be read as a status record."""
    live, sources, i = {}, set(), 0
    while i < len(entries):
        r = entries[i]
        i += 1
        if not r:
            continue
        if len(r) < 4 or r[2] != ' ':
            return None
        xy, p = r[:2], r[3:]
        live[p] = xy
        if 'R' in xy or 'C' in xy:
            if i >= len(entries) or not entries[i]:
                return None
            sources.add(entries[i])
            i += 1
    return live, sources

def valid_baseline(d):
    if not isinstance(d, dict):
        return 'not an object'
    if type(d.get('schema')) is not int or d['schema'] != 1:
        return 'unknown schema'
    if d.get('root') != root:
        return 'another tree'
    s = d.get('started_at')
    if type(s) is not int or not 0 <= now - s < MAX_AGE:
        return 'stale'
    h = d.get('head_sha')
    if not isinstance(h, str) or not h or git('rev-parse', '--verify', '--quiet', h + '^{commit}').returncode:
        return 'bad head_sha'
    p = d.get('porcelain')
    if not isinstance(p, list) or not all(isinstance(e, str) for e in p):
        return 'bad porcelain'
    if parse_porcelain(p) is None:
        return 'unparseable porcelain'
    return None

def load_json(path):
    try:
        with open(path, encoding='utf-8') as f:
            return json.load(f)
    except Exception:
        return None

def find_baseline():
    """Same lookup as /mise-en-place Phase 0: the per-tree file if it exists; only when
    it is missing, a scan matched on the root FIELD (never a filename or grep), newest
    started_at first. Returns (doc, path, reason_if_absent)."""
    primary = os.path.join(PRE, '%s.%s.session-start.json' % (key, tree))
    if os.path.exists(primary):
        d = load_json(primary)
        why = valid_baseline(d)
        return (d, primary, None) if why is None else (None, primary, why)
    best = None
    for f in glob.glob(os.path.join(PRE, '*.session-start.json')):
        d = load_json(f)
        if valid_baseline(d) is None and (best is None or d['started_at'] > best[0]['started_at']):
            best = (d, f)
    if best:
        return best[0], best[1], None
    return None, None, 'none for this tree'

def load_records():
    recs = []
    try:
        with open(LEDGER, encoding='utf-8') as f:
            for line in f:
                try:
                    d = json.loads(line)
                except Exception:
                    continue
                if isinstance(d, dict):
                    recs.append(d)
    except OSError:
        pass
    return recs

def rel(p):
    """A path the model named, absolute or relative to its cwd, as a repo-relative path,
    or None if it lies outside the repo. Resolves directory symlinks only: git tracks a
    symlinked file as itself, not as its target."""
    a = p if os.path.isabs(p) else os.path.join(os.getcwd(), p)
    a = os.path.normpath(a)
    a = os.path.join(os.path.realpath(os.path.dirname(a)), os.path.basename(a))
    r = os.path.relpath(a, os.path.realpath(root))
    return None if r == '.' or r == '..' or r.startswith('..' + os.sep) else r

baseline, base_path, base_why = find_baseline()

if mode == 'probe':
    print('Root      ' + root)
    print('Key       %s  (tree %s)' % (key, tree))
    if baseline:
        print('Baseline  %s  started %.1fh ago' % (base_path, (now - baseline['started_at']) / 3600))
    else:
        print('Baseline  ABSENT (%s): nothing certified now can ever land; run /preflight' % base_why)
    print('Ledger    ' + LEDGER)
    sys.exit(0)

st = git('--no-optional-locks', 'status', '--porcelain', '-z', '-uall')
if st.returncode:
    fail('git status failed, so the tree state is unknown; no record written')
parsed = parse_porcelain(st.stdout.decode('utf-8', 'surrogateescape').split('\0'))
if parsed is None:
    fail('could not parse git status output; no record written')
live, _ = parsed

base_paths = set()
if baseline:
    b_live, b_src = parse_porcelain(baseline['porcelain'])
    base_paths = set(b_live) | b_src

def ok_to_certify(p):
    return p in live and p not in base_paths and 'D' not in live[p]

certified, carried, pre, dropped, notes_path = [], [], [], [], None
prior = None
record_id = secrets.token_hex(6)

if mode == 'certify':
    # Strict: an option this loop does not recognise must never fall through to the path
    # list. `--drop=x` or a `--drop` after `--` would otherwise leave the drop set empty,
    # and --prior would carry forward the very path the operator just disclaimed.
    drops, names, i = set(), [], 0
    while i < len(args):
        a = args[i]
        if a in ('--prior', '--drop'):
            if i + 1 >= len(args) or args[i + 1].startswith('-'):
                fail('%s needs a value: %s <value>' % (a, a))
            if a == '--prior':
                prior = args[i + 1]
            else:
                r = rel(args[i + 1])
                if r is None:
                    fail('--drop path is outside the repo: %s' % args[i + 1])
                drops.add(r)
            i += 2
        elif a == '--':
            names.extend(args[i + 1:])
            break
        elif a.startswith('-'):
            fail('unrecognized option %s. Options are --prior ID and --drop PATH, before `--`.' % a)
        else:
            names.append(a)
            i += 1
    for n in names:
        if n.split('=', 1)[0] in ('--prior', '--drop'):
            fail('%s appears after `--`, where it would be read as a path. Put options before `--`.' % n)

    chosen = []
    for n in names:
        r = rel(n)
        if r is None:
            dropped.append((n, 'outside the repo'))
        elif r in drops:
            dropped.append((r, '--drop'))
        elif r not in live:
            dropped.append((r, 'clean now'))
        elif r in base_paths:
            pre.append(r)
        elif 'D' in live[r]:
            dropped.append((r, 'a deletion, never certified'))
        else:
            chosen.append(r)

    if prior:
        match = [d for d in load_records() if d.get('record_id') == prior]
        d = match[-1] if match else None
        why = None
        if d is None:
            why = 'not in the ledger'
        elif d.get('root') != root:
            why = 'another tree'
        elif d.get('certified') is not True:
            why = 'not certified'
        elif not baseline or d.get('baseline_started_at') != baseline['started_at']:
            why = 'written under a different baseline'
        elif not isinstance(d.get('paths'), list):
            why = 'malformed'
        if why:
            out.append('WARNING   prior record %s not usable (%s): earlier edits are NOT carried' % (prior, why))
            prior = None
        else:
            for p in d['paths']:
                if isinstance(p, str) and p not in drops and p not in chosen and ok_to_certify(p):
                    carried.append(p)

    if baseline:
        certified = sorted(set(chosen) | set(carried))
    else:
        dropped.extend((p, 'no baseline, cannot certify') for p in chosen + carried)

    if not sys.stdin.isatty():
        text = sys.stdin.read().strip()
        if text:
            os.makedirs(DIR, mode=0o700, exist_ok=True)
            notes_path = os.path.join(DIR, '%s.%s.%s.notes.md' % (key, tree, record_id))
            fd = os.open(notes_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, 'w', encoding='utf-8') as f:
                f.write(text + '\n')

cset = set(certified)
candidates = sorted(p for p in live if p not in base_paths and p not in cset)
head = git('rev-parse', '--verify', '--quiet', 'HEAD')
trigger = {'certify': 'manual', 'evidence': 'evidence'}.get(mode, 'hook-' + (ptrig or 'unknown'))

rec = {
    'schema': 1,
    'writer': 'compact-clean 1.0' + (' (hook)' if mode == 'hook' else ''),
    'record_id': record_id,
    'prior': prior,
    'root': root,
    'session_id': sess or None,
    'written_at': now,
    'baseline_started_at': baseline['started_at'] if baseline else None,
    'head_sha': head.stdout.decode().strip() if head.returncode == 0 else '',
    'certified': bool(certified),
    'paths': certified,
    'candidates': candidates,
    'baseline': bool(baseline),
    'notes': notes_path,
    'trigger': trigger,
}
line = json.dumps(rec, ensure_ascii=True) + '\n'
try:
    os.makedirs(DIR, mode=0o700, exist_ok=True)
    with open(LEDGER, 'a', encoding='utf-8') as f:
        f.write(line)
except OSError as e:
    fail('ledger write failed (%s); the certification exists only in this context' % e)

if mode == 'hook':
    sys.exit(0)

j = lambda xs: json.dumps(xs, ensure_ascii=False)
print('COMPACT CLEAN  record %s' % record_id)
print('Certified     %d  %s' % (len(certified), j(certified)))
if mode == 'certify' and prior:
    print('Carried       %d from record %s' % (len(carried), prior))
print('Pre-existing  %d  %s  (dirty before this session, never certified)' % (len(pre), j(pre)))
print('Dropped       %d  %s' % (len(dropped), j(['%s: %s' % x for x in dropped])))
print('Candidates    %d  (reported at closedown, never committed)' % len(candidates))
print('Notes         ' + (notes_path or 'none'))
for w in out:
    print(w)
if mode == 'evidence':
    print('Evidence only. Nothing certified, nothing will land from this record.')
    sys.exit(0)
if not baseline:
    print('Baseline      ABSENT (%s): no work from this record can land. Run /preflight.' % base_why)
elif not certified:
    print('Nothing certified: no work from this record can land. Re-check Phase 2 before you compact.')
# The id is the binding for the notes as well as the paths, so hand it over every time.
print('%s Run:  /compact Keep this line verbatim: compact-clean record %s'
      % ('Safe to compact.' if certified else 'Then', record_id))
PY

python3 -c "$PY" "$mode" "$root" "$key" "$tree" "$sess_id" "$payload_trigger" "$@"
rc=$?
[ "$mode" = hook ] && exit 0
exit $rc
