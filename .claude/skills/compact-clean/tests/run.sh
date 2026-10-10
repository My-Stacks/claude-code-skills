#!/usr/bin/env bash
# Hermetic tests for scripts/ledger.sh: throwaway HOME, throwaway repos, explicit
# session ids. Never touches the real ~/.claude. Run: bash tests/run.sh
# shellcheck disable=SC2164  # every cd targets a directory this harness just created
set -u
L="$(cd "$(dirname "$0")/.." && pwd)/scripts/ledger.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/compact-clean-test.XXXXXX")
trap 'rm -rf "$T"' EXIT
export HOME="$T/home"
mkdir -p "$HOME/.claude/preflight"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
unset CLAUDE_CODE_SESSION_ID   # hermetic: the caller's real session must never leak in
pass=0 failed=0

eq() {  # eq <got> <want> <label>
  if [ "$1" = "$2" ]; then pass=$((pass + 1))
  else failed=$((failed + 1)); printf 'FAIL %s\n  got:  %s\n  want: %s\n' "$3" "$1" "$2"; fi
}
repo() {  # repo <dir>: committed files a b c d, "ab cdef.txt", origin set
  rm -rf "$1"; mkdir -p "$1"
  ( cd "$1" && git init -q && git config user.email t@t && git config user.name t \
    && git remote add origin git@github.com:Org/Repo.git \
    && for f in a b c d; do echo 1 > "$f"; done && printf x > "ab cdef.txt" \
    && git add -A && git commit -qm init )
}
baseline() {  # baseline <dir> <seconds-ago>: written exactly as /preflight 5.3 does
  ( cd "$1"
    root=$(git rev-parse --show-toplevel)
    raw=$(git remote get-url origin 2>/dev/null | head -1); [ -z "$raw" ] && raw=$root
    canon=$(printf '%s' "$raw" | tr 'A-Z' 'a-z' \
      | sed -E 's#^([a-z]+://([^/@]+@)?[^/:]+):[0-9]+/#\1/#; s#^[a-z]+://##; s#^[^@/]+@##; s#:#/#; s#/+$##; s#\.git$##; s#/+$##')
    stem=$(printf '%s' "$canon" | tr -c 'a-z0-9._-' '-' | sed -E 's#-+#-#g; s#^[-.]+##; s#[-.]+$##')
    key="${stem:-repo}-$(printf '%s' "$canon" | { shasum 2>/dev/null || sha1sum; } | cut -c1-12)"
    tree=$(printf '%s' "$root" | { shasum 2>/dev/null || sha1sum; } | cut -c1-12)
    git --no-optional-locks status --porcelain -z -uall > "$T/porc"
    python3 - "$HOME/.claude/preflight/$key.$tree.session-start.json" "$root" "$(git rev-parse HEAD)" "$2" "$T/porc" <<'PY'
import json, sys, time
b, root, head, ago, pf = sys.argv[1:6]
p = [e for e in open(pf, encoding='utf-8', errors='replace').read().split('\0') if e]
json.dump({'schema': 1, 'writer': 'preflight 5.3', 'root': root, 'started_at': int(time.time()) - int(ago),
           'head_sha': head, 'porcelain': p, 'stashes': 0, 'worktrees': [root], 'listening_ports': []},
          open(b, 'w'))
PY
  )
}
last() { tail -1 "$HOME"/.claude/compact-clean/*.ledger.jsonl | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print($1)"; }
bindq() { bash "$L" bind | python3 -c "import json,sys; v=json.load(sys.stdin); print($1)"; }
S1=11111111-1111-1111-1111-111111111111 S2=22222222-2222-2222-2222-222222222222

# --- certify buckets and normalisation ---
R="$T/r1"; repo "$R"; cd "$R"; echo pre > d; baseline "$R" 120
echo s > a; echo s > b; mkdir -p "sub/x y"; echo s > "sub/x y/q\"z.txt"; rm c; echo side > lock.json
cd sub
out=$(CLAUDE_CODE_SESSION_ID=$S1 bash "$L" certify -- ../a "$R/sub/x y/q\"z.txt" ../d ../c /etc/passwd ../nope <<'CC_NOTES_END'
decided X because Y
CC_NOTES_END
); eq "$?" 0 "certify exits 0"
cd "$R"
eq "$(last 'd["paths"]')" "['a', 'sub/x y/q\"z.txt']" "certified set"
eq "$(echo "$out" | grep -c 'Pre-existing  1')" 1 "baseline path is pre-existing"
eq "$(last '"c" in d["candidates"] and "lock.json" in d["candidates"]')" True "deletion and side effect stay candidates"
eq "$(last 'sorted(d["fingerprints"])==sorted(d["paths"])')" True "every certified path fingerprinted"
eq "$(last 'd["session"].startswith("sha256:")')" True "session stored as a hash"
eq "$(grep -c "$S1" "$HOME"/.claude/compact-clean/*.ledger.jsonl)" 0 "raw session id never written to the ledger"
eq "$(echo "$out" | grep -c 'Safe to compact.')" 1 "success reported"

# --- binding: session, content, newest-only ---
eq "$(CLAUDE_CODE_SESSION_ID=$S1 bindq 'v["bound"]["paths"]')" "['a', 'sub/x y/q\"z.txt']" "own session binds"
eq "$(CLAUDE_CODE_SESSION_ID=$S2 bindq 'v["bound"]')" None "another session binds nothing"
eq "$(bindq 'v["bound"]')" None "no session id binds nothing"
eq "$(CLAUDE_CODE_SESSION_ID=$S1 bindq 'len(v["notes"])')" 1 "own notes bound"
eq "$(CLAUDE_CODE_SESSION_ID=$S2 bindq 'len(v["notes"])')" 0 "other session's notes not bound"
echo tampered >> a
eq "$(CLAUDE_CODE_SESSION_ID=$S1 bindq '[r["reason"] for r in v["bound"]["rejected"]]')" "['content or mode changed since it was certified']" "edited-after-certify rejected"
printf '{"cwd":"%s","session_id":"%s","trigger":"manual"}' "$R" "$S1" | bash "$L" hook
eq "$(CLAUDE_CODE_SESSION_ID=$S1 bindq 'v["bound"] is not None')" True "hook record does not shadow the certification"

# --- carry-forward, sticky drop, subdirectory drop ---
R="$T/r2"; repo "$R"; cd "$R"; baseline "$R" 120; echo s > a; echo s > b
CLAUDE_CODE_SESSION_ID=$S1 bash "$L" certify -- a b </dev/null >/dev/null
echo s > c
CLAUDE_CODE_SESSION_ID=$S1 bash "$L" certify -- c </dev/null >/dev/null
eq "$(last 'd["paths"]')" "['a', 'b', 'c']" "earlier certification carried"
mkdir -p deep; cd deep
CLAUDE_CODE_SESSION_ID=$S1 bash "$L" certify --drop b </dev/null >/dev/null
eq "$(last 'd["paths"]')" "['a', 'c']" "repo-relative --drop from a subdirectory"
CLAUDE_CODE_SESSION_ID=$S1 bash "$L" certify -- ../b </dev/null >/dev/null
eq "$(last 'd["paths"]')" "['a', 'c']" "a disclaimed path never comes back"
CLAUDE_CODE_SESSION_ID=$S1 bash "$L" certify --drop nosuch </dev/null 2>/dev/null; eq "$?" 1 "--drop matching nothing refused"
cd "$R"
CLAUDE_CODE_SESSION_ID=$S1 bash "$L" certify --drop a --drop c </dev/null >/dev/null
eq "$(CLAUDE_CODE_SESSION_ID=$S1 bindq 'v["bound"]')" None "newest certifies nothing: no fallback to an older record"
echo t > d; echo other >> a
CLAUDE_CODE_SESSION_ID=$S2 bash "$L" certify -- d </dev/null >/dev/null
eq "$(last 'd["paths"]')" "['d']" "a second session carries nothing from the first"

# --- evidence never shadows; mode is part of the fingerprint ---
R="$T/r8"; repo "$R"; cd "$R"; baseline "$R" 120; echo s > a; echo s > b
CLAUDE_CODE_SESSION_ID=$S1 bash "$L" certify -- a b </dev/null >/dev/null
CLAUDE_CODE_SESSION_ID=$S1 bash "$L" evidence </dev/null >/dev/null
eq "$(last 'd["certified"]')" False "evidence record is uncertified"
eq "$(CLAUDE_CODE_SESSION_ID=$S1 bindq 'v["bound"]["paths"]')" "['a', 'b']" "evidence does not shadow the certification"
env -u CLAUDE_CODE_SESSION_ID bash "$L" evidence </dev/null 2>/dev/null; eq "$?" 1 "evidence without a session id refused"
chmod +x b
eq "$(CLAUDE_CODE_SESSION_ID=$S1 bindq 'v["bound"]["paths"]')" "['a']" "chmod after certification rejected"

# --- staged content must equal certified content ---
git add a
CLAUDE_CODE_SESSION_ID=$S1 bash "$L" verify-staged -- a >/dev/null; eq "$?" 0 "staged blob matches certification"
echo late >> a; git add a
CLAUDE_CODE_SESSION_ID=$S1 bash "$L" verify-staged -- a >/dev/null; eq "$?" 1 "content changed before staging refused"
CLAUDE_CODE_SESSION_ID=$S1 bash "$L" verify-staged -- c >/dev/null; eq "$?" 1 "uncertified path refused"

# --- symlinks and unfingerprintable paths ---
R="$T/r9"; repo "$R"; cd "$R"; baseline "$R" 120
echo s > a; ln -s "$T/outside.txt" lnk; echo v1 > "$T/outside.txt"; ln -s /nonexistent dangle; mkdir -p dir; echo s > dir/f
CLAUDE_CODE_SESSION_ID=$S1 bash "$L" certify -- a lnk dangle dir <<'CC_NOTES_END' >/dev/null
note survives an unfingerprintable path
CC_NOTES_END
eq "$?" 0 "unfingerprintable path does not abort the record"
eq "$(last 'd["paths"]')" "['a', 'dangle', 'lnk']" "symlinks certified by link text; the directory is not a dirty path"
eq "$(last 'd["notes"] is not None')" True "notes kept"
eq "$(last 'd["fingerprints"]["lnk"].split()[1]')" "$(printf '%s' "$T/outside.txt" | git hash-object --stdin)" "symlink blob equals what git stores"
echo v2 > "$T/outside.txt"
eq "$(CLAUDE_CODE_SESSION_ID=$S1 bindq '"lnk" in v["bound"]["paths"]')" True "a symlink's target changing is not an edit to the link"

# --- names resolve from the cwd only; drops never guess ---
R="$T/r10"; repo "$R"; cd "$R"; mkdir -p src; echo 1 > src/app.ts; echo 1 > app.ts; git add -A; git commit -qm more; baseline "$R" 120
echo other > new.ts; echo s > src/mine.ts
cd src
CLAUDE_CODE_SESSION_ID=$S1 bash "$L" certify -- new.ts mine.ts </dev/null >/dev/null
eq "$(last 'd["paths"]')" "['src/mine.ts']" "a same-named root file is never certified from a subdirectory"
echo s > app.ts; echo t > ../app.ts
CLAUDE_CODE_SESSION_ID=$S1 bash "$L" certify -- app.ts ../app.ts </dev/null >/dev/null
CLAUDE_CODE_SESSION_ID=$S1 bash "$L" certify --drop app.ts </dev/null 2>/dev/null; eq "$?" 1 "ambiguous --drop refused"
cd "$R"

# --- concurrent certify under one session loses nothing ---
R="$T/r11"; repo "$R"; cd "$R"; baseline "$R" 120
for k in 1 2 3 4 5 6; do echo s > "x$k"; echo s > "y$k"
  CLAUDE_CODE_SESSION_ID=$S1 bash "$L" certify -- "x$k" </dev/null >/dev/null &
  CLAUDE_CODE_SESSION_ID=$S1 bash "$L" certify -- "y$k" </dev/null >/dev/null &
  wait
done
eq "$(CLAUDE_CODE_SESSION_ID=$S1 bindq 'len(v["bound"]["paths"])')" 12 "twelve parallel certifications, none lost"

# --- literal pathspec in verify-staged; sticky drops survive a new baseline ---
R="$T/r12"; repo "$R"; cd "$R"; echo 1 > a1.json; git add -A; git commit -qm lit; baseline "$R" 120
echo s > "a[1].json"; echo different > a1.json
CLAUDE_CODE_SESSION_ID=$S1 bash "$L" certify -- "a[1].json" </dev/null >/dev/null
git --literal-pathspecs add -- "a[1].json" a1.json
CLAUDE_CODE_SESSION_ID=$S1 bash "$L" verify-staged -- "a[1].json" >/dev/null; eq "$?" 0 "glob-looking name verified literally"
echo s > b
CLAUDE_CODE_SESSION_ID=$S1 bash "$L" certify -- b </dev/null >/dev/null
CLAUDE_CODE_SESSION_ID=$S1 bash "$L" certify --drop b </dev/null >/dev/null
git commit -qam checkpoint; baseline "$R" 5          # b clean at the new baseline
echo again > b
CLAUDE_CODE_SESSION_ID=$S1 bash "$L" certify -- b </dev/null >/dev/null
eq "$(last 'd["paths"]')" "[]" "a disclaimer survives a re-run of /preflight"

# --- carry-forward stops at a new baseline ---
R="$T/r13"; repo "$R"; cd "$R"; baseline "$R" 120; echo s > a
CLAUDE_CODE_SESSION_ID=$S1 bash "$L" certify -- a </dev/null >/dev/null
baseline "$R" 5                      # a new /preflight while a is still dirty
eq "$(CLAUDE_CODE_SESSION_ID=$S1 bindq 'v["bound"]')" None "a certification does not bind under a newer baseline"
CLAUDE_CODE_SESSION_ID=$S1 bash "$L" certify </dev/null >/dev/null
eq "$(last 'd["paths"]')" "[]" "nor is it carried into one"

# --- a torn ledger line fails closed ---
R="$T/r14"; repo "$R"; cd "$R"; baseline "$R" 120; echo s > a; echo s > b
CLAUDE_CODE_SESSION_ID=$S1 bash "$L" certify -- a b </dev/null >/dev/null
CLAUDE_CODE_SESSION_ID=$S1 bash "$L" certify --drop b </dev/null >/dev/null
led=$(ls "$HOME"/.claude/compact-clean/*.ledger.jsonl)
python3 -c 'import sys; p=sys.argv[1]; L=open(p).read().splitlines(True); L[-1]=L[-1][:40]+"\n"; open(p,"w").writelines(L)' "$led"
CLAUDE_CODE_SESSION_ID=$S1 bash "$L" bind >/dev/null 2>&1; eq "$?" 1 "bind refuses a torn newest record instead of falling back"
CLAUDE_CODE_SESSION_ID=$S1 bash "$L" certify -- a </dev/null >/dev/null 2>&1; eq "$?" 1 "certify refuses a torn ledger"
rm -f "$led"

# --- probe ---
eq "$(bash "$L" probe | grep -c '^Ledger ')" 1 "probe states the ledger path"

# --- content drift blocks the carry ---
R="$T/r3"; repo "$R"; cd "$R"; baseline "$R" 120; echo s > a
CLAUDE_CODE_SESSION_ID=$S1 bash "$L" certify -- a </dev/null >/dev/null
echo foreign >> a
out=$(CLAUDE_CODE_SESSION_ID=$S1 bash "$L" certify </dev/null)
eq "$(echo "$out" | grep -c 'NOT CARRIED')" 1 "externally changed file not carried"

# --- strict options ---
for bad in '--drop=a' '--drop' '-x' '--prior x' '-- --drop a'; do
  # shellcheck disable=SC2086
  CLAUDE_CODE_SESSION_ID=$S1 bash "$L" certify $bad </dev/null 2>/dev/null; eq "$?" 1 "refused: $bad"
done

# --- no baseline, no session id ---
R="$T/r4"; repo "$R"; cd "$R"; echo s > a
out=$(CLAUDE_CODE_SESSION_ID=$S1 bash "$L" certify -- a </dev/null)
eq "$(last 'd["certified"]')" False "no baseline: nothing certified"
eq "$(echo "$out" | grep -c 'Baseline ABSENT')" 1 "no baseline reported"
env -u CLAUDE_CODE_SESSION_ID bash "$L" certify -- a </dev/null 2>/dev/null; eq "$?" 1 "no session id: refused"

# --- porcelain parsing ---
R="$T/r5"; repo "$R"; cd "$R"; baseline "$R" 120; git mv "ab cdef.txt" renamed.txt
printf '{"cwd":"%s","session_id":"%s"}' "$R" "$S1" | bash "$L" hook; eq "$?" 0 "hook exit 0"
eq "$(last 'd["candidates"]')" "['ab cdef.txt', 'renamed.txt']" "rename source kept whole, not sliced"
R="$T/r6"; repo "$R"; cd "$R"; echo 2 > a; echo 2 > b; baseline "$R" 120; git add a; rm b
printf '{"cwd":"%s"}' "$R" | bash "$L" hook
eq "$(last 'd["candidates"]')" "[]" "status change on a pre-existing path is not new"

# --- hook contract ---
cd "$T"
for p in '' '{"cwd": ' '[1,2]' '{"cwd":"/nonexistent"}'; do
  printf '%s' "$p" | bash "$L" hook; eq "$?" 0 "hook exit 0 on payload <$p>"
done
env -u HOME bash "$L" hook </dev/null; eq "$?" 0 "hook exit 0 with HOME unset"
echo null > "$HOME/.claude/preflight/zzz.session-start.json"
R="$T/r7"; repo "$R"; cd "$R"; echo s > a
n0=$(cat "$HOME"/.claude/compact-clean/*.ledger.jsonl | wc -l)
printf '{"cwd":"%s"}' "$R" | bash "$L" hook
eq "$(( $(cat "$HOME"/.claude/compact-clean/*.ledger.jsonl | wc -l) - n0 ))" 1 "malformed preflight file does not disable the hook"
printf garbage > .git/index; n0=$(cat "$HOME"/.claude/compact-clean/*.ledger.jsonl | wc -l)
printf '{"cwd":"%s"}' "$R" | bash "$L" hook
eq "$(( $(cat "$HOME"/.claude/compact-clean/*.ledger.jsonl | wc -l) - n0 ))" 0 "failed git status records nothing"

# --- guard (PreCompact) ---
rm -f "$HOME"/.claude/compact-clean/*.ledger.jsonl   # test repos share one origin, so one ledger
R="$T/g1"; repo "$R"; cd "$R"; baseline "$R" 120; echo s > a
g() { printf '{"cwd":"%s","session_id":"%s","trigger":"%s","custom_instructions":"%s"}' "$R" "$1" "$2" "$3" | bash "$L" guard 2>"$T/gerr"; echo $?; }
eq "$(g $S1 manual '')" 2 "guard blocks a manual /compact with no flush"
eq "$(grep -c 'compact noflush' "$T/gerr")" 1 "guard explains the bypass"
eq "$(g $S1 auto '')" 0 "guard never blocks auto-compaction"
eq "$(g $S1 manual 'keep NoFlush please')" 0 "noflush in the instructions bypasses"
eq "$(g '' manual '')" 0 "no session id: guard allows"
printf '{"cwd":"%s","session_id":"%s","trigger":"manual"}' "$R" "$S1" | bash "$L" hook
eq "$(g $S1 manual '')" 2 "a hook evidence record is not a flush"
CLAUDE_CODE_SESSION_ID=$S1 bash "$L" certify -- a </dev/null >/dev/null
eq "$(g $S1 manual '')" 0 "a fresh certify unblocks"
eq "$(g $S2 manual '')" 2 "another session's flush does not unblock"
CLAUDE_CODE_SESSION_ID=$S2 bash "$L" evidence </dev/null >/dev/null
eq "$(g $S2 manual '')" 0 "a fresh evidence snapshot unblocks"
set -- "$HOME"/.claude/compact-clean/*.ledger.jsonl; eq "$#" 1 "guard tests run against exactly one ledger"; LG=$1
python3 - "$LG" <<'PY'
import json, sys
p = sys.argv[1]; rs = [json.loads(l) for l in open(p)]
for r in rs: r['written_at'] -= 11 * 60
open(p, 'w').write(''.join(json.dumps(r) + '\n' for r in rs))
PY
eq "$(g $S1 manual '')" 2 "a flush older than 10 min does not unblock"
echo garbage >> "$LG"
eq "$(g $S1 manual '')" 0 "corrupt ledger: guard fails open"
cd "$T"; eq "$(printf '{"cwd":"%s","session_id":"%s","trigger":"manual"}' "$T" "$S1" | bash "$L" guard 2>/dev/null; echo $?)" 0 "outside a repo: guard allows"
for p in '' '[1]' '{"cwd":"/nonexistent","trigger":"manual"}'; do
  printf '%s' "$p" | bash "$L" guard 2>/dev/null; eq "$?" 0 "guard exit 0 on payload <$p>"
done

# --- cue (SessionStart) ---
rm -f "$HOME"/.claude/compact-clean/*.ledger.jsonl   # the guard tests left it corrupt on purpose
R="$T/c1"; repo "$R"; cd "$R"; baseline "$R" 120; echo s > a
c() { printf '{"cwd":"%s","session_id":"%s","source":"%s"}' "$R" "$1" "$2" | bash "$L" cue; }
eq "$(c $S1 compact)" "" "cue silent with no notes"
CLAUDE_CODE_SESSION_ID=$S1 bash "$L" certify -- a <<<'NEXT: x' >/dev/null
CLAUDE_CODE_SESSION_ID=$S1 bash "$L" certify -- a <<<'NEXT: y' >/dev/null
eq "$(c $S1 compact | grep -c 'saved 2 notes file(s).*Run the /compact-resume skill')" 1 "cue names the notes and the skill"
eq "$(c $S1 startup)" "" "cue silent on a non-compact start"
eq "$(c $S2 compact)" "" "cue silent for another session"
c $S1 compact >/dev/null; eq "$?" 0 "cue exit 0"
printf '[1]' | bash "$L" cue; eq "$?" 0 "cue exit 0 on a bad payload"

# --- worktrees, encoding, head_sha ---
rm -f "$HOME"/.claude/compact-clean/*.ledger.jsonl; S3=33333333-3333-3333-3333-333333333333
R="$T/w1"; repo "$R"; cd "$R"; baseline "$R" 120; echo s > a
git worktree add -q "$T/w2" 2>/dev/null
CLAUDE_CODE_SESSION_ID=$S3 bash "$L" certify -- a <<<'NEXT: w' >/dev/null
eq "$(CLAUDE_CODE_SESSION_ID=$S3 bindq 'bool(v["bound"]["head_sha"])')" True "bind exposes head_sha"
gw() { printf '{"cwd":"%s","session_id":"%s","trigger":"manual"}' "$T/w2" "$S3" | bash "$L" guard 2>/dev/null; echo $?; }
eq "$(gw)" 0 "a flush in another worktree satisfies the guard"
eq "$(printf '{"cwd":"%s","session_id":"%s","source":"compact"}' "$T/w2" "$S3" | bash "$L" cue | grep -c "/w1 (the worktree")" 1 "cue names the worktree holding the notes"
eq "$(printf '{"cwd":"%s","session_id":"%s","source":"compact"}' "$R" "$S3" | bash "$L" cue | grep -c 'worktree')" 0 "cue names no worktree from the same one"
( cd "$T/w2" && echo s > b && CLAUDE_CODE_SESSION_ID=$S3 bash "$L" certify -- b <<<'NEXT: w2' >/dev/null )
out=$(printf '{"cwd":"%s","session_id":"%s","source":"compact"}' "$R" "$S3" | bash "$L" cue)
eq "$(echo "$out" | grep -c 'saved 1 notes file(s).*/w2 (the worktree.*Earlier notes also exist in .*/w1: resume from there too')" 1 "cue counts per worktree and names the others"
gx() { printf '{"cwd":"%s","session_id":"%s","trigger":"manual","custom_instructions":"%s"}' "$R" "$S2" "$1" | bash "$L" guard 2>/dev/null; echo $?; }
eq "$(gx '\ud83d x')" 2 "lone surrogate in the payload still blocks"
eq "$(PYTHONIOENCODING=ascii gx 'café')" 2 "raw UTF-8 under an ascii locale still blocks"
eq "$(PYTHONIOENCODING=ascii gx 'caf\u00e9')" 2 "escaped non-ASCII under an ascii locale still blocks"
eq "$(gx 'noflushlater')" 2 "noflush must be a word, not a substring"
eq "$(gx 'focus on X (noflush)')" 0 "noflush beside punctuation bypasses"

# --- key parity with /preflight 5.3 ---
R="$T/kp"; repo "$R"; cd "$R"
for o in 'git@github.com:Org/Repo.git' 'https://github.com/Org/Repo.git/' 'ssh://git@github.com:22/Org/Repo.git' 'https://user@github.com/org/repo'; do
  git remote set-url origin "$o"
  eq "$(bash "$L" probe | awk '/^Key/{print $2}')" "github.com-org-repo-c34fddf8b000" "key parity: $o"
done

printf '\n%d passed, %d failed\n' "$pass" "$failed"
[ "$failed" -eq 0 ]
