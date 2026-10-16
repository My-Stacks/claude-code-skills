#!/usr/bin/env node
// PreToolUse(Bash) hook: blocks commands that break the Stacklist team rules.
// Reads the hook JSON on stdin; exit 2 + stderr blocks the call and tells Claude why.
// Fails open: any internal error lets the command through.

import { execFileSync } from 'node:child_process'
import { realpathSync } from 'node:fs'
import { homedir } from 'node:os'
import { resolve, sep } from 'node:path'
import { pathToFileURL } from 'node:url'

// PR base per repo. Must match registry/repos.yaml (a test enforces it).
export const PR_BASE = {
  'stacklist-platform-v2': 'dev',
  'stacks-cloud-functions': 'dev',
  'stacklist-mcp': 'dev',
  'stacklist-surfaces-contract': 'main',
  'stacklist-admin': 'dev',
  'stacklist-capacitor': 'dev',
  'stacklist-radar': 'main',
  'stacklist-microservice-scrape': 'dev',
  'stacklist-hub-builder': 'main',
  'stacklist-extensions': 'dev',
  'stacklist-wrangler': 'main',
  'stacklist-shopify': 'feat/be-780-shopify-app-build',
  'stacklist-report-generator': 'main',
}
const MAX_WORKERS = 4
const BRANCH_OK = /^(feat|fix|chore|refactor|docs|test|perf|ci|build|style|revert|hotfix|release|deps|spike|ops|claude)\//

// ---- shell-ish parsing -------------------------------------------------------

