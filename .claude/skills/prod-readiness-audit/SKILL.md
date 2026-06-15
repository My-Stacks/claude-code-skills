---
name: prod-readiness-audit
version: "1.0"
description: >-
  Audits any codebase for production-readiness across four buckets —
  infra/security/compliance, engineering, design/UX, and product analytics —
  then returns a red/yellow/green scorecard and the single highest-priority fix.
  Accepts an optional path argument to scope the audit to a subdirectory
  (e.g. /prod-readiness-audit stacklist-platform-v2).
trigger: /prod-readiness-audit
allowed-tools: Read Glob Grep Bash(grep *) Bash(rg *) Bash(cat *) Bash(ls *) Bash(find *) Bash(head *) Bash(tail *) Bash(wc *) Bash(jq *) Bash(git log *) Bash(git ls-files *) Bash(git remote *)
---

# Production-Readiness Audit

A prototype got interest. Now it has to ship to real customers. This skill
audits the gap between the two.

**The model:** the prototype is the dot in the middle. Production is everything
around it — four buckets the prototype tool didn't build for you:

1. Infra · Security · Compliance
2. Engineering best practices
3. Design & UX
4. Product analytics

Score every line, shade every bucket, name the one fix that matters most.

## Path argument

If invoked with a path argument (e.g. `/prod-readiness-audit stacklist-platform-v2`),
scope all reads and grep commands to that directory. If no path is given, use
the current working directory as the root.

## Rules of engagement (read-only)

This audit **only inspects**. It must never:
- start servers or run the app
- hit the network or call external endpoints
- write, move, or modify any file (this includes not writing a report file)
- run build/test/lint or any script that mutates state

Allowed: read files, `grep`/`rg`, `find`/`ls`, `cat`/`head`, `git log`/`git ls-files`,
inspect `package.json`/lockfiles/configs. If something can't be determined by
reading the repo, score it `?` — do not guess and do not go fetch it.

**Evidence over presence.** A dependency in `package.json` is not a passing
score. Verify the capability is actually *wired* — `init` called, imported at the
entry point, configured, invoked — by reading the bootstrap/config file, not the
lockfile. Score what the code **does**, not what it imports. A grep hit is a lead,
not a verdict: open the file and confirm. When the dependency list and the
implementation disagree, the implementation wins. Watch for:
- `@sentry/*` in deps ≠ `Sentry.init()` actually running at startup
- an analytics SDK installed ≠ events actually fired
- RLS *enabled* on a table ≠ RLS *policies* that scope rows to a user
- a test/example secret in a `*.spec`/`.env.example` file ≠ a real leaked key

## Scoring legend

| Mark | Meaning |
|:---:|---|
| 🟢 G | Handled — production-grade |
| 🟡 Y | Partial — started but gaps remain |
| 🔴 R | Missing / at-risk — would bite in production |
| ⚪ ? | Not sure — can't tell from the code alone |

## Workflow

```
Audit progress:
- [ ] Step 0: Orient — detect stack (frontend tool, backend, hosting, analytics, AI)
- [ ] Step 1: Score each line in all four buckets (see § The four buckets)
- [ ] Step 2: Shade each bucket from its line scores
- [ ] Step 3: Pick the single top fix
- [ ] Step 4: Emit the scorecard in the output format below
```

**Step 0 — Orient.** Get the lay of the land:
- Frontend / prototype origin: Lovable, v0, Bolt, Replit, Cursor markers in `README`, comments, or commit history.
- Backend: Supabase (`supabase/`, `@supabase/*`), Firebase, a custom API, or none.
- Hosting: `vercel.json`, `netlify.toml`, `Dockerfile`, `fly.toml`, `render.yaml`, or unknown.
- Observability: error tracking (`Sentry.init`), structured logs, metrics/APM (`prom-client`, `@opentelemetry`, `dd-trace`, `statsd`), `/health` — scored in bucket 02.
- Analytics: `posthog`, `mixpanel`, `amplitude`, GA in deps or code — scored in bucket 04.
- AI: any LLM SDK (`openai`, `anthropic`, `@ai-sdk/*`, `langchain`, etc.).

**Headless / backend service (no UI)?** Score its **observability** (logs + error
tracking + metrics/APM) under **bucket 02** — that's where the deck puts it.
Bucket 04 (product analytics) is end-user behavior, which usually lives in the
consuming frontend; mark it ⚪ N/A for a pure backend rather than forcing a score.
Map bucket 03's UI lines to their API equivalents (see that bucket).

**Step 1 — Score each line** using the detail in § The four buckets. Keep one
short, evidence-based finding per line (cite a file/path when you can).

