---
name: ai-router
version: "1.0"
description: "Route tasks to optimal model tiers and ensemble responses across Claude, GPT, and Gemini APIs."
trigger: /ai-router
---

## Version Check
To check for updates: `curl -s https://raw.githubusercontent.com/My-Stacks/claude-code-skills/refs/heads/main/versions.yaml`
Compare against this file's version in frontmatter.

# AI Router Skill

Route tasks to the best Claude Code model tier, and optionally call external model APIs (Anthropic, OpenAI, Gemini) for ensemble responses. Curl-based — no runtime dependencies beyond `curl` and `jq`.

## Config

File: `~/.orchestrator-config.json`

```json
{
  "anthropic_api_key": "sk-ant-...",
  "openai_api_key": "sk-...",
  "gemini_api_key": "AIza...",
  "default_anthropic_model": "claude-sonnet-4-6",
  "default_openai_model": "gpt-5.4",
  "default_gemini_model": "gemini-3-flash-preview"
}
```

All keys optional. At least one required for API commands.

## First Run Setup

On first invocation, check for `~/.orchestrator-config.json`.

If missing, run setup:

1. Prompt for each API key (Enter to skip):
   > "Anthropic API key (sk-ant-...): "
   > "OpenAI API key (sk-...): "
   > "Gemini API key (AIza...): "
2. Require at least one key. If all skipped: "At least one API key is required."
3. Validate each provided key with a minimal API call (see Validation section below).
4. Write config with provided keys + default models.
5. Confirm: "ai-router configured. [N] provider(s) active: [list]."

### Key Validation

**Anthropic:**
```bash
curl -s -o /dev/null -w "%{http_code}" https://api.anthropic.com/v1/messages \
  -H "x-api-key: $KEY" -H "anthropic-version: 2023-06-01" -H "content-type: application/json" \
  -d '{"model":"claude-haiku-4-5-20251001","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}'
```

**OpenAI:**
```bash
curl -s -o /dev/null -w "%{http_code}" https://api.openai.com/v1/chat/completions \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"model":"gpt-5.4","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}'
```

**Gemini:**
```bash
curl -s -o /dev/null -w "%{http_code}" \
  "https://generativelanguage.googleapis.com/v1beta/models/gemini-3-flash-preview:generateContent?key=$KEY" \
  -H "Content-Type: application/json" -d '{"contents":[{"parts":[{"text":"hi"}]}]}'
```

200 = valid. Anything else = warn and skip: "Anthropic key invalid (HTTP [code]). Skipping."

## Commands

| Command | What it does | API calls? |
|---------|-------------|:---:|
| `/ai-router` | First-run setup or command menu | No |
| `/ai-router setup` | Configure/reconfigure API keys | No |
| `/ai-router route <task>` | Suggest best model tier | No |
| `/ai-router ask <prompt>` | Send to one external model | Yes |
| `/ai-router ensemble <prompt>` | Send to all configured models, synthesize | Yes |
| `/ai-router review <context>` | Ensemble PR review | Yes |
| `/ai-router compare <prompt>` | Side-by-side without synthesis | Yes |
| `/ai-router config` | Show current config (redacted keys) | No |

### `/ai-router` and `/ai-router help`

After setup, show the command menu:

> **AI Router** ([N] providers active: [list])
>
> `/ai-router route <task>` — suggest best model for a task
> `/ai-router ask <prompt>` — send to one external model
> `/ai-router ensemble <prompt>` — multi-model synthesis
> `/ai-router review` — ensemble PR review
> `/ai-router compare <prompt>` — side-by-side responses
> `/ai-router config` — show config
> `/ai-router setup` — reconfigure keys

---

## `/ai-router route <task>`

Analyze the task description and recommend model tiers using this matrix:

