---
name: hf-models
version: "1.0"
description: "Switch between open-weight models (Qwen, Kimi, DeepSeek, GLM, gpt-oss) through the Hugging Face Inference Providers router. Live pricing lookup, single calls, side-by-side comparison, and a task-to-model routing table. Use when picking a model for a job, cost-checking an LLM feature, getting a non-Claude second opinion, or wiring an open model into a Stacklist service."
trigger: /hf
---

# hf-models

One OpenAI-compatible endpoint (`https://router.huggingface.co/v1`) fronting every
major open-weight model. Switching models is changing one string.

Requires `curl` and `python3`. All network calls go through `scripts/hf.sh` so a
single `permissions.allow` rule covers the skill.

**Read `REFERENCE.md` before recommending a model.** It holds the curated routing
table plus a generated catalogue of every priced model on the router. The catalogue
is regenerated with `hf.sh table --write REFERENCE.md`, so when prices look stale,
**refresh it rather than trusting it** — and for an actual cost decision, run
`hf.sh cost`, which always reads live.

## Setup

Token: hf.co/settings/tokens/new -> type **Fine-grained** -> name it anything
(it's just a label, e.g. `stacklist-hf-models`) -> click the **Inference** preset.
The preset is what grants "Make calls to Inference Providers" — the permission is a
scope, not the token's name, and *Create token* stays disabled until a scope is
picked. A plain Read token will not work. The value is shown once; copy it then.

```bash
scripts/hf.sh setup hf_xxxxx     # validates against whoami-v2, writes ~/.hf-router.json (0600)
```

`HF_TOKEN` in the environment takes precedence over the config file.

## Billing

No paid tier is required to call the router — but the free allowance is a rounding
error, so any real use means putting a card on the account.

| Account | Monthly credits | Spendable on |
|---|--:|---|
| Free | **$0.10** | Inference Providers only |
| PRO ($9/mo) | **$2.00** | Inference Providers, Endpoints, Spaces GPU, Jobs |
| Team / Enterprise | **$2.00 per seat**, pooled | same as PRO |

**Two different things are both called "credits" on the billing page**, and they
behave differently:

- **Included credits** — the monthly allowance in the table above. Recurring, and
  tied to the billing period shown as *"Ends on <1st of next month>"*. Use them or
  lose them; they refresh on the 1st.
- **Purchased credits** — a prepaid balance from *Add Credits*, on its own line. The
  *"Ends on"* date governs the period counters (`Current period usage`, the free
  allowance), **not** this balance. HF's billing docs describe only included credits
  as "credited every month" and say nothing about purchased credits expiring — but
  they don't explicitly guarantee rollover either. If a balance is large enough to
  matter, confirm with billing@huggingface.co rather than inferring it.

Leave **Automatic Recharge off** while piloting. The prepaid balance is then a hard
ceiling on any runaway job; auto-recharge removes exactly that protection.

Credits apply automatically to routed requests, before any pay-as-you-go usage.
Past them you buy credits and continue — **free accounts must purchase credits before
pay-as-you-go works at all**, so a job that outruns $0.10 mid-run stops rather than
overflowing.

Two things that follow from this:

- **HF adds no markup.** You pay the provider's rate. So the router is a routing and
  billing convenience, not a tax — there is no cost reason to go direct.
- **A Custom Provider Key (your own Groq/Together key set in HF settings) bills you
  at the provider and forfeits HF credits.** Use it only when you already have volume
  committed with that provider; otherwise stay routed.

For team-wide use, bill an org rather than a personal account — each member keeps
their own token, spend is pooled and visible on the org billing page, and admins can
set a spending limit and disable providers:

```ts
extra_headers: { "X-HF-Bill-To": "<org-name>" }   // or headers: {...} in JS
```

Costs per model and provider: hf.co/settings/inference-providers/overview.

**There is no public API for remaining balance.** Spend is visible on the billing
page and the Inference Providers overview only, so budget control has to be
*preventative*, not reactive:

1. `hf.sh cost <model> <in> <out> <calls>` **before** any batch. It prices the whole
   run against every provider and flags inputs that overflow a provider's context.
2. Cap the blast radius at the org: Team/Enterprise admins can set a spending limit
   and disable providers. Do this before a service calls the router in production.
3. A free account is its own circuit breaker — pay-as-you-go needs a credit purchase
   first, so an unfunded run stops at $0.10 instead of overflowing. Useful for a
   first pilot; useless once funded, so add the org limit before you fund it.
4. Bill runs to the org (`X-HF-Bill-To`) so spend is attributable per model and
   provider, rather than pooled invisibly on a personal account.

## Commands

| Command | Does | Auth |
|---|---|:--:|
| `/hf models [substring]` | Warm models + live cheapest price, sorted by input cost | No |
| `/hf price <org/model>` | Every provider for one model, with status | No |
| `/hf route <task>` | Recommend a model from `REFERENCE.md` + a cost estimate | No |
| `/hf ask <model> <prompt>` | One call | Yes |
| `/hf compare <m1,m2,...> <prompt>` | Same prompt to N models in parallel | Yes |
| `/hf cost <model> <in-tok> <out-tok> <calls>` | Total cost across every provider, from live prices | No |
| `/hf table [--write]` | Regenerate the full 112-model catalogue in `REFERENCE.md` | No |
| `/hf pick [filter]` | Interactive chooser; prints the chosen model id | No |
| `/hf claude [model]` | Launch a new session driven by an open model | No |

Under the hood:

```bash
scripts/hf.sh models kimi
scripts/hf.sh price zai-org/GLM-5.3-Flash
printf '%s' "$PROMPT" > "$D/p.txt" && scripts/hf.sh ask 'openai/gpt-oss-120b:cheapest' "$D/p.txt"
scripts/hf.sh compare 'zai-org/GLM-5.3,moonshotai/Kimi-K3' "$D/p.txt"
```

Write the prompt to a file in the scratchpad and pass the path — never interpolate a
prompt into argv (quoting, length, and it leaks into process listings).

Env knobs: `HF_SYSTEM` (system prompt), `HF_MAX_TOKENS` (4096), `HF_TIMEOUT` (600).

## Rules

1. **Verify the model id before using it.** Model names in the wild are frequently
   wrong or hallucinated. `hf.sh models <substring>` is the authority — if the id
   isn't in that output, it is not callable. Never invent a version number.
2. **Never quote a price from memory.** Run `hf.sh price`. Same model, different
   provider, up to 9x apart.
3. **`:cheapest` on every batch job.** Default `:fastest` optimises throughput, not
   cost, and can pick a provider 9x the price for identical weights.
4. **Check `supports_tools`** in `hf.sh price` output before routing anything that
   needs function calling.
5. **Don't route judgement away from Claude.** Customer-visible copy, brand voice,
   Surfaces slot-filling, architectural calls, anything writing to prod — stays on
   Opus 5 / Fable 5. Open models are for volume, cost, and diversity of opinion.
6. Report failures as failures. If a provider 5xxs or the model is cold, say so;
   don't silently fall back to a different model and present the answer as the one
   that was asked for.

## `/hf route <task>`

No API call. Match the task against the "Task -> model" table in `REFERENCE.md`, then:

1. Name one primary model and one fallback, with the reason (price / context /
   licence / benchmark), not just the name.
2. Run `hf.sh price` on the primary to confirm it's live and get the real number.
3. If volume is known, give the monthly cost against the current Claude cost.
4. If the task belongs on Claude (rule 5), say so and stop.

## Driving Claude Code with an open model

**There is no in-session switch.** `ANTHROPIC_BASE_URL` and auth are bound when the
process starts, so pointing at a different endpoint means a new process. `/model`
and `--model` pick *which* Anthropic model to talk to; they cannot change *where*
requests go.

One command, no files touched, token read from the config:

```bash
hf.sh claude                                   # DeepSeek V4 Pro (default)
hf.sh claude zai-org/GLM-5.3                   # any router model
hf.sh claude --pick                            # choose from a menu
hf.sh claude --pick qwen                       # menu, filtered
hf.sh claude moonshotai/Kimi-K3 --sub openai/gpt-oss-120b
hf.sh claude <model> --dry-run                 # show what it would launch
```

**To come back: exit that session** (`/exit` or Ctrl+D). Nothing was written, so
there is nothing to undo.

`hf.sh pick` also works standalone and prints the id to stdout, so it composes:

```bash
M=$(hf.sh pick qwen) && hf.sh cost "$M" 800 150 100000
```

With no filter it shows a curated shortlist with a note on what each is for; with a
filter it shows every match, cheapest first. The menu goes to stderr so `$(...)`
captures only the id.

`--sub` sets the model for subagents and the Haiku tier — keep that cheap. Exit the
launched session to return to Claude; nothing persists.

Prefer this over editing settings: no second plaintext copy of the token on disk, and
nothing to remember to undo. Use a project's `.claude/settings.local.json` `env` block
only when a whole repo should *always* run on an open model — and check that file is
gitignored by the repo itself, not just by your global gitignore, before putting a
token in it.

Worth it for bulk mechanical work in a throwaway session. Not worth it for real work:
the launched session is not Claude, and tool-calling reliability drops noticeably.
For a second opinion, `ask` / `compare` from a normal session is strictly better —
you keep the context.

## Wiring into a Stacklist service

`stacklist-mcp` and `stacklist-agents` already depend on the `openai` SDK, so the
router is a base-URL swap with no new dependency:

```ts
const hf = new OpenAI({
  baseURL: "https://router.huggingface.co/v1",
  apiKey: process.env.HF_TOKEN,
});
// model: "openai/gpt-oss-120b:cheapest"
```

Keep the Anthropic client alongside it and route per task — one client per provider,
picked at the call site. Do not rip out the Claude path.