**Step 2 — Shade each bucket.** A bucket takes the color of its worst *known*
line: any 🔴 → bucket is 🔴; else any 🟡 → 🟡; else all 🟢 → 🟢. Surface ⚪
unknowns explicitly rather than letting them hide a bucket's true state.

**Step 3 — Pick the top fix.** One fix — the highest-leverage thing to do next,
usually the most dangerous 🔴 (data leaks and exposed secrets outrank polish).
Say what it is and what it prevents.

**Step 4 — Emit the scorecard** using the output format below. Output to chat only.

## The four buckets

Each check has its signals (read-only) and a 🟢/🟡/🔴 rubric. Apply *evidence over
presence* throughout: a grep hit is a lead — open the file and confirm.

### 01 · Infra · Security · Compliance

Where prototypes leak data and get founders in real trouble. Score security
conservatively: an exploitable-today gap is 🔴, not 🟡. *(The deck's "DB
monitoring" is scored with observability in bucket 02; "replatforming for scale"
is folded into "Hosted on something you own" below.)*

**Real database + auth** — real DB + real auth, not localStorage/mock/hardcoded.
- Signals: backend `@supabase/*`/firebase/prisma/an ORM; auth `next-auth`/`clerk`/`lucia`/`@supabase/auth`/JWT middleware. Red flags: localStorage holding auth, hardcoded user arrays, a single shared key as "login", no auth at all.
- 🟢 real DB + real auth, sessions enforced server-side · 🟡 real DB but thin/client-only auth · 🔴 toy/mock backend, localStorage auth, or none.

**User data isolation** — authorization, not just authentication: user A can't reach user B's rows.
- Signals: Supabase RLS — `grep -riE "enable row level security|create policy" supabase/` (**RLS enabled ≠ policies exist**; with the service-role key the server *bypasses* RLS, so isolation then rests entirely on app-level `.eq('user_id', …)` scoping). Custom API: every query scoped to the *session* user, not a client-supplied id (IDOR).
- 🟢 RLS policies per-user, or every query scoped to the session user · 🟡 inconsistent, or app-scoping only with no DB backstop · 🔴 no RLS / no per-user scoping — anyone reaches anyone's data.

**API keys in env, not in repo** — secrets come from the environment, never committed.
- Signals: secret scan `grep -rnoE "sk_live_|sk-ant-|AKIA[0-9A-Z]{16}|BEGIN (RSA )?PRIVATE KEY|service_role.{0,3}eyJ"`; env usage (`process.env`/`ConfigService`). Distinguish public-by-design (Supabase anon key, `NEXT_PUBLIC_*`) from real secrets (service_role, LLM/payment keys). Check git history. A key in a `*.spec`/`.env.example` is a test/placeholder, not a leak.
- 🟢 no secrets in source or history; all read from env · 🟡 in env now but a secret sits in git history (rotate) · 🔴 a live secret key is in the current code.

**Secrets in .gitignore** — `.env` and friends are ignored.
- Signals: `cat .gitignore` → `.env`, `.env.local`, `.env*.local`; `git ls-files | grep -E "\.env"` returns nothing (a placeholder `.env.example` is fine).
- 🟢 `.env*` ignored, none tracked · 🟡 ignored but an env file (or `.env.example` with real values) tracked · 🔴 no entry and/or a real `.env` committed.

