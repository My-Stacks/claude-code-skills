# hf-models reference — model routing table

Prices are **USD per 1M tokens, cheapest live provider on the HF router**, verified
2026-08-30 via `scripts/hf.sh models`. They move — re-verify before quoting them
anywhere or before a cost decision. Never copy a price from this file into a doc
without re-running the command.

## The set worth knowing

| Model | In | Out | Ctx | Licence | Use it for |
|---|--:|--:|--:|---|---|
| `openai/gpt-oss-20b` | 0.03 | 0.14 | 131k | Apache 2.0 | Highest-volume trivial calls |
| `openai/gpt-oss-120b` | 0.037 | 0.17 | 131k | Apache 2.0 | Fast + cheap, but **reasoning inflates output ~3x** — see below |
| `deepseek-ai/DeepSeek-V4-Flash` | 0.09 | 0.18 | 1M | MIT | Cheap summarisation over long inputs |
| `zai-org/GLM-5.3-Flash` | 0.15 | 0.50 | 1M | open weights | Whole-site / whole-corpus reads |
| `Qwen/Qwen3-Coder-Next` | 0.20 | 1.50 | 262k | Apache 2.0 | Mechanical code work |
| `google/gemma-3-12b-it` | 0.05 | 0.15 | 131k | Gemma | **Cheapest vision+tools+schema.** Default for image->data |
| `Qwen/Qwen3.8-27B` | 0.40 | 3.00 | 262k | Apache 2.0 | Vision when gemma isn't good enough; also video |
| `moonshotai/Kimi-K2.7-Code` | 0.68 | 3.40 | 262k | custom | Coding agent, mid-tier |
| `deepseek-ai/DeepSeek-V4-Pro` | 1.30 | 2.60 | 1M | MIT | Repo-level code gen; cheapest output of the frontier tier |
| `zai-org/GLM-5.3` | 1.40 | 4.40 | 1M | open weights | Security review, long-horizon reasoning |
| `moonshotai/Kimi-K3` | 2.85 | 14.25 | 1M | custom | Best open agentic/tool use — and the priciest |

Benchmarks that separate the top four (Aug 2026, third-party aggregations — treat as
directional, not gospel):

| | GLM-5.3 | Kimi K3 | DeepSeek V4 Pro | Qwen3.8-Max |
|---|--:|--:|--:|--:|
| DeepSWE v1.1 | 66.9 | **67.5** | 62.7 | 56.6 |
| Terminal-Bench 2.1 | 88.2 | **88.3** | 87.9 | 86.6 |
| CyberGym (security) | **84.5** | 80.0 | 83.3 | 78.5 |
| Toolathlon (tools) | 73.0 | **76.5** | 74.1 | 72.5 |

They are within noise of each other on coding. Pick on **price, context, and licence**,
not on the leaderboard.

## Task -> model

| Task | Model | Why |
|---|---|---|
| Bulk tagging / classification / structured extraction | **Measure both** — `Qwen/Qwen3-4B-Instruct-2507` vs `openai/gpt-oss-120b` | The small non-reasoning model can be ~8x cheaper for schema filling; the big one is more accurate. Run `hf.sh compare` on real rows |
| Summaries, FAQ, blurbs at volume | `deepseek-ai/DeepSeek-V4-Flash-0731` | Cheapest 1M-context model, and the dated snapshot is *cheaper and faster* than the floating tag ($0.08 vs $0.09, 105 vs 84 tok/s) |
| Read an entire site / sitemap / corpus in one call | `zai-org/GLM-5.3-Flash` | 1M ctx at $0.15 in |
| Codemods, test scaffolding, mechanical refactors | `Qwen/Qwen3-Coder-Next` | $0.20/$1.50, Apache 2.0 |
| Screenshot / image -> structured data | `google/gemma-3-12b-it` | Cheapest model that does vision + tools + structured output, by 8x on input |
| Trivial classification at extreme volume | `Qwen/Qwen3-4B-Instruct-2507` | $0.01/$0.03 with tools + schema + 262k ctx |
| Anything a user waits on | `openai/gpt-oss-120b:cerebras` | 1147 tok/s, the fastest on the router — but pinning Cerebras costs **$0.35/$0.75**, ~9x DeepInfra's $0.037. Buy the latency deliberately |
| Second opinion on a security-shaped diff | `zai-org/GLM-5.3` | CyberGym leader |
| Second opinion on agent/tool-calling design | `moonshotai/Kimi-K3` | Toolathlon leader |
| Anything customer-visible, brand voice, or judgement | **Claude (Opus 5 / Fable 5)** | Do not route away |
| The driving agent in Claude Code on real work | **Claude** | See SKILL.md "Driving Claude Code" |