| Signal words | CC Model | External | Reason |
|-------------|----------|----------|--------|
| plan, architect, design, strategy, system design | Opus | Claude API (Opus) | Deep reasoning, long coherence |
| code, implement, refactor, debug, fix, build | Sonnet | — | Best cost/quality for coding |
| format, rename, lookup, quick question, typo, lint | Haiku | — | Fast and cheap |
| review, audit, security, vulnerability | Sonnet | Ensemble (all) | Multiple perspectives catch more |
| brainstorm, explore, compare options, tradeoffs | Sonnet | Ensemble (all) | Diversity of thought |

**Output format:**

```
## Route: [task summary]

**Claude Code:** Switch to [Model] -> run `/model [model-name]`
**External:** [None | Single provider | Ensemble recommended]
**Why:** [one line reasoning]
```

If the current CC model already matches the recommendation, say so: "Already on [Model] — good fit for this task."

---

## `/ai-router ask <prompt>`

Send a prompt to a single external model.

1. Read config. If only one provider configured, use it. If multiple, ask: "Which provider? (anthropic/openai/gemini)" — or auto-route using the routing matrix.
2. Call the API (see API Call Templates below).
3. Display the response with provider attribution.

**Output format:**

```
## [Provider] ([model])

[response content]
```

---

## `/ai-router ensemble <prompt>`

Send to all configured providers in parallel, then synthesize.

1. Read config. Identify active providers.
2. If only one provider: fall back to `/ai-router ask` behavior.
3. Run all API calls in parallel using separate Bash tool calls.
4. Synthesize using the Ensemble Synthesis format.

### Ensemble Synthesis Format

```markdown
## Ensemble: [topic]

### Consensus
[Points all models agree on — highest confidence]

### Unique Insights
- **Claude:** [what only Claude caught]
- **GPT:** [what only GPT caught]
- **Gemini:** [what only Gemini caught]

### Conflicts
[Where models disagree, with reasoning from each]

### Recommendation
[Synthesized best answer]
```

Omit sections with no content. If a provider failed, note it: "Gemini: unavailable (HTTP 429)."

---

## `/ai-router review`

Ensemble PR review. Gathers diff context, sends to all configured models, synthesizes.

1. Get the diff to review:
   - If user provides a PR number: `gh pr diff <number>`
   - Otherwise: `git diff HEAD~1` or staged changes
2. Construct a review prompt: "Review this code diff for bugs, security issues, performance problems, and style. Be specific with line references."
3. Prepend the diff to the prompt.
4. Send to all configured providers in parallel.
5. Synthesize using the PR Review Synthesis format.

### PR Review Synthesis Format

```markdown
## Ensemble PR Review

### Critical Issues (flagged by 2+ models)
[Highest priority — issues multiple models independently caught]

### Suggestions
[Deduplicated improvements from any model]

### Model-Specific Catches
[Issues found by only one model — lower confidence, worth checking]

### Summary
[Overall assessment]
```

---

## `/ai-router compare <prompt>`

Side-by-side responses without synthesis.

1. Send to all configured providers in parallel.
2. Display each response under its own heading. No synthesis.

**Output format:**

```markdown
## Compare: [topic]

### Claude ([model])
[response]

### GPT ([model])
[response]

### Gemini ([model])
[response]
```

---

## `/ai-router config`

Show current configuration with redacted keys.

```
## AI Router Config

| Provider | Key | Model | Status |
|----------|-----|-------|--------|
| Anthropic | sk-ant-...XY12 | claude-sonnet-4-6 | Active |
| OpenAI | sk-...Ab34 | gpt-5.4 | Active |
| Gemini | — | — | Not configured |

Config: ~/.orchestrator-config.json
```

Redact keys to first 6 + last 4 characters. Show "Not configured" for missing providers.

---

## `/ai-router setup`

Re-run the first-run setup flow. Overwrites existing config.

---

## API Call Templates

Read keys and models from `~/.orchestrator-config.json` using jq. Substitute into these templates.

### Anthropic