**Hosted on something you own (and able to scale)** — runs on infra the team controls, not the prototype tool's sandbox — and won't fall over under real load. *(folds the deck's "Hosting (Lovable → Live)" + "Replatforming for scale".)*
- Signals: `vercel.json`/`netlify.toml`/`Dockerfile`/`fly.toml`/`render.yaml`/CI deploy, or a documented host in README; README/commit URLs pointing only at a Lovable/Bolt/Replit preview = not yet yours. Scale signals: connection pooling (Supabase pooler/pgBouncer), indexes on hot query paths, pagination on list endpoints, no obvious N+1 — vs. prototype-tool defaults that need replatforming before real traffic.
- 🟢 owned host + room to scale (pooling/indexes) · 🟡 deployable but on the prototype tool's hosting, or a known scale ceiling · 🔴 trapped in the prototype sandbox / needs replatforming before launch · ⚪ host & load characteristics not determinable from the repo.

**Compliance you actually need** — if the domain demands it (health→HIPAA, EU→GDPR, payments→PCI), the basics exist. Most need *some*, not all.
- Signals: infer domain from README/UI/data model (PHI, PII, payments, minors, call recording). Look for privacy policy, consent flows, cookie banner, BAA, encryption-at-rest, audit logging, data-retention notes. Often ⚪ from code alone.
- 🟢 relevant need identified + basics implemented · 🟡 need clear, partial measures · 🔴 clearly regulated data (e.g. PHI, call recordings) with none of the basics · ⚪ need not determinable from code.

### 02 · Engineering best practices

What separates "works in the demo" from "survives real users."

**Errors handled, no silent failures** — failures are caught and surfaced; the app degrades gracefully.
- Signals: risky calls (`fetch`/axios/DB/LLM) wrapped in `try/catch`/`.catch`; smell for empty `catch {}`; an error boundary (`ErrorBoundary`, route `error.tsx`/`global-error.tsx`).
- 🟢 risky paths wrapped + user-facing fallback + error boundary · 🟡 some handling, but empty catches / unguarded async remain · 🔴 errors largely unhandled or swallowed.

**Logging + error tracking** — when something breaks in prod, the team finds out and can diagnose it. Three pillars — **logs, error tracking, metrics**.
- Signals — logs + errors: error-tracking SDK (`@sentry/*`, bugsnag, rollbar) **initialized** (`Sentry.init`/DSN configured), not just installed; a structured logger (`pino`/`winston`) vs scattered `console.log`.
- Signals — metrics/APM (a separate leg, often missing even when logs + Sentry exist): `prom-client`/`@opentelemetry`/`dd-trace`/`statsd`, a `/metrics` endpoint, `Counter`/`Gauge`/`Histogram`; RED per endpoint (Rate/Errors/Duration), queue/job metrics (BullMQ depth/failures), **DB monitoring** (slow queries, connection-pool metrics), `/health`. **Logs + Sentry present ≠ metrics exist** — verify separately.
- 🟢 error tracking initialized + structured logging + metrics/APM (incl. DB monitoring) on the core paths · 🟡 logs + error tracking but **no metrics/APM** (can't answer latency/throughput/queue-depth) · 🔴 no error tracking; only `console.log`.

**AI tested beyond happy-path inputs** — *(⚪ N/A if the product has no AI)*. If it uses an LLM, it's exercised on messy/adversarial/empty inputs, with evals.
- Signals: AI present? (`openai`/`anthropic`/`@ai-sdk`/`langchain`). Evals/tests: an `evals/` suite, mocked-provider tests, malformed-input/failure-path tests, input validation before the prompt.
- 🟢 evals/tests cover non-happy-path inputs · 🟡 manual/ad-hoc testing only · 🔴 AI present but only ever run on the demo input · ⚪ N/A — no AI.

**Guardrail on what the AI can do** — *(⚪ N/A if no AI)*. The model can't be steered into harmful/unbounded behavior or expensive actions.
- Signals: scoped system prompt (not empty/trivial); input/output validation (moderation, zod/structured-output parsing); bounded actions (rate limiting, max tokens, cost caps) on any tool/DB the AI touches.
- 🟢 scoped prompt + I/O validation + bounded actions · 🟡 some constraints (e.g. a system prompt) but no validation/limits · 🔴 raw input → model → action with no guardrails · ⚪ N/A.

**Deploy + roll back safely** — shipping is repeatable, reversible, and gated by tests. *(folds the deck's "Testing".)*
- Signals: CI/CD (`.github/workflows`, `vercel.json`/`netlify.toml`, deploy script); rollback (platform instant rollback, tagged releases); versioned migrations with `down`/revert (`supabase/migrations`, `prisma/migrations`, typeorm). **Testing**: a runner wired (`jest`/`vitest`/`pytest`) with *actual* test files (count them — not 0 behind a `"test"` script) and CI running them on the core paths. Red flag: push-to-main-and-pray, no migrations, no tests.
- 🟢 automated deploy + rollback + versioned migrations + meaningful tests in CI · 🟡 deploys exist but rollback manual / migrations ad-hoc / thin test coverage · 🔴 no repeatable deploy or rollback, or ~0 tests · ⚪ hosting/deploy not determinable.

### 03 · Design & UX

Prototypes demo with seeded data and a happy path. Real users arrive with an
empty account and find the broken edges. Judge the *actual* flow a real user
hits, not the polished demo path. *(For a headless backend, map these to their
API equivalents — see below — rather than N/A'ing them.)*

**Onboarding for a new user with no data** — a brand-new, zero-data user knows what to do next.
- Signals: welcome/onboarding flow, guided first action, or seed/sample data; does the main view render nothing meaningful without pre-existing data? `grep -riE "onboard|getting started|welcome|first.?run|setup wizard"`.
- 🟢 deliberate new-user path (onboarding, empty-state guidance, or starter data) · 🟡 usable but no guidance · 🔴 unusable/confusing until data exists that only a power user could create.

**Real empty + error states** — every list/view has a designed "nothing here yet" and "this failed" state.
- Signals: empty states (`length === 0` branch, "no X yet"), loading (skeleton/`Suspense`/`loading.tsx` that resolves), error UI + a 404/not-found page. Red flag: `data.map(...)` with no empty/loading/error guard.
- 🟢 empty + loading + error states designed across main views · 🟡 some handled (e.g. loading) but empty/error missing in places · 🔴 unguarded rendering — blank screens or raw errors.
- **Backend equivalent:** consistent API error responses / exception filters, DTO/request validation, proper status codes + 404 handling, Swagger/contract docs.

### 04 · Product analytics

Can you see what *users* actually do — or are you guessing? This bucket is
end-user behavior: **PostHog, Mixpanel, event tracking, knowing what users
actually do.** (System-health observability lives in bucket 02.) Rule: **GA pageviews ≠ behavioral analytics.**

**Analytics wired in** — a behavioral analytics flow, not just a pageview tag.
- Signals: a behavioral platform (`posthog`/`mixpanel`/`amplitude`/`heap`) initialized + mounted, named events through a deliberate taxonomy (a central `track()` wrapper / `events.ts`), and `identify()` tying events to users. GA4 / `@vercel/analytics` / Plausible are traffic-only and need custom events layered on to count.
- 🟢 behavioral platform + named events + `identify()` · 🟡 traffic-only (GA/Vercel/Plausible pageviews) or installed-but-not-mounted · 🔴 nothing.

**You can see what users do, not guess** — could you reconstruct a user's journey and spot usage patterns?
- Signals: funnel end-to-end as named events (signup → activation → core/repeated action → conversion → retention), usage-pattern events, and *properties* on events for segmentation. Missing the conversion step is the most common, most expensive gap.
- 🟢 full funnel incl. conversion + usage patterns + segmentable, user-tied · 🟡 a few events but funnel holes / no properties / no identity · 🔴 pageviews only, or nothing.

**Headless backend?** Product analytics is end-user behavior — usually the consuming frontend's job. Mark this ⚪ N/A for a pure backend, and make sure its **system observability is scored in bucket 02**.

## Output format

Produce exactly this structure (fill in scores and findings; one bucket section
each, then the rollup, then the single top fix):

```markdown
# Production-Readiness Audit
_<repo or app name> · read-only inspection_

Your prototype is the dot in the middle. Production is everything around it —
here's where you stand.

**Legend:** 🟢 handled · 🟡 partial · 🔴 missing/at-risk · ⚪ not sure

## 01 · Infra · Security · Compliance — <🟢|🟡|🔴>
| Check | Score | Finding |
|---|:---:|---|
| Real database + auth | <emoji> | <evidence, cite a path> |
| User data isolation | <emoji> | <…> |
| API keys in env, not in repo | <emoji> | <…> |
| Secrets in .gitignore | <emoji> | <…> |
| Hosted on something you own (+ scale) | <emoji> | <…> |
| Compliance you actually need | <emoji> | <…> |

## 02 · Engineering best practices — <🟢|🟡|🔴>
| Check | Score | Finding |
|---|:---:|---|
| Errors handled, no silent failures | <emoji> | <…> |
| Logging + error tracking (observability) | <emoji> | <…> |
| AI tested beyond happy path | <emoji> | <…> |
| Guardrail on what the AI can do | <emoji> | <…> |
| Deploy + roll back safely (+ tests) | <emoji> | <…> |

## 03 · Design & UX — <🟢|🟡|🔴>
| Check | Score | Finding |
|---|:---:|---|
| Onboarding for a new user with no data | <emoji> | <…> |
| Real empty + error states | <emoji> | <…> |

## 04 · Product analytics — <🟢|🟡|🔴>
| Check | Score | Finding |
|---|:---:|---|
| Analytics wired in | <emoji> | <…> |
| You can see what users do, not guess | <emoji> | <…> |

## Scorecard
| Bucket | Status |
|---|:---:|
| 01 · Infra · Security · Compliance | <emoji> |
| 02 · Engineering best practices | <emoji> |
| 03 · Design & UX | <emoji> |
| 04 · Product analytics | <emoji> |

## 🔧 Top fix
**<the one fix>** — <why it matters / what it prevents>.
```

Keep findings concrete and short. If a bucket is mostly ⚪, say so plainly — an
honest "can't tell from the code" beats a confident wrong score.
