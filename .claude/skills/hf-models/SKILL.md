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

**Read `REFERENCE.md` before recommending a model.** It holds the routing table and the
last-verified prices. Prices rot — re-run `hf.sh models` rather than quoting the file
when the answer is a cost decision.

## Setup

Token: hf.co/settings/tokens/new -> fine-grained -> **"Make calls to Inference
Providers"**. A plain read token will not work.

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

## Commands

| Command | Does | Auth |
|---|---|:--:|
| `/hf models [substring]` | Warm models + live cheapest price, sorted by input cost | No |
| `/hf price <org/model>` | Every provider for one model, with status | No |
| `/hf route <task>` | Recommend a model from `REFERENCE.md` + a cost estimate | No |
| `/hf ask <model> <prompt>` | One call | Yes |
| `/hf compare <m1,m2,...> <prompt>` | Same prompt to N models in parallel | Yes |
| `/hf cost <model> <in-tok> <out-tok> <calls>` | Monthly cost math from live prices | No |

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

Claude Code speaks to the router directly. This replaces the model driving the whole
session — it is not per-task routing:

```bash
ANTHROPIC_BASE_URL="https://router.huggingface.co" \
ANTHROPIC_AUTH_TOKEN="$HF_TOKEN" \
ANTHROPIC_DEFAULT_OPUS_MODEL="zai-org/GLM-5.3" \
ANTHROPIC_DEFAULT_SONNET_MODEL="zai-org/GLM-5.3" \
ANTHROPIC_DEFAULT_HAIKU_MODEL="openai/gpt-oss-120b" \
CLAUDE_CODE_SUBAGENT_MODEL="openai/gpt-oss-120b" \
claude
```

Set it for one shell, never in a shell profile — a stray export silently downgrades
every future session. Worth it for bulk mechanical work in a throwaway session;
not worth it for real work: the harness is tuned for Claude, and tool-calling
reliability drops noticeably.

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
