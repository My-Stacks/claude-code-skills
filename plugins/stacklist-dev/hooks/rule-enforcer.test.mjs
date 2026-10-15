import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { test } from 'node:test'
import { fileURLToPath } from 'node:url'

import { check, createdBranches, jestCap } from './rule-enforcer.mjs'

const PV2 = '/x/stacklist/stacklist-platform-v2'
const CF = '/x/stacklist/stacks-cloud-functions/functions'
const HOOK = fileURLToPath(new URL('./rule-enforcer.mjs', import.meta.url))

test('jest needs a worker cap', () => {
  assert.ok(jestCap('npx jest src/a.test.ts'))
  assert.ok(jestCap('cd app && CI=1 jest a | tail'))
  assert.equal(jestCap('npx jest --maxWorkers=4 a'), null)
  assert.equal(jestCap('npx jest --runInBand a'), null)
  assert.equal(jestCap('grep -r "npx jest" docs'), null)
  assert.equal(jestCap('cat jest.config.ts'), null)
})

test('cloud-functions jest needs an explicit project', () => {
  assert.match(check('npx jest --maxWorkers=4', CF), /selectProjects/)
  assert.equal(check('npx jest --maxWorkers=4 --selectProjects unit', CF), null)
  assert.equal(check('npm test', CF), null)
})

test('branch names need a type prefix; claude/ is allowed for bots', () => {
  assert.deepEqual(createdBranches('git worktree add ../wt -b feat/be-1 origin/dev'), ['feat/be-1'])
  assert.match(check('git checkout -b martina/fe-1234-x', PV2), /feat\/fe-1234-x/)
  assert.equal(check('git checkout -b claude/fix-bug-12', PV2), null)
  assert.equal(check('git checkout -b fix/be-9', PV2), null)
  assert.equal(check('git checkout main', PV2), null)
})

test('PR base main refused in dev-flow repos, allowed for promotions and elsewhere', () => {
  assert.match(check('gh pr create --base main --title x', PV2), /target dev/)
  assert.equal(check('gh pr create --base dev', PV2), null)
  assert.equal(check('gh pr create --base main --head dev', PV2), null)
  assert.equal(check('gh pr create --base main', '/x/stacklist/stacklist-radar'), null)
})

test('as a hook: exit 2 + reason on a violation, exit 0 otherwise, fail open on junk', () => {
  const run = input => spawnSync('node', [HOOK], { input })
  const bad = run(JSON.stringify({ tool_name: 'Bash', cwd: PV2, tool_input: { command: 'git checkout -b martina/x' } }))
  assert.equal(bad.status, 2)
  assert.match(bad.stderr.toString(), /stacklist rule/)
  assert.equal(run(JSON.stringify({ tool_name: 'Bash', cwd: PV2, tool_input: { command: 'git status' } })).status, 0)
  assert.equal(run('not json').status, 0)
})
