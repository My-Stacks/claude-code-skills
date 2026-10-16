#!/usr/bin/env node
// PreToolUse(Bash) hook: blocks commands that break the Stacklist team rules.
// Reads the hook JSON on stdin; exit 2 + stderr blocks the call and tells Claude why.
// Fails open: any internal error lets the command through.
//
// This is a guardrail against honest mistakes, not a security boundary: it parses
// common shell, not every shell construct.

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
const TRUNKS = ['main', 'master', 'staging']
const BRANCH_OK = /^(feat|fix|chore|refactor|docs|test|perf|ci|build|style|revert|hotfix|release|deps|spike|ops|claude)\//

// ---- shell-ish parsing -------------------------------------------------------

/**
 * Split into simple commands on newline, ;, &&, ||, |, &, ( and ) (quote-aware;
 * keeps 2>&1 and $(...)). Skips heredoc bodies and unquoted # comments.
 * A herestring (<<<) and a << inside quotes are not heredocs.
 */
export const segments = text => {
  const segs = []
  const heredocs = []
  let cur = ''
  let quote = null
  const flush = () => { segs.push(cur); cur = '' }
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
    if (c === '#' && (i === 0 || /[\s;&|()]/.test(text[i - 1]))) {
      while (i + 1 < text.length && text[i + 1] !== '\n') i++
      continue
    }
    if (c === '<' && text[i + 1] === '<' && text[i - 1] !== '<' && text[i + 2] !== '<') {
      const m = text.slice(i + 2).match(/^-?\s*(['"]?)([A-Za-z_]\w*)\1/)
      if (m) heredocs.push(m[2])
      cur += c
      continue
    }
    if (c === '\n' && heredocs.length) {
      flush()
      let j = i + 1
      while (heredocs.length) {
        const endTag = heredocs.shift()
        for (;;) {
          const nl = text.indexOf('\n', j)
          const line = text.slice(j, nl === -1 ? text.length : nl)
          j = nl === -1 ? text.length : nl + 1
          if (line.trim() === endTag || nl === -1) break
        }
      }
      i = j - 1
      continue
    }
    const isRedirectAmp = c === '&' && (text[i - 1] === '>' || text[i + 1] === '>')
    const isSubst = c === '(' && text[i - 1] === '$'
    if (((c === '\n' || c === ';' || c === '|' || c === '&') && !isRedirectAmp) || ((c === '(' || c === ')') && !isSubst)) {
      flush()
      if ((c === '&' || c === '|') && text[i + 1] === c) i++
      continue
    }
    cur += c
  }
  flush()
  return segs.map(s => s.trim()).filter(Boolean)
}

/** Words of one simple command, quotes removed. A word containing $ or ` is marked dynamic. */
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
    if (['sudo', 'time', 'command', 'exec', 'nohup'].includes(t)) { i++; continue }
    if (t === 'nice') {
      i++
      if (ws[i]?.text === '-n') i += 2
      else if (/^-/.test(ws[i]?.text ?? '')) i++
      continue
    }
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

/** Value of a flag: `--long value`, `--long=value`, or an exact short `-X value`. */
const flagValue = (args, names) => {
  for (let i = 0; i < args.length; i++) {
    for (const n of names) {
      if (args[i] === n) return args[i + 1] ?? null
      if (n.startsWith('--') && args[i].startsWith(`${n}=`)) return args[i].slice(n.length + 1)
    }
  }
  return undefined
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

// ---- rules ---------------------------------------------------------------------

const jestRules = (args, repo) => {
  if (repo === 'stacks-cloud-functions') {
    const projects = []
    for (let i = 0; i < args.length; i++) {
      if (args[i].startsWith('--selectProjects=')) projects.push(...args[i].split('=')[1].split(','))
      else if (args[i] === '--selectProjects')
        for (let j = i + 1; j < args.length && !args[j].startsWith('-'); j++) projects.push(...args[j].split(','))
    }
    if (projects.length === 0 || projects.some(p => p !== 'unit'))
      return 'In stacks-cloud-functions only the unit jest project is safe; e2e and integration write to a real database. Use --selectProjects unit, or `npm test`.'
  }
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
    for (let k = 0; k < rest.length; k++) {
      const w = rest[k].text
      if (flags.includes(w)) return rest[k + 1] ? [rest[k + 1]] : []
      for (const f of flags) {
        if (f.startsWith('--') && w.startsWith(`${f}=`)) return [{ ...rest[k], text: w.slice(f.length + 1) }]
        if (!f.startsWith('--') && w.startsWith(f) && w.length > 2 && !w.startsWith('--')) return [{ ...rest[k], text: w.slice(2) }]
      }
    }
    return []
  }
  let found = []
  if (sub === 'checkout') found = after(['-b', '-B'])
  else if (sub === 'switch') found = after(['-c', '-C', '--create', '--force-create'])
  else if (sub === 'worktree' && rest[0]?.text === 'add') found = after(['-b', '-B'])
  else if (sub === 'push') {
    // git push <remote> <src>:<dst> creates <dst> on the remote
    for (const w of rest) {
      if (!w.text.includes(':') || w.text.startsWith('-')) continue
      const dst = w.text.split(':').pop().replace(/^refs\/heads\//, '')
      if (dst && !dst.startsWith('refs/') && !TRUNKS.includes(dst) && dst !== 'dev') found.push({ ...w, text: dst })
    }
  } else if (sub === 'branch') {
    const LIST_OR_EDIT = /^(-d|-D|--delete|-m|-M|--move|-c|-C|--copy|-l|--list|-a|--all|-r|--remotes|-v|-vv|--show-current|--contains|--merged|--no-merged|--set-upstream-to|-u|--unset-upstream|--edit-description)$/
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

const prRule = (ws, repoAt) => {
  const t = ws.map(w => w.text)
  if (!(t[0] === 'gh' && t[1] === 'pr' && t[2] === 'create')) return null
  const args = t.slice(3)
  const repoFlag = flagValue(args, ['--repo', '-R'])
  const repo = repoFlag ? repoFlag.split('/').pop() : repoAt()
  const own = PR_BASE[repo]
  if (!own) return null
  const base = flagValue(args, ['--base', '-B'])
  const head = flagValue(args, ['--head', '-H'])
  if (!base && own !== 'main')
    return `In ${repo}, pass --base explicitly (--base ${own}, or the feature's umbrella). Without it the PR goes to the repo's default branch, which can be main.`
  if (base && base !== own && TRUNKS.includes(base) && !(head === 'dev' || head?.startsWith('release/')))
    return `PRs in ${repo} target ${own} (or the feature's umbrella), not ${base}. Promotions are human-only and come from --head dev or a release/* branch.`
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
    if (['bash', 'sh', 'zsh'].includes(ws[0].text)) {
      const k = ws.findIndex(w => w.text === '-c')
      const inner = k >= 0 && ws[k + 1] ? check(ws[k + 1].text, segDir) : null
      if (inner) return inner
      continue
    }
    const jest = jestArgs(ws)
    const why = (jest && jestRules(jest, repoOf(segDir))) || branchRule(ws) || prRule(ws, () => repoOf(segDir))
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
