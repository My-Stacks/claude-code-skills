#!/usr/bin/env node
// PreToolUse(Bash) hook: blocks commands that break the Stacklist team rules.
// Reads the hook JSON on stdin; exit 2 + stderr blocks the call and tells Claude why.
// Fails open: any internal error lets the command through.

const SEG = String.raw`(^|&&|\|\||;|\||\(|\bthen\b|\bdo\b)(\s*(?:[A-Z_][A-Z0-9_]*=\S+\s+)*)`
const JEST = new RegExp(
  SEG + String.raw`((?:npx|pnpm(?:\s+exec)?|yarn)\s+jest|(?:\.\/)?(?:\S*\/)?node_modules\/\.bin\/jest|jest)(?=\s|$|;|&|\||\))`,
)
const BRANCH_OK = /^(feat|fix|chore|refactor|docs|test|perf|ci|build|style|revert|hotfix|release|deps|spike|ops|claude)\//
// Repos whose PRs go to dev (registry pr_base: dev). main only takes dev -> main promotions.
const DEV_BASE_REPOS = [
  'stacklist-platform-v2', 'stacks-cloud-functions', 'stacklist-mcp', 'stacklist-admin',
  'stacklist-capacitor', 'stacklist-microservice-scrape', 'stacklist-extensions',
]

export const hasJest = cmd => JEST.test(cmd)

export const jestCap = cmd =>
  hasJest(cmd) && !/--maxWorkers|--runInBand|(^|\s)-i(\s|$)|(^|\s)-w(\s|=)/.test(cmd)
    ? 'jest must run with a worker cap on this shared machine: add --maxWorkers=4 (or --runInBand for a few files).'
    : null

export const cloudFunctionsJest = (cmd, where) =>
  where.includes('stacks-cloud-functions') && hasJest(cmd) && !/--selectProjects/.test(cmd)
    ? 'In stacks-cloud-functions, bare jest also runs the e2e/integration projects that write to a real database. Add --selectProjects unit, or use `npm test`.'
    : null

export const createdBranches = cmd => {
  const names = []
  const add = re => { for (const m of cmd.matchAll(re)) if (m[1]) names.push(m[1].replace(/^['"]|['"]$/g, '')) }
  add(/\bgit\s+checkout\s+(?:\S+\s+)*?-[bB]\s+(\S+)/g)
  add(/\bgit\s+switch\s+(?:\S+\s+)*?(?:-[cC]|--create|--force-create)\s+(\S+)/g)
  add(/\bgit\s+worktree\s+add\s+(?:\S+\s+)*?-[bB]\s+(\S+)/g)
  add(/\bgit\s+branch\s+(?!-)([^\s;&|]+)/g)
  return names
}

export const branchNames = cmd => {
  const bad = createdBranches(cmd).filter(b => !BRANCH_OK.test(b))
  if (bad.length === 0) return null
  const fixes = bad.map(b => `${b} -> ${b.includes('/') ? b.replace(/^[^/]+\//, 'feat/') : `feat/${b}`}`)
  return `Branch names start with a type prefix (feat/, fix/, chore/, ...), never a person's name. Rename: ${fixes.join(', ')}.`
}

export const prBase = (cmd, where) => {
  if (!/\bgh\s+pr\s+create\b/.test(cmd)) return null
  const repo = DEV_BASE_REPOS.find(r => where.includes(r))
  if (!repo) return null
  const base = cmd.match(/(?:--base|-B)[\s=]+['"]?([^\s'"]+)/)?.[1]
  const head = cmd.match(/(?:--head|-H)[\s=]+['"]?([^\s'"]+)/)?.[1]
  if (!base || !/^(main|master)$/.test(base) || head === 'dev') return null
  return `PRs in ${repo} target dev (or the feature's umbrella branch, e.g. feat/stream-video-poc), not ${base}. A dev -> main promotion is human-only and must say --head dev.`
}

export const check = (cmd, where) =>
  cloudFunctionsJest(cmd, where) ?? branchNames(cmd) ?? prBase(cmd, where) ?? jestCap(cmd)

const main = async () => {
  let raw = ''
  for await (const chunk of process.stdin) raw += chunk
  const input = JSON.parse(raw)
  const cmd = input?.tool_input?.command
  if (typeof cmd !== 'string') return
  const why = check(cmd, `${input.cwd ?? ''} ${cmd}`)
  if (why) {
    process.stderr.write(`stacklist rule: ${why}\n`)
    process.exit(2)
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch(() => process.exit(0))
}