const dropHeredocBodies = cmd => {
  const out = []
  let end = null
  for (const line of cmd.split('\n')) {
    if (end !== null) {
      if (line.trim() === end) end = null
      continue
    }
    out.push(line)
    const m = line.match(/<<-?\s*['"]?([A-Za-z_]\w*)['"]?/)
    if (m) end = m[1]
  }
  return out.join('\n')
}

/** Split into simple commands on newline, ;, &&, ||, |, & (quote-aware; keeps 2>&1). */
export const segments = cmd => {
  const text = dropHeredocBodies(cmd)
  const segs = []
  let cur = ''
  let quote = null
  for (let i = 0; i < text.length; i++) {
    const c = text[i]
    if (quote) {
      cur += c
      if (c === '\\' && quote === '"') cur += text[++i] ?? ''
      else if (c === quote) quote = null
      continue
    }
    if (c === "'" || c === '"') { quote = c; cur += c; continue }
    if (c === '\\') { cur += c + (text[++i] ?? ''); continue }
    const isRedirectAmp = c === '&' && (text[i - 1] === '>' || text[i + 1] === '>')
    if ((c === '\n' || c === ';' || c === '|' || c === '&') && !isRedirectAmp) {
      segs.push(cur)
      cur = ''
      if ((c === '&' || c === '|') && text[i + 1] === c) i++
      continue
    }
    cur += c
  }
  segs.push(cur)
  return segs.map(s => s.trim()).filter(Boolean)
}

/** Words of one simple command, quotes removed. A word containing $ is marked unknown. */
export const words = seg => {
  const out = []
  let cur = ''
  let quote = null
  let started = false
  let dynamic = false
  const push = () => { if (started) out.push({ text: cur, dynamic }); cur = ''; started = false; dynamic = false }
  for (let i = 0; i < seg.length; i++) {
    const c = seg[i]
    if (quote) {
      if (c === quote) quote = null
      else { if (c === '$' && quote === '"') dynamic = true; cur += c }
      continue
    }
    if (c === "'" || c === '"') { quote = c; started = true; continue }
    if (/\s/.test(c)) { push(); continue }
    if (c === '$' || c === '`') dynamic = true
    cur += c
    started = true
  }
  push()
  return out
}

const stripWrappers = ws => {
  let i = 0
  for (;;) {
    const t = ws[i]?.text
    if (t === undefined) break
    if (/^[A-Za-z_]\w*=/.test(t)) { i++; continue }
    if (['sudo', 'time', 'nice', 'command', 'exec', 'nohup'].includes(t)) { i++; continue }
    if (t === 'env') { i++; while (ws[i] && (/^-/.test(ws[i].text) || /^[A-Za-z_]\w*=/.test(ws[i].text))) i++; continue }
    if (t === 'timeout') {
      i++
      while (ws[i] && /^-/.test(ws[i].text)) { if (/^-(s|k)$/.test(ws[i].text)) i++; i++ }
      i++ // duration
      continue
    }
    break
  }
  return ws.slice(i)
}

/** Arguments after `jest` if this command runs jest, else null. */
export const jestArgs = ws => {
  const t = ws.map(w => w.text)
  const isJest = s => s === 'jest' || s?.endsWith('/jest')
  if (isJest(t[0])) return t.slice(1)
  let i = 1
  if (['npx', 'bunx', 'yarn'].includes(t[0])) {
    while (t[i]?.startsWith('-')) i++
    return isJest(t[i]) ? t.slice(i + 1) : null
  }
  if (t[0] === 'pnpm') {
    if (['exec', 'dlx'].includes(t[i])) i++
    return isJest(t[i]) ? t.slice(i + 1) : null
  }
  return null
}

// ---- repo detection ------------------------------------------------------------

const repoCache = new Map()
const repoFromPath = dir => {
  const names = Object.keys(PR_BASE).sort((a, b) => b.length - a.length)
  for (const comp of dir.split(sep).reverse()) {
    const hit = names.find(n => comp === n || comp.startsWith(`${n}-`))
    if (hit) return hit
  }
  return null
}
export const repoOf = dir => {
  if (!dir) return null
  if (repoCache.has(dir)) return repoCache.get(dir)
  let repo = null
  try {
    const url = execFileSync('git', ['-C', dir, 'remote', 'get-url', 'origin'], { timeout: 2000, stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim()
    const name = url.match(/\/([^/]+?)(?:\.git)?$/)?.[1]
    repo = name && name in PR_BASE ? name : null
  } catch { /* not a repo, or git unavailable */ }
  repo ??= repoFromPath(dir)
  repoCache.set(dir, repo)
  return repo
}

const expandHome = p => (p === '~' || p.startsWith('~/') ? homedir() + p.slice(1) : p)
const flagValue = (args, names) => {
  for (let i = 0; i < args.length; i++) {
    for (const n of names) {
      if (args[i] === n) return args[i + 1] ?? null
      if (args[i].startsWith(`${n}=`)) return args[i].slice(n.length + 1)
      if (n.length === 2 && args[i].startsWith(n) && args[i].length > 2 && !args[i].startsWith('--')) return args[i].slice(2)
    }
  }
  return undefined
}

// ---- rules ---------------------------------------------------------------------

const jestRules = (args, repo) => {
  if (repo === 'stacks-cloud-functions' && !args.some(a => a.startsWith('--selectProjects')))
    return 'In stacks-cloud-functions, bare jest also runs the e2e/integration projects that write to a real database. Add --selectProjects unit, or use `npm test`.'
  if (args.includes('--runInBand') || args.includes('-i')) return null
  const w = flagValue(args, ['--maxWorkers', '-w'])
  if (w === undefined || w === null)
    return `jest must run with a worker cap on this shared machine: add --maxWorkers=${MAX_WORKERS} (or --runInBand for a few files).`
  if (!/^\d+$/.test(w) || Number(w) > MAX_WORKERS)
    return `--maxWorkers=${w} is above the cap; use --maxWorkers=${MAX_WORKERS} or less.`
  return null
}

/** Branch names a git command creates (unknown $VAR names are skipped). */
export const createdBranches = ws => {
  const t = ws.map(w => w.text)
  if (t[0] !== 'git') return []
  let i = 1
  while (t[i]?.startsWith('-')) { if (t[i] === '-C' || t[i] === '-c') i++; i++ }
  const sub = t[i]
  const rest = ws.slice(i + 1)
  const after = flags => {
    const k = rest.findIndex(w => flags.includes(w.text))
    return k >= 0 && rest[k + 1] ? [rest[k + 1]] : []
  }
  let found = []
  if (sub === 'checkout') found = after(['-b', '-B'])
  else if (sub === 'switch') found = after(['-c', '-C', '--create', '--force-create'])
  else if (sub === 'worktree' && rest[0]?.text === 'add') found = after(['-b', '-B'])
  else if (sub === 'branch') {
    const LIST_OR_EDIT = /^(-d|-D|--delete|-m|-M|--move|-c|--copy|-l|--list|-a|--all|-r|--remotes|-v|-vv|--show-current|--contains|--merged|--no-merged|--set-upstream-to|-u|--unset-upstream|--edit-description)$/
    if (!rest.some(w => LIST_OR_EDIT.test(w.text))) {
      const first = rest.find(w => !w.text.startsWith('-'))
      if (first && !/^[<>]/.test(first.text)) found = [first]
    }
  }
  return found.filter(w => !w.dynamic).map(w => w.text)
}

const branchRule = ws => {
  const bad = createdBranches(ws).filter(b => !BRANCH_OK.test(b))
  if (bad.length === 0) return null
  const fixes = bad.map(b => `${b} -> ${b.includes('/') ? b.replace(/^[^/]+\//, 'feat/') : `feat/${b}`}`)
  return `Branch names start with a type prefix (feat/, fix/, chore/, ...), never a person's name. Rename: ${fixes.join(', ')}.`
}

const prRule = (ws, repoAtDir) => {
  const t = ws.map(w => w.text)
  if (!(t[0] === 'gh' && t[1] === 'pr' && t[2] === 'create')) return null
  const args = t.slice(3)
  const repoFlag = flagValue(args, ['--repo', '-R'])
  const repo = repoFlag ? repoFlag.split('/').pop() : repoAtDir
  if (!repo || PR_BASE[repo] !== 'dev') return null
  const base = flagValue(args, ['--base', '-B'])
  const head = flagValue(args, ['--head', '-H'])
  if (!base)
    return `In ${repo}, pass --base explicitly (--base dev, or the feature's umbrella). Without it the PR may go to the repo's default branch, which can be main.`
  if (/^(main|master)$/.test(base) && head !== 'dev')
    return `PRs in ${repo} target dev (or the feature's umbrella, e.g. feat/stream-video-poc), not ${base}. A dev -> main promotion is human-only and must say --head dev.`
  return null
}

/** First rule violation in the command, or null. `cwd` is where the command starts. */
export const check = (cmd, cwd) => {
  let dir = cwd
  for (const seg of segments(cmd)) {
    const ws = stripWrappers(words(seg))
    if (ws.length === 0) continue
    if (ws[0].text === 'cd') {
      if (ws[1] && !ws[1].dynamic) dir = resolve(dir ?? '/', expandHome(ws[1].text))
      continue
    }
    let segDir = dir
    if (ws[0].text === 'git') {
      const k = ws.findIndex(w => w.text === '-C')
      if (k >= 0 && ws[k + 1] && !ws[k + 1].dynamic) segDir = resolve(dir ?? '/', expandHome(ws[k + 1].text))
    }
    const jest = jestArgs(ws)
    const why =
      (jest && jestRules(jest, repoOf(segDir))) ||
      branchRule(ws) ||
      prRule(ws, repoOf(segDir))
    if (why) return why
  }
  return null
}

const main = async () => {
  let raw = ''
  for await (const chunk of process.stdin) raw += chunk
  const input = JSON.parse(raw)
  const cmd = input?.tool_input?.command
  if (typeof cmd !== 'string') return
  const why = check(cmd, input.cwd ?? process.cwd())
  if (why) {
    process.stderr.write(`stacklist rule: ${why}\n`)
    process.exit(2)
  }
}

const isMain = () => {
  try { return import.meta.url === pathToFileURL(realpathSync(process.argv[1])).href } catch { return false }
}
if (isMain()) main().catch(() => process.exit(0))