## Suffix rules

- No suffix -> `:fastest` (highest throughput, auto-failover). Good default.
- `:cheapest` -> lowest price per output token. **Use for every batch job.**
- `:preferred` -> your provider order from hf.co/settings/inference-providers.
- `:groq`, `:deepinfra`, `:together`, ... -> pin one provider. Use when you need stable
  latency or a known price, and accept losing failover.

The same model can differ ~9x by provider (GLM-5.3-Flash: $0.15 Together vs $1.40
Novita). Always check `hf.sh price <model>` before pinning.

## Two corrections the full catalogue forced

Both found by generating the catalogue rather than reasoning from model reputation:

- **`gpt-oss-120b` spans both ends of the router**: the fastest option anywhere on it
  (1147 tok/s, Cerebras) *and* among the cheapest ($0.037, DeepInfra) — but **those are
  different providers at ~9x different prices**, not one cheap-and-fast deal. Pick the
  end you need; you cannot have both at once.
- **Do not reach for a big multimodal model just because a task has images.**
  `gemma-3-12b-it` does vision + tools + structured output at $0.05/$0.15, versus
  $0.40/$3.00 for `Qwen3.8-27B` — 8x cheaper in, 20x out. Reach for Qwen only when
  gemma measurably fails the task, or you need video.

## Reasoning tokens break output-cost estimates

Measured 2026-08-30, same one-word-answer prompt:

| Model | Billed output tokens | Hidden reasoning |
|---|--:|--:|
| `openai/gpt-oss-120b` | 32-74 | **66-85%** |
| `Qwen/Qwen3-4B-Instruct-2507` | 2 | none |
| `google/gemma-3-12b-it` | 2 | none |

`gpt-oss-120b` is a reasoning model: it thinks in a `reasoning` field the OpenAI
response shape hides, and **bills every one of those tokens as output**. A headline
price of $0.17/M out behaves like ~$0.50/M on short structured replies.

This inverts a cheap-looking choice. For 100k cards at 800 in / 150 visible out:

- `gpt-oss-120b` with ~300 reasoning tokens: **~$10.60**
- `Qwen3-4B-Instruct-2507`, no reasoning: **~$1.25**

So for short structured output, a small non-reasoning model can be ~8x cheaper than
the "cheap" reasoning model. Reasoning earns its cost on hard judgement, not on
filling a JSON schema.

`hf.sh ask` prints `of which reasoning=N (X% of billed output)` when present, so
measure before you extrapolate. `HF_SHOW_REASONING=1` dumps the trace itself.

## Providers are not interchangeable

`hf.sh price` prints per-provider price, context, tool support, **structured-output
support**, time-to-first-token and throughput. Three traps it exposes, all verified
2026-08-30:

- **Structured output is not universal.** `DeepSeek-V4-Flash` supports JSON-schema
  output on DeepInfra but **not on Novita**. Anything parsing a schema must pin the
  provider, not trust `:cheapest`.
- **Throughput varies ~22x on identical weights.** `gpt-oss-120b`: DeepInfra $0.037 at
  51 tok/s, Groq $0.15 at 425 tok/s, Cerebras $0.35 at 1147 tok/s. `:cheapest` for
  offline batch, `:fastest`/`:groq` for anything a user waits on.
- **Context limits differ per provider for the same model.** A cheap provider may
  serve a 1M-context model at 64k. Check `CTX` before relying on a long-context plan.

A worked case — `GLM-5.3-Flash`, where **Together and Baseten are both $0.15/$0.50**,
but Together reports `supports_structured_output: false` and Baseten `true`. A
`:cheapest` call can land on either. Same model, same price, and one of them cannot
return your schema. Pin `:baseten`.

So: `:cheapest` for offline batch with no schema; pin a provider explicitly when you
need structured output, a latency budget, or the full context window.

Note `:cheapest` / `:fastest` / `:groq` are **routing policies the router consumes**,
not part of the model id. `hf.sh price` and `hf.sh cost` strip them and show every
provider, since the point of those commands is to compare what a policy would pick.

