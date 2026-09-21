#!/usr/bin/env bash
# compact-clean ledger tool. The one implementation behind the /compact-clean skill,
# the PreCompact hook, and /mise-en-place's read of the ledger, so none can drift.
#
#   ledger.sh probe                     resolve root, key, tree, baseline, session; no writes
#   ledger.sh certify [--drop PATH]... [--] [PATH...]
#                                       append one certification record; notes on stdin
#   ledger.sh evidence                  append one uncertified snapshot
#   ledger.sh hook                      PreCompact hook: JSON payload on stdin
#   ledger.sh bind                      closedown verdict for THIS session, as JSON; no writes
#   ledger.sh verify-staged -- PATH...  after staging: each path's staged mode and blob must
#                                       equal what was certified; exit 1 on any mismatch
#
# Records bind to a session mechanically, by CLAUDE_CODE_SESSION_ID, never by an id a
# model has merely seen. Hook mode exits 0 on every path: failing a compaction to protect
# a bookkeeping file has its priorities backwards. Every other mode exits non-zero on
# failure, because a model that believes a record exists when it does not loses work.

set -u
mode=${1:-}
[ $# -gt 0 ] && shift

die() {
  [ "$mode" = hook ] && exit 0
  printf 'compact-clean: %s\n' "$*" >&2
  exit 1
}

case "$mode" in probe|certify|evidence|hook|bind|verify-staged) ;; *) die "usage: ledger.sh probe|certify|evidence|hook|bind|verify-staged" ;; esac
[ -n "${HOME:-}" ] || die "HOME is unset"
command -v python3 >/dev/null 2>&1 || die "python3 not found"

sess_id=${CLAUDE_CODE_SESSION_ID:-} payload_trigger=''
if [ "$mode" = hook ]; then
  # The hook's cwd, session_id and trigger arrive ONLY in the stdin payload. One field
  # per line, read with sed: `read a b` word-splits, so a cwd containing spaces would
  # bleed into the next field.
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
import fcntl, glob, hashlib, json, os, secrets, subprocess, sys, time, unicodedata

sys.stdout.reconfigure(errors='backslashreplace')
mode, root, key, tree, sess, ptrig = sys.argv[1:7]
args = sys.argv[7:]
HOME = os.environ['HOME']
PRE = os.path.join(HOME, '.claude', 'preflight')
DIR = os.path.join(HOME, '.claude', 'compact-clean')
LEDGER = os.path.join(DIR, key + '.ledger.jsonl')
MAX_AGE = 16 * 3600
now = int(time.time())
# The ledger stores a hash of the session id, never the id: an id read back out of the
# file must not be usable to impersonate that session.
SESS = ('sha256:' + hashlib.sha256(sess.encode()).hexdigest()) if sess else None

def fail(msg):
    if mode == 'hook':
        sys.exit(0)
    sys.stderr.write('compact-clean: ' + msg + '\n')
    sys.exit(1)

