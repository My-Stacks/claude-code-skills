# AI Router Reference

Load this file on demand. Not needed for route, config, or setup commands.

## Model Catalog

### Claude Code Models (internal switching via `/model`)

| Model | Best for | Context | Speed |
|-------|----------|---------|-------|
| Opus 4.6 | Architecture, planning, complex reasoning, long documents | 1M | Slowest |
| Sonnet 4.6 | Code generation, refactoring, debugging, general tasks | 200K | Fast |
| Haiku 4.5 | Quick lookups, formatting, simple edits, triage | 200K | Fastest |

### External API Models

| Provider | Default Model | Strengths | Context |
|----------|--------------|-----------|---------|
| Anthropic | claude-sonnet-4-6 | Structured output, instruction following, code | 200K |
| OpenAI | gpt-5.4 | Broad knowledge, creative writing, multimodal, reasoning | 1M |
| Gemini | gemini-3-flash-preview | Speed, long context, multimodal, cost efficiency | 1M |

### Model Override

To use a non-default model for a single call, the user can specify it:
> `/ai-router ask --model claude-opus-4-6 "deep architecture question"`

Parse `--model <value>` from the prompt. Substitute into the API call template, overriding the config default.

For Anthropic models: substitute in the `model` field.
For OpenAI models: substitute in the `model` field.
For Gemini models: substitute in the URL path.

## PR Review Rubric

When constructing review prompts, instruct each model to evaluate:

1. **Correctness** — Logic errors, off-by-one, null handling, race conditions
2. **Security** — Injection, auth bypass, secrets exposure, OWASP top 10
3. **Performance** — N+1 queries, unnecessary allocations, missing indexes
4. **Maintainability** — Naming, complexity, dead code, missing error handling
5. **Tests** — Coverage gaps, flaky patterns, missing edge cases

Ask models to reference specific lines/hunks and categorize severity (critical/suggestion/nit).

## Troubleshooting

### "command not found: jq"
Install jq: `brew install jq` (macOS) or `apt-get install jq` (Linux).

### "command not found: curl"
Curl is pre-installed on macOS and most Linux. If missing: `apt-get install curl`.

### API key validation fails with 401
Key is invalid or revoked. Regenerate from the provider's dashboard:
- Anthropic: https://console.anthropic.com/settings/keys
- OpenAI: https://platform.openai.com/api-keys
- Gemini: https://aistudio.google.com/app/apikey

### API call returns 429 (rate limited)
Wait and retry. For ensemble calls, the other providers still return results.

### API call returns 400 (bad request)
Usually a prompt encoding issue. Check that `jq` is escaping the prompt correctly. Common cause: unescaped quotes or control characters in the prompt.

### Config file permissions
The config contains API keys. Ensure it's not world-readable:
```bash
chmod 600 ~/.orchestrator-config.json
```

### Large diffs in review
If the diff exceeds ~100K characters, it may hit API context limits. Truncate to the most recent N files or ask the user to scope the review.

## Pricing Reference (per 1M tokens)

| Provider | Model | Input | Output |
|----------|-------|------:|-------:|
| Anthropic | claude-sonnet-4-6 | $3.00 | $15.00 |
| Anthropic | claude-opus-4-6 | $5.00 | $25.00 |
| Anthropic | claude-haiku-4-5 | $1.00 | $5.00 |
| OpenAI | gpt-5.4 | $2.50 | $15.00 |
| Gemini | gemini-3-flash-preview | $0.50 | $3.00 |

### Typical Cost Per Command

| Command | Calls | Est. cost (short prompt) | Est. cost (PR review ~5K lines) |
|---------|------:|-------------------------:|--------------------------------:|
| ask | 1 | ~$0.005 | ~$0.05 |
| ensemble | 3 | ~$0.012 | ~$0.12 |
| compare | 3 | ~$0.012 | ~$0.12 |
| review | 3 | ~$0.05 | ~$0.15 |
| route/config/setup | 0 | $0 | — |

When the prompt is large (e.g., PR diffs), note the approximate token count so the user can decide whether to proceed.