Only Groq and Cerebras serve the speed tier here, and only for gpt-oss:
`gpt-oss-120b:groq` ($0.15/$0.75), `gpt-oss-20b:groq` ($0.10/$0.50),
`gpt-oss-120b:cerebras` ($0.35/$0.75).

## Full catalogue

Generated from the live router — **regenerate rather than trusting the numbers**:

```bash
hf.sh table --write REFERENCE.md    # splices between the markers below
hf.sh table                          # or just print it
```

<!-- CATALOGUE:START -->
<!-- generated by scripts/table.py on 2026-08-30 — regenerate with `hf.sh table` -->

112 models on the router publish a price. Columns: **In/Out** = USD per 1M
tokens at the *cheapest* provider; **Ctx** = largest context any provider offers;
**Caps** = `V`ision / `T`ools / `S`tructured-output, and **`!` means at least one
provider lacks structured output** — pin a provider for schema work; **Fastest**
= best tok/s seen on any provider, which is usually *not* the cheapest one.

### Budget — under $0.10 in (31)

| Model | In | Out | Ctx | Caps | Cheapest on | Fastest |
|---|--:|--:|--:|:--:|---|--:|
| `prism-ml/Ternary-Bonsai-27B-gguf` | 0.000 | 0.00 | 262k | ·T·  | together | 60 |
| `prism-ml/Ternary-Bonsai-27B-AWQ-4bit` | 0.000 | 0.00 | 262k | VT·  | together | 79 |
| `Qwen/Qwen2.5-Coder-7B-Instruct` | 0.010 | 0.03 | 131k | ··S  | nscale | 147 |
| `Qwen/Qwen3-4B-Instruct-2507` | 0.010 | 0.03 | 262k | ·TS  | nscale | 66 |
| `Qwen/Qwen2.5-Coder-3B-Instruct` | 0.010 | 0.03 | 32k | ··S  | nscale | 165 |
| `Qwen/Qwen3-4B-Thinking-2507` | 0.010 | 0.03 | 262k | ·TS  | nscale | 158 |
| `meta-llama/Llama-3.1-8B-Instruct` | 0.020 | 0.05 | 131k | ·TS! | novita | 152 |
| `ibm-granite/granite-4.2-3b` | 0.030 | 0.12 | 131k | ·T·  | deepinfra | 238 |
| `openai/gpt-oss-20b` | 0.030 | 0.14 | 131k | ·TS  | deepinfra | 724 |
| `zai-org/AutoGLM-Phone-9B-Multilingual` | 0.035 | 0.14 | 65k | V··  | novita | 94 |
| `openai/gpt-oss-120b` | 0.037 | 0.17 | 131k | ·TS  | deepinfra | 1147 |
| `google/gemma-3-4b-it` | 0.050 | 0.10 | 131k | VTS  | deepinfra | 40 |
| `Sao10K/L3-8B-Stheno-v3.2` | 0.050 | 0.05 | 8k | ···  | novita | 90 |
| `google/gemma-3-12b-it` | 0.050 | 0.15 | 131k | VTS  | deepinfra | 100 |
| `deepseek-ai/DeepSeek-R1-Distill-Llama-8B` | 0.050 | 0.05 | 131k | ··S  | nscale | 145 |
| `Sao10K/L3-8B-Lunaris-v1` | 0.050 | 0.05 | 8k | ···  | novita | 75 |
| `inclusionAI/Ling-3.0-flash` | 0.060 | 0.18 | 262k | ·TS! | novita | 280 |
| `Qwen/Qwen2.5-Coder-32B-Instruct` | 0.060 | 0.20 | 131k | ··S  | nscale | 48 |
| `ibm-granite/granite-4.2-8b` | 0.060 | 0.25 | 131k | ·T·  | deepinfra | 154 |
| `zai-org/GLM-4.7-Flash` | 0.060 | 0.40 | 202k | ·T·  | deepinfra | 89 |
| `google/gemma-4-26B-A4B-it` | 0.070 | 0.34 | 262k | VTS! | deepinfra | 114 |
| `Qwen/Qwen3-8B` | 0.070 | 0.18 | 40k | ·T·  | nscale | 133 |
| `Qwen/Qwen3-14B` | 0.070 | 0.20 | 40k | ·TS! | nscale | 94 |
| `microsoft/phi-4` | 0.070 | 0.14 | 16k | ··S  | deepinfra | 79 |
| `deepseek-ai/DeepSeek-V4-Flash-0731` | 0.080 | 0.18 | 1048k | ·TS! | deepinfra | 83 |
| `Qwen/Qwen3-32B` | 0.080 | 0.25 | 40k | ·TS! | nscale | 41 |
| `google/gemma-3-27b-it` | 0.080 | 0.16 | 131k | VTS  | deepinfra | 13 |
| `deepseek-ai/DeepSeek-V4-Flash` | 0.090 | 0.18 | 1048k | ·TS! | deepinfra | 80 |
| `Qwen/Qwen3-Next-80B-A3B-Instruct` | 0.090 | 1.10 | 262k | ·TS! | deepinfra | 131 |
| `meta-llama/Llama-4-Scout-17B-16E-Instruct` | 0.090 | 0.29 | 890k | VTS! | nscale | 72 |
| `Qwen/Qwen3-235B-A22B-Instruct-2507` | 0.090 | 0.55 | 262k | ·TS  | deepinfra | 90 |

