import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { mkdtempSync, readFileSync, symlinkSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { test } from 'node:test'
import { fileURLToPath } from 'node:url'

import { PR_BASE, check, createdBranches, segments, words } from './rule-enforcer.mjs'

// Paths that are not real git checkouts: the repo is read from the path.
const PV2 = '/x/stacklist/stacklist-platform-v2'
const CF = '/x/stacklist/stacks-cloud-functions/functions'
const MCP = '/x/stacklist/stacklist-mcp'
const RADAR = '/x/stacklist/stacklist-radar'
const HOOK = fileURLToPath(new URL('./rule-enforcer.mjs', import.meta.url))
const ok = (cmd, cwd = PV2) => assert.equal(check(cmd, cwd), null, cmd)
const blocked = (cmd, cwd, re) => assert.match(check(cmd, cwd) ?? '', re, cmd)

test('jest needs a worker cap of at most 4', () => {
  blocked('npx jest src/a.test.ts', PV2, /worker cap/)
  blocked('cd app && CI=1 jest a | tail', PV2, /worker cap/)
  ok('npx jest --maxWorkers=4 a')
  ok('npx jest --maxWorkers 2 a')
  ok('npx jest --runInBand a')
  ok('npx jest -i a')
  blocked('npx jest --maxWorkers=16', PV2, /above the cap/)
  blocked('npx jest --maxWorkers=50%', PV2, /above the cap/)
})

test('a flag on another command does not satisfy the cap', () => {
  blocked('npx jest src | grep -i fail', PV2, /worker cap/)
  blocked('npx jest src; echo -w 2', PV2, /worker cap/)
})

test('jest is seen on later lines and behind wrappers', () => {
  blocked('cd x\nnpx jest', PV2, /worker cap/)
  blocked('timeout 600 npx jest', PV2, /worker cap/)
  blocked('env CI=1 npx jest', PV2, /worker cap/)
  blocked('time pnpm exec jest', PV2, /worker cap/)
})

test('text that only mentions jest is not jest', () => {
  ok('grep -r "npx jest" docs')
  ok('cat jest.config.ts')
  ok("cat > f.md <<'EOF'\nnpx jest\ngit checkout -b martina/x\nEOF")
})

test('cloud-functions jest needs an explicit project, read from the real directory', () => {
  blocked('npx jest --maxWorkers=4', CF, /selectProjects/)
  ok('npx jest --maxWorkers=4 --selectProjects unit', CF)
  ok('npm test', CF)
  blocked('cd /x/stacklist/stacks-cloud-functions/functions\nnpx jest --maxWorkers=4', PV2, /selectProjects/)
  ok('npx jest --maxWorkers=4 # see stacks-cloud-functions', PV2)
})

test('branch names need a type prefix; claude/ allowed; no false positives', () => {
  blocked('git checkout -b martina/fe-1234-x', PV2, /feat\/fe-1234-x/)
  blocked('git worktree add ../wt -b martina/x origin/dev', PV2, /type prefix/)
  ok('git checkout -b claude/fix-bug-12')
  ok('git switch -c fix/be-9')
  ok('git checkout main')
  ok('git checkout feat/x && gh pr create -B dev')
  ok('git checkout main && curl -b c.txt https://example.com')
  ok('git branch > out.txt')
  ok('git branch -D old && git branch --show-current')
  ok('git checkout -b "$BRANCH"')
  assert.deepEqual(createdBranches(words('git -C ../x worktree add ../wt -b feat/be-1 origin/dev')), ['feat/be-1'])
})

test('PR base: dev-flow repos need an explicit non-trunk base', () => {
  blocked('gh pr create --base main --title x', PV2, /target dev/)
  blocked('gh pr create --title x', MCP, /pass --base explicitly/)
  ok('gh pr create --base dev', PV2)
  ok('gh pr create -B feat/stream-video-poc', PV2)
  ok('gh pr create --base main --head dev', MCP)
})

test('PR repo comes from -R or the directory, never the body', () => {
  ok('gh pr create --base main --body "see stacklist-mcp#3"', RADAR)
  ok('gh pr create -R My-Stacks/stacklist-surfaces-contract --base main', PV2)
  blocked('gh pr create -R My-Stacks/stacklist-admin --base main', RADAR, /stacklist-admin/)
})

test('segments keep 2>&1 and split &&, ||, ;, |, newlines', () => {
  assert.deepEqual(segments('a 2>&1 && b || c; d | e\nf'), ['a 2>&1', 'b', 'c', 'd', 'e', 'f'])
})

test('PR_BASE matches registry/repos.yaml', () => {
  const yaml = readFileSync(fileURLToPath(new URL('../registry/repos.yaml', import.meta.url)), 'utf8')
  const fromYaml = {}
  let repo = null
  for (const line of yaml.split('\n')) {
    const name = line.match(/^ {2}([\w-]+):\s*$/)?.[1]
    if (name) repo = name
    const base = line.match(/^ {4}pr_base:\s*([^\s#]+)/)?.[1]
    if (repo && base) fromYaml[repo] = base
  }
  assert.deepEqual(PR_BASE, fromYaml)
})

test('as a hook: exit 2 + reason, exit 0 otherwise, fail open, works through a symlink', () => {
  const run = (input, hook = HOOK) => spawnSync('node', [hook], { input })
  const bad = JSON.stringify({ tool_name: 'Bash', cwd: PV2, tool_input: { command: 'git checkout -b martina/x' } })
  const res = run(bad)
  assert.equal(res.status, 2)
  assert.match(res.stderr.toString(), /stacklist rule/)
  assert.equal(run(JSON.stringify({ tool_name: 'Bash', cwd: PV2, tool_input: { command: 'git status' } })).status, 0)
  assert.equal(run('not json').status, 0)
  const link = join(mkdtempSync(join(tmpdir(), 'rule enforcer ')), 'linked.mjs')
  symlinkSync(HOOK, link)
  assert.equal(run(bad, link).status, 2)
})
