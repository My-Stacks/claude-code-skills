# hf-models reference — model routing table

Prices are **USD per 1M tokens, cheapest live provider on the HF router**, verified
2026-08-30 via `scripts/hf.sh models`. They move — re-verify before quoting them
anywhere or before a cost decision. Never copy a price from this file into a doc
without re-running the command.

## The set worth knowing

| Model | In | Out | Ctx | Licence | Use it for |
|---|--:|--:|--:|---|---|
| `openai/gpt-oss-20b` | 0.03 | 0.14 | 131k | Apache 2.0 | Highest-volume trivial calls |
| `openai/gpt-oss-120b` | 0.037 | 0.17 | 131k | Apache 2.0 | **Default workhorse.** Classification, tagging, extraction |
| `deepseek-ai/DeepSeek-V4-Flash` | 0.09 | 0.18 | 1M | MIT | Cheap summarisation over long inputs |
| `zai-org/GLM-5.3-Flash` | 0.15 | 0.50 | 1M | open weights | Whole-site / whole-corpus reads |
| `Qwen/Qwen3-Coder-Next` | 0.20 | 1.50 | 262k | Apache 2.0 | Mechanical code work |
| `Qwen/Qwen3.8-27B` | 0.40 | 3.00 | 262k | Apache 2.0 | Vision: screenshots, OG images, video |
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
| Bulk tagging / classification / structured extraction | `openai/gpt-oss-120b:groq` | ~$0.15/$0.75 on Groq for speed, $0.037/$0.17 on DeepInfra for cost |
| Summaries, FAQ, blurbs at volume | `deepseek-ai/DeepSeek-V4-Flash` | Cheapest competent summariser; 1M ctx swallows a full scrape |
| Read an entire site / sitemap / corpus in one call | `zai-org/GLM-5.3-Flash` | 1M ctx at $0.15 in |
| Codemods, test scaffolding, mechanical refactors | `Qwen/Qwen3-Coder-Next` | $0.20/$1.50, Apache 2.0 |
| Screenshot / image -> structured data | `Qwen/Qwen3.8-27B` | Text+image+video, Apache 2.0 |
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

So: `:cheapest` for offline batch with no schema; pin a provider explicitly when you
need structured output, a latency budget, or the full context window.

Only Groq and Cerebras serve the speed tier here, and only for gpt-oss:
`gpt-oss-120b:groq` ($0.15/$0.75), `gpt-oss-20b:groq` ($0.10/$0.50),
`gpt-oss-120b:cerebras` ($0.35/$0.75).