### Cheap — $0.10 to $0.50 in (50)

| Model | In | Out | Ctx | Caps | Cheapest on | Fastest |
|---|--:|--:|--:|:--:|---|--:|
| `Qwen/Qwen3.5-9B` | 0.100 | 0.15 | 262k | VTS  | deepinfra | 101 |
| `Qwen/Qwen3.6-35B-A3B` | 0.100 | 0.95 | 262k | VTS  | deepinfra | 136 |
| `stepfun-ai/Step-3.5-Flash` | 0.100 | 0.30 | 262k | ·T·  | deepinfra | 108 |
| `Qwen/Qwen3-30B-A3B` | 0.120 | 0.50 | 40k | ·TS  | deepinfra | 78 |
| `google/gemma-4-31B-it` | 0.130 | 0.38 | 262k | VTS! | deepinfra | 811 |
| `zai-org/GLM-4.5-Air` | 0.130 | 0.85 | 131k | ·T·  | novita | 80 |
| `meta-llama/Llama-3.3-70B-Instruct` | 0.135 | 0.40 | 131k | ·TS! | novita | 85 |
| `tencent/Hy3` | 0.140 | 0.58 | 262k | ·TS  | deepinfra | 56 |
| `Qwen/Qwen3.5-35B-A3B` | 0.140 | 1.00 | 262k | VTS! | deepinfra | 72 |
| `zai-org/GLM-5.3-Flash` | 0.150 | 0.50 | 1048k | ·TS! | together | 162 |
| `deepseek-ai/DeepSeek-R1-Distill-Qwen-7B` | 0.150 | 0.15 | 131k | ···  | nscale | 119 |
| `Qwen/Qwen3-VL-30B-A3B-Instruct` | 0.150 | 0.60 | 262k | VTS  | deepinfra | 116 |
| `ibm-granite/granite-4.2-30b` | 0.160 | 0.65 | 131k | ·T·  | deepinfra | 85 |
| `XiaomiMiMo/MiMo-V2.5` | 0.168 | 0.34 | 1048k | ·TS! | novita | 43 |
| `meta-llama/Llama-Guard-4-12B` | 0.180 | 0.18 | 163k | V··  | deepinfra | 10 |
| `Qwen/Qwen3-Coder-Next` | 0.200 | 1.50 | 262k | ·T·  | novita | 113 |
| `stepfun-ai/Step-3.7-Flash` | 0.200 | 1.15 | 262k | VT·  | deepinfra | 111 |
| `Qwen/Qwen3-235B-A22B` | 0.200 | 0.60 | 40k | ·T·  | nscale | 16 |
| `deepseek-ai/DeepSeek-R1-Distill-Qwen-14B` | 0.200 | 0.20 | 131k | ··S  | nscale | 92 |
| `aisingapore/Gemma-SEA-LION-v4-27B-IT` | 0.200 | 0.40 | - | ··S  | publicai | 52 |
| `Qwen/Qwen3-VL-235B-A22B-Instruct` | 0.200 | 0.88 | 262k | VTS  | deepinfra | 51 |
| `Qwen/Qwen3-Coder-30B-A3B-Instruct` | 0.228 | 0.91 | - | ·TS  | scaleway | 123 |
| `Qwen/Qwen3-235B-A22B-Thinking-2507` | 0.230 | 2.30 | 262k | ·TS! | deepinfra | 71 |
| `deepseek-ai/DeepSeek-V3-0324` | 0.240 | 0.90 | 163k | ·TS! | deepinfra | 29 |
| `aisingapore/Qwen-SEA-LION-v4-32B-IT` | 0.250 | 0.50 | - | ·TS  | publicai | 46 |
| `deepseek-ai/DeepSeek-V3.1` | 0.250 | 0.95 | 163k | ·TS  | deepinfra | 31 |
| `MiniMaxAI/MiniMax-M2.7` | 0.250 | 1.00 | 204k | ·T·  | deepinfra | 54 |
| `Qwen/Qwen3.5-27B` | 0.260 | 2.60 | 262k | VTS! | deepinfra | 80 |
| `deepseek-ai/DeepSeek-V3.2` | 0.260 | 0.38 | 163k | ·TS  | deepinfra | 30 |
| `deepseek-ai/DeepSeek-V3.2-Exp` | 0.270 | 0.41 | 163k | ·TS  | novita | 32 |
| `meta-llama/Llama-4-Maverick-17B-128E-Instruct-FP8` | 0.270 | 0.85 | 1048k | V·S  | novita | 34 |
| `deepseek-ai/DeepSeek-V3.1-Terminus` | 0.270 | 0.95 | 163k | ·TS  | deepinfra | 33 |
| `MiniMaxAI/MiniMax-M3` | 0.280 | 1.10 | 1000k | VTS! | deepinfra | 94 |
| `Qwen/Qwen3.5-122B-A10B` | 0.290 | 2.40 | 262k | VT·  | deepinfra | 100 |
| `meta-models/Muse-Glimmer-30B` | 0.300 | 1.20 | 131k | VTS  | deepinfra | 106 |
| `MiniMaxAI/MiniMax-M2.5` | 0.300 | 1.20 | 204k | ·T·  | novita | 59 |
| `zai-org/GLM-4.6V-Flash` | 0.300 | 0.90 | 131k | VT·  | novita | 50 |
| `MiniMaxAI/MiniMax-M2` | 0.300 | 1.20 | 204k | ·T·  | novita | 61 |
| `MiniMaxAI/MiniMax-M2.1` | 0.300 | 1.20 | 204k | ·T·  | novita | 56 |
| `Qwen/Qwen3.6-27B` | 0.320 | 3.20 | 262k | VTS  | deepinfra | 70 |
| `deepseek-ai/DeepSeek-V3` | 0.320 | 0.89 | 163k | ·TS! | deepinfra | 36 |
| `Qwen/Qwen2.5-72B-Instruct` | 0.360 | 0.40 | 32k | ·TS! | deepinfra | 27 |
| `Qwen/Qwen3-Coder-480B-A35B-Instruct` | 0.380 | 1.55 | 262k | ·T·  | novita | 58 |
| `Qwen/Qwen3.8-27B` | 0.400 | 3.00 | 262k | VTS  | deepinfra | 47 |
| `zai-org/GLM-4.7` | 0.400 | 1.75 | 204k | ·TS! | deepinfra | 146 |
| `speakleash/Bielik-11B-v3.0-Instruct` | 0.400 | 0.40 | - | ·TS  | publicai | 35 |
| `baidu/ERNIE-4.5-VL-424B-A47B-Base-PT` | 0.420 | 1.25 | 123k | V··  | novita | 41 |
| `thinkingmachines/Inkling-Small` | 0.450 | 1.20 | 1048k | VTS! | deepinfra | 230 |
| `Qwen/Qwen3.5-397B-A17B` | 0.450 | 3.00 | 262k | VTS! | deepinfra | 122 |
| `moonshotai/Kimi-K2.5` | 0.450 | 2.25 | 262k | VTS! | deepinfra | 48 |