```bash
RESPONSE=$(curl -s https://api.anthropic.com/v1/messages \
  -H "x-api-key: $(jq -r '.anthropic_api_key' ~/.orchestrator-config.json)" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d "{
    \"model\": \"$(jq -r '.default_anthropic_model' ~/.orchestrator-config.json)\",
    \"max_tokens\": 4096,
    \"messages\": [{\"role\": \"user\", \"content\": $(echo "$PROMPT" | jq -Rs .)}]
  }")
echo "$RESPONSE" | jq -r '.content[0].text'
```

### OpenAI

```bash
RESPONSE=$(curl -s https://api.openai.com/v1/chat/completions \
  -H "Authorization: Bearer $(jq -r '.openai_api_key' ~/.orchestrator-config.json)" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"$(jq -r '.default_openai_model' ~/.orchestrator-config.json)\",
    \"max_tokens\": 4096,
    \"messages\": [{\"role\": \"user\", \"content\": $(echo "$PROMPT" | jq -Rs .)}]
  }")
echo "$RESPONSE" | jq -r '.choices[0].message.content'
```

### Gemini

```bash
MODEL=$(jq -r '.default_gemini_model' ~/.orchestrator-config.json)
KEY=$(jq -r '.gemini_api_key' ~/.orchestrator-config.json)
RESPONSE=$(curl -s "https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${KEY}" \
  -H "Content-Type: application/json" \
  -d "{
    \"contents\": [{\"parts\": [{\"text\": $(echo "$PROMPT" | jq -Rs .)}]}]
  }")
echo "$RESPONSE" | jq -r '.candidates[0].content.parts[0].text'
```

### Error Handling

For each API call:
1. Check HTTP status. If not 200, capture the error.
2. If a provider fails during ensemble, continue with remaining providers.
3. Note failures in the synthesis: "[Provider]: unavailable ([error])."
4. If all providers fail, report the errors — do not synthesize from nothing.

### Parallel Execution

For ensemble and compare commands, run all API calls as separate Bash tool calls in a single response. This executes them in parallel. Collect results, then synthesize.

### Prompt Construction

When building the prompt string for API calls:
- Use `jq -Rs .` to safely escape the prompt for JSON embedding.
- For review commands, prepend the diff to the prompt.
- Keep system context minimal — the prompt should stand alone.

---

## Cost Tracking

After every API call, extract token usage from the response and calculate cost.

### Extracting Usage

**Anthropic:** `echo "$RESPONSE" | jq '{input: .usage.input_tokens, output: .usage.output_tokens}'`

**OpenAI:** `echo "$RESPONSE" | jq '{input: .usage.prompt_tokens, output: .usage.completion_tokens}'`

**Gemini:** `echo "$RESPONSE" | jq '{input: .usageMetadata.promptTokenCount, output: .usageMetadata.candidatesTokenCount}'`

### Pricing Table (per 1M tokens)

| Provider | Model | Input | Output |
|----------|-------|------:|-------:|
| Anthropic | claude-sonnet-4-6 | $3.00 | $15.00 |
| Anthropic | claude-opus-4-6 | $5.00 | $25.00 |
| Anthropic | claude-haiku-4-5 | $1.00 | $5.00 |
| OpenAI | gpt-5.4 | $2.50 | $15.00 |
| Gemini | gemini-3-flash-preview | $0.50 | $3.00 |

### Cost Calculation

```
cost = (input_tokens / 1_000_000 * input_rate) + (output_tokens / 1_000_000 * output_rate)
```

### Cost Report

Append a cost summary to every API response (`ask`, `ensemble`, `compare`, `review`):

```
---
**Cost:** Claude $0.0045 (312 in / 189 out) | GPT $0.0038 (298 in / 201 out) | Gemini $0.0008 (305 in / 195 out) | **Total: $0.0091**
```

For single-model calls (`ask`), show just that provider's cost. For multi-model calls, show per-provider breakdown + total.

---

## Reference

For model capabilities, context windows, pricing tiers, PR review rubrics,
and troubleshooting, read REFERENCE.md. Load on demand, not by default.