def git(*a):
    return subprocess.run(['git', '-C', root, *a], capture_output=True)

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
    valid started_at. Returns (doc, path, reason_if_absent)."""
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
    """Every record, in file order. File order, not written_at, decides which record is
    newest: written_at counts whole seconds and ties. An unparseable line fails closed:
    skipping it would silently promote the record before it, which may still certify a
    path the newest one disclaimed."""
    recs = []
    try:
        with open(LEDGER, encoding='utf-8', errors='replace') as f:
            for n, line in enumerate(f, 1):
                if not line.strip():
                    continue
                try:
                    d = json.loads(line)
                except Exception:
                    d = None
                if not isinstance(d, dict):
                    fail('ledger %s line %d is unparseable, so no record can be trusted; nothing bound or '
                         'written. It is local bookkeeping: delete the file to reset.' % (LEDGER, n))
                recs.append(d)
    except OSError:
        pass
    return recs

def fingerprint(p):
    """'<mode> <blob>' exactly as git would stage the working-tree path, or None for a
    directory, submodule, missing or special file. Mode is part of it: a chmod +x is an
    edit. A symlink is hashed by its link text, which is what git stores, not its target."""
    full = os.path.join(root, p)
    try:
        st = os.lstat(full)
    except OSError:
        return None
    import stat as S
    if S.S_ISLNK(st.st_mode):
        r = subprocess.run(['git', '-C', root, 'hash-object', '--stdin'], capture_output=True,
                           input=os.fsencode(os.readlink(full)))
        mode = '120000'
    elif S.S_ISREG(st.st_mode):
        r = git('hash-object', '--', p)
        mode = '100755' if st.st_mode & 0o111 else '100644'
    else:
        return None
    return '%s %s' % (mode, r.stdout.decode().strip()) if r.returncode == 0 else None

class Lock:
    """Serialises read-latest-then-append: two certify runs of one session (a subagent
    shares its parent's id) would otherwise each carry from the same record and one
    run's paths would vanish from the newest record."""
    def __enter__(self):
        os.makedirs(DIR, mode=0o700, exist_ok=True)
        self.f = open(LEDGER + '.lock', 'a')
        fcntl.flock(self.f, fcntl.LOCK_EX)
        return self
    def __exit__(self, *a):
        fcntl.flock(self.f, fcntl.LOCK_UN)
        self.f.close()

def rel(p):
    """A path the model named, relative to its cwd or absolute, as a repo-relative path,
    or None if it lies outside the repo. Resolves directory symlinks only: git tracks a
    symlinked file as itself, not as its target."""
    a = p if os.path.isabs(p) else os.path.join(os.getcwd(), p)
    a = os.path.normpath(a)
    a = os.path.join(os.path.realpath(os.path.dirname(a)), os.path.basename(a))
    r = os.path.relpath(a, os.path.realpath(root))
    return None if r == '.' or r == '..' or r.startswith('..' + os.sep) else r

def readings(p):
    """Both ways to read a relative name: from the cwd, and from the repo root."""
    a = rel(p)
    b = None if os.path.isabs(p) else rel(os.path.join(root, p))
    return a, (b if b != a else None)

def near(p, pool):
    f = unicodedata.normalize('NFC', p).casefold()
    return [q for q in pool if unicodedata.normalize('NFC', q).casefold() == f and q != p]

def mine(r, baseline):
    """This session's certification records for this tree and baseline window."""
    return (r.get('schema') == 1 and SESS and r.get('session') == SESS
            and r.get('root') == root and r.get('trigger') == 'manual'
            and baseline is not None and r.get('baseline_started_at') == baseline['started_at']
            and isinstance(r.get('written_at'), int) and 0 <= now - r['written_at'] < MAX_AGE)

baseline, base_path, base_why = find_baseline()

if mode == 'probe':
    print('Root      ' + root)
    print('Key       %s  (tree %s)' % (key, tree))
    if baseline:
        print('Baseline  %s  started %.1fh ago' % (base_path, (now - baseline['started_at']) / 3600))
    else:
        print('Baseline  ABSENT (%s): nothing certified now can land; run /preflight' % base_why)
    print('Ledger    ' + LEDGER)
    print('Session   ' + ('bound (CLAUDE_CODE_SESSION_ID present)' if sess else
                         'UNAVAILABLE: CLAUDE_CODE_SESSION_ID is not set, so nothing can be certified'))
    sys.exit(0)

# Decoded with errors='replace' to match how /preflight decodes the baseline: a name
# that is not valid UTF-8 then compares equal on both sides instead of reading as new.
st = git('--no-optional-locks', 'status', '--porcelain', '-z', '-uall')
if st.returncode:
    fail('git status failed, so the tree state is unknown; nothing written')
parsed = parse_porcelain(st.stdout.decode('utf-8', 'replace').split('\0'))
if parsed is None:
    fail('could not parse git status output; nothing written')
live, live_src = parsed

base_paths = set()
if baseline:
    b_live, b_src = parse_porcelain(baseline['porcelain'])
    base_paths = set(b_live) | b_src

def certifiable(p):
    return p in live and p not in base_paths and 'D' not in live[p]

def bound_record():
    """(record, reason): this session's newest certification record, or None."""
    if not sess:
        return None, 'CLAUDE_CODE_SESSION_ID not set: no record can bind'
    if not baseline:
        return None, 'no valid baseline (%s)' % base_why
    own = [r for r in load_records() if mine(r, baseline)]
    if not own:
        return None, 'no certification record from this session under this baseline'
    r = own[-1]   # the newest only: never an older record, never a union
    if r.get('certified') is not True or not isinstance(r.get('paths'), list) \
            or not isinstance(r.get('fingerprints'), dict):
        return None, 'newest certification record %s certifies nothing' % r.get('record_id')
    return r, None

if mode in ('verify-staged', 'bind'):
    # Readers wait for an in-flight append: reading mid-write would see the record
    # before a fresh --drop and approve the path it disclaims.
    _lock = Lock().__enter__()

if mode == 'verify-staged':
    names = args[1:] if args[:1] == ['--'] else args
    r, why = bound_record()
    if r is None:
        fail('no bound record (%s); nothing can be verified against the ledger' % why)
    bad = []
    for n in names:
        p = rel(n)
        want = r['fingerprints'].get(p) if p else None
        got = git('--literal-pathspecs', 'ls-files', '-s', '--', p).stdout.decode().split('\n')[0].split() if p else []
        have = '%s %s' % (got[0], got[1]) if len(got) >= 2 else None
        if want is None:
            bad.append('%s: not certified by the bound record' % n)
        elif have != want:
            bad.append('%s: staged %s, certified %s' % (p, have or 'nothing', want))
    for b in bad:
        print('MISMATCH  ' + b)
    print('verified %d of %d' % (len(names) - len(bad), len(names)))
    sys.exit(1 if bad else 0)

if mode == 'bind':
    verdict = {'session_id_present': bool(sess), 'baseline': bool(baseline),
               'bound': None, 'reason': None, 'notes': []}
    recs = load_records()
    for r in recs:
        n = r.get('notes')
        rid = r.get('record_id')
        if (SESS and r.get('session') == SESS and r.get('root') == root
                and isinstance(r.get('written_at'), int) and 0 <= now - r['written_at'] < MAX_AGE
                and isinstance(n, str) and isinstance(rid, str)
                and n == os.path.join(DIR, '%s.%s.%s.notes.md' % (key, tree, rid))
                and os.path.isfile(n) and not os.path.islink(n)):
            verdict['notes'].append(n)
    r, why = bound_record()
    if r is None:
        verdict['reason'] = why
    else:
        ok, rejected = [], []
        for p in r['paths']:
            if not isinstance(p, str):
                continue
            if not certifiable(p):
                rejected.append({'path': p, 'reason': 'not a live, non-deleted path absent from the baseline'})
            elif fingerprint(p) != r['fingerprints'].get(p):
                rejected.append({'path': p, 'reason': 'content or mode changed since it was certified'})
            else:
                ok.append(p)
        verdict['bound'] = {'record_id': r.get('record_id'), 'written_at': r['written_at'],
                            'paths': ok, 'fingerprints': {p: r['fingerprints'][p] for p in ok},
                            'rejected': rejected}
    print(json.dumps(verdict, indent=1, ensure_ascii=False))
    sys.exit(0)

if mode in ('certify', 'evidence') and not sess:
    fail('CLAUDE_CODE_SESSION_ID is not set, so no record can be bound to this session; '
         'nothing written. The certification and notes exist only in this context.')

certified, carried, pre, dropped, changed, notes_path = [], [], [], [], [], None
fps, sticky = {}, set()
record_id = secrets.token_hex(6)
# Held until exit, from reading this session's latest record through the append.
_lock = Lock().__enter__()

if mode == 'certify':
    # Strict: an option this loop does not recognise must never fall through to the path
    # list, where `--drop=x` would leave the drop set empty and carry the file forward.
    raw_drops, names, i = [], [], 0
    while i < len(args):
        a = args[i]
        if a == '--drop':
            if i + 1 >= len(args) or args[i + 1].startswith('-'):
                fail('--drop needs a value: --drop <path>')
            raw_drops.append(args[i + 1])
            i += 2
        elif a == '--prior':
            fail('--prior is gone: records now bind by session automatically. Drop the option.')
        elif a == '--':
            names.extend(args[i + 1:])
            break
        elif a.startswith('-'):
            fail('unrecognized option %s. The only option is --drop PATH, before `--`.' % a)
        else:
            names.append(a)
            i += 1
    for n in names:
        if n.split('=', 1)[0] in ('--drop', '--prior'):
            fail('%s appears after `--`, where it would be read as a path. Put options before `--`.' % n)

    prev = None
    if baseline:
        own = [r for r in load_records() if mine(r, baseline)]
        prev = own[-1] if own else None
    prev_paths = [p for p in (prev or {}).get('paths') or [] if isinstance(p, str)]
    prev_fp = (prev or {}).get('fingerprints') if isinstance((prev or {}).get('fingerprints'), dict) else {}
    # Disclaimers outlive a re-run of /preflight: carry-forward is scoped to the baseline,
    # but "never certified again this session" means the session.
    sticky = {p for r in load_records()
              if SESS and r.get('session') == SESS and r.get('root') == root and r.get('trigger') == 'manual'
              for p in r.get('dropped') or [] if isinstance(p, str)}

    # Names resolve from the cwd only. Falling back to the repo root would pick up a
    # same-named file some other session dirtied there, and certify it as this one's.
    resolved = []
    for n in names:
        a_, b_ = readings(n)
        if a_ not in live and b_ in live:
            dropped.append((n, 'not a dirty path from the cwd; %s is (name paths from the repo root)' % b_))
        else:
            resolved.append((n, a_))
    known = set(live) | set(prev_paths) | {r for _, r in resolved if r}
    # A drop may be read either way, but never guessed between two different files.
    for d in raw_drops:
        a_, b_ = readings(d)
        hits = [x for x in (a_, b_) if x and x in known]
        if len(hits) > 1:
            fail('--drop %s is ambiguous: %s or %s. Use the repo-relative path from the repo root; '
                 'nothing written.' % (d, hits[0], hits[1]))
        if not hits:
            fail('--drop %s matches no named, carried or dirty path; nothing written. '
                 'Use the repo-relative path from the report.' % d)
        sticky.add(hits[0])

    chosen = []
    for n, r in resolved:
        if r is None:
            dropped.append((n, 'outside the repo'))
        elif r in sticky:
            dropped.append((r, 'dropped earlier this session'))
        elif r not in live:
            hint = near(r, live)
            dropped.append((r, 'not a dirty path' + (' (did you mean %s?)' % ', '.join(hint) if hint else '')))
        elif r in base_paths:
            pre.append(r)
        elif 'D' in live[r]:
            dropped.append((r, 'a deletion, never certified'))
        else:
            chosen.append(r)

    # Carry this session's earlier certification forward, mechanically. A carried path
    # whose content changed and was not re-named here was changed by something else.
    for p in prev_paths:
        if p in sticky or p in chosen or not certifiable(p):
            continue
        if fingerprint(p) == prev_fp.get(p):
            carried.append(p)
        else:
            changed.append(p)

    if baseline:
        for p in sorted(set(chosen) | set(carried)):
            fp = fingerprint(p)
            if fp is None:
                dropped.append((p, 'cannot fingerprint (a directory, submodule or special file)'))
            else:
                fps[p] = fp
        certified = sorted(fps)
    else:
        dropped.extend((p, 'no baseline, cannot certify') for p in chosen + carried)

    if not sys.stdin.isatty():
        text = sys.stdin.read().strip()
        if text:
            notes_path = os.path.join(DIR, '%s.%s.%s.notes.md' % (key, tree, record_id))
            try:
                fd = os.open(notes_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
                with os.fdopen(fd, 'w', encoding='utf-8') as f:
                    f.write(text + '\n')
            except OSError as e:
                fail('notes write failed (%s); nothing written. The notes exist only in this context.' % e)

cset = set(certified)
candidates = sorted(p for p in set(live) | live_src if p not in base_paths and p not in cset)
head = git('rev-parse', '--verify', '--quiet', 'HEAD')
trigger = {'certify': 'manual', 'evidence': 'evidence'}.get(mode, 'hook-' + (ptrig or 'unknown'))

rec = {
    'schema': 1,
    'writer': 'compact-clean 1.0' + (' (hook)' if mode == 'hook' else ''),
    'record_id': record_id,
    'root': root,
    'session': SESS,
    'written_at': now,
    'baseline_started_at': baseline['started_at'] if baseline else None,
    'head_sha': head.stdout.decode().strip() if head.returncode == 0 else '',
    'certified': bool(certified),
    'paths': certified,
    'fingerprints': fps,
    'dropped': sorted(sticky),
    'candidates': candidates,
    'baseline': bool(baseline),
    'notes': notes_path,
    'trigger': trigger,
}
try:
    os.makedirs(DIR, mode=0o700, exist_ok=True)
    with open(LEDGER, 'a', encoding='utf-8') as f:
        f.write(json.dumps(rec, ensure_ascii=True) + '\n')
except OSError as e:
    fail('ledger write failed (%s); the certification exists only in this context' % e)

if mode == 'hook':
    sys.exit(0)

j = lambda xs: json.dumps(xs, ensure_ascii=False)
print('COMPACT CLEAN  record %s' % record_id)
if mode == 'evidence':
    print('Candidates    %d  (reported at closedown, never committed)' % len(candidates))
    print('Evidence only. Nothing certified, nothing will land from this record.')
    sys.exit(0)
print('Certified     %d  %s' % (len(certified), j(certified)))
print('Carried       %d  (from this session\'s earlier record, content unchanged)' % len(carried))
if changed:
    print('NOT CARRIED   %d  %s  (changed since certified and not re-named here: something else edited it)'
          % (len(changed), j(changed)))
print('Pre-existing  %d  %s  (dirty before this session, never certified)' % (len(pre), j(pre)))
print('Dropped       %d  %s' % (len(dropped), j(['%s: %s' % x for x in dropped])))
if sticky:
    print('Disclaimed    %s  (never certified again this session)' % j(sorted(sticky)))
print('Candidates    %d  (reported at closedown, never committed)' % len(candidates))
print('Notes         ' + (notes_path or 'none'))
if not baseline:
    print('Baseline ABSENT (%s): no work from this record can land; notes are kept. Run /preflight.' % base_why)
elif not certified:
    print('Nothing certified: no work from this record can land; notes are kept. Re-check Phase 2.')
else:
    print('Safe to compact.')
PY

python3 -c "$PY" "$mode" "$root" "$key" "$tree" "$sess_id" "$payload_trigger" "$@"
rc=$?
[ "$mode" = hook ] && exit 0
exit $rc