### Mid — $0.50 to $1.50 in (29)

| Model | In | Out | Ctx | Caps | Cheapest on | Fastest |
|---|--:|--:|--:|:--:|---|--:|
| `deepseek-ai/DeepSeek-R1-0528` | 0.500 | 2.15 | 163k | ·TS! | deepinfra | 24 |
| `zai-org/GLM-4.6` | 0.500 | 2.00 | 204k | ·TS! | deepinfra | 43 |
| `XiaomiMiMo/MiMo-V2.5-Pro` | 0.522 | 1.04 | 1048k | ·TS! | novita | 32 |
| `zai-org/GLM-4-32B-0414` | 0.550 | 1.66 | 32k | ···  | novita | 34 |
| `MiniMaxAI/MiniMax-M1-80k` | 0.550 | 2.20 | 1000k | ·T·  | novita | 63 |
| `moonshotai/Kimi-K2-Instruct` | 0.570 | 2.30 | 131k | ·T·  | novita | 38 |
| `nvidia/NVIDIA-Nemotron-3-Ultra-550B-A55B-NVFP4` | 0.600 | 2.40 | 262k | ·TS  | fireworks-ai | 111 |
| `zai-org/GLM-5` | 0.600 | 2.08 | 202k | ·TS! | deepinfra | 68 |
| `zai-org/GLM-4.5V` | 0.600 | 1.80 | 65k | VT·  | novita | 82 |
| `moonshotai/Kimi-K2-Instruct-0905` | 0.600 | 2.50 | 262k | ·TS  | novita | 38 |
| `alpindale/WizardLM-2-8x22B` | 0.620 | 0.62 | 65k | ···  | novita | 24 |
| `moonshotai/Kimi-K2.7-Code` | 0.680 | 3.40 | 262k | VTS! | deepinfra | 135 |
| `deepseek-ai/DeepSeek-R1` | 0.700 | 2.50 | 64k | ·TS  | novita | 23 |
| `NousResearch/Hermes-3-Llama-3.1-70B` | 0.700 | 0.70 | 131k | ··S  | deepinfra | 35 |
| `zai-org/GLM-5.2` | 0.750 | 2.40 | 1048k | ·TS! | deepinfra | 109 |
| `moonshotai/Kimi-K2.6` | 0.750 | 3.50 | 262k | VTS  | deepinfra | 109 |
| `deepseek-ai/DeepSeek-R1-Distill-Llama-70B` | 0.800 | 0.80 | 8k | ···  | novita | 15 |
| `swiss-ai/Apertus-v1.5-8B` | 0.820 | 2.92 | - | VT·  | publicai | 65 |
| `swiss-ai/Apertus-8B-Instruct-2509` | 0.820 | 2.92 | - | ·TS  | publicai | 66 |
| `swiss-ai/Apertus-70B-Instruct-2509` | 0.820 | 2.92 | - | ·TS  | publicai | 65 |
| `swiss-ai/Apertus-v1.5-70B` | 0.820 | 2.92 | - | VTS  | publicai | 68 |
| `thinkingmachines/Inkling` | 0.950 | 4.05 | 1048k | VTS! | deepinfra | 158 |
| `Qwen/Qwen3-VL-235B-A22B-Thinking` | 0.980 | 3.95 | 131k | VT·  | novita | 59 |
| `nvidia/NVIDIA-Nemotron-3-Ultra-550B-A55B-BF16` | 1.000 | 5.00 | 262k | ·TS  | deepinfra | 26 |
| `Qwen/Qwen2.5-VL-72B-Instruct` | 1.010 | 1.01 | 32k | V·S  | ovhcloud | 35 |
| `zai-org/GLM-5.1` | 1.050 | 3.50 | 202k | ·TS  | deepinfra | 27 |
| `deepseek-ai/DeepSeek-V4-Pro-0813` | 1.300 | 2.60 | 1048k | ·TS! | deepinfra | 107 |
| `deepseek-ai/DeepSeek-V4-Pro` | 1.300 | 2.60 | 1048k | ·TS! | deepinfra | 107 |
| `zai-org/GLM-5.3` | 1.400 | 4.40 | 1048k | ·TS! | together | 160 |

### Frontier — over $1.50 in (2)

| Model | In | Out | Ctx | Caps | Cheapest on | Fastest |
|---|--:|--:|--:|:--:|---|--:|
| `Qwen/Qwen3.8-2.4T-A95B` | 2.000 | 6.00 | 1010k | ·TS! | deepinfra | 119 |
| `moonshotai/Kimi-K3` | 2.850 | 14.25 | 1048k | VTS! | deepinfra | 87 |

**36 of 112 accept images.** **2 are currently $0 in** (promos — never depend on one).
<!-- CATALOGUE:END -->
