---
name: ai-router
version: "1.1"
description: "Route tasks to optimal model tiers and ensemble responses across Claude, GPT, and Gemini APIs."
trigger: /ai-router
---

## Version Check
To check for updates: `curl -s https://raw.githubusercontent.com/My-Stacks/claude-code-skills/main/versions.yaml`
Compare against this file's version in frontmatter.

# AI Router Skill

Route tasks to the best Claude Code model tier, and optionally call external model APIs (Anthropic, OpenAI, Gemini) for ensemble responses. Requires `curl` and `jq`.

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

1. Check dependencies: `command -v jq >/dev/null 2>&1` and `command -v curl >/dev/null 2>&1`. If missing, tell user to install and stop.
2. Prompt for each API key (Enter to skip):
   > "Anthropic API key (sk-ant-...): "
   > "OpenAI API key (sk-...): "
   > "Gemini API key (AIza...): "
3. Require at least one key. If all skipped: "At least one API key is required."
4. Validate each provided key with a minimal API call (see Validation section below).
5. Write config with restrictive permissions:
   ```bash
   (umask 077 && python3 -c "import json; print(json.dumps(CONFIG))" > ~/.orchestrator-config.json)
   ```
6. Confirm: "ai-router configured. [N] provider(s) active: [list]."

### Key Validation

Use python3 for safe JSON construction. Write request body to a temp file, use `curl -sS -o /tmp/resp -w "%{http_code}"` to capture both body and status.

**Anthropic:**
```bash
python3 -c "import json; print(json.dumps({'model':'claude-haiku-4-5','max_tokens':1,'messages':[{'role':'user','content':'hi'}]}))" > /tmp/ai-router-val.json
STATUS=$(curl -sS -o /tmp/ai-router-resp -w "%{http_code}" --max-time 10 --connect-timeout 5 \
  https://api.anthropic.com/v1/messages \
  -H "x-api-key: $KEY" -H "anthropic-version: 2023-06-01" -H "content-type: application/json" \
  -d @/tmp/ai-router-val.json)
```

**OpenAI:**
```bash
python3 -c "import json; print(json.dumps({'model':'gpt-5.4','max_completion_tokens':1,'messages':[{'role':'user','content':'hi'}]}))" > /tmp/ai-router-val.json
STATUS=$(curl -sS -o /tmp/ai-router-resp -w "%{http_code}" --max-time 10 --connect-timeout 5 \
  https://api.openai.com/v1/chat/completions \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d @/tmp/ai-router-val.json)
```

**Gemini:**
```bash
python3 -c "import json; print(json.dumps({'contents':[{'parts':[{'text':'hi'}]}]}))" > /tmp/ai-router-val.json
STATUS=$(curl -sS -o /tmp/ai-router-resp -w "%{http_code}" --max-time 10 --connect-timeout 5 \
  "https://generativelanguage.googleapis.com/v1beta/models/gemini-3-flash-preview:generateContent" \
  -H "Content-Type: application/json" -H "x-goog-api-key: $KEY" \
  -d @/tmp/ai-router-val.json)
```

200 = valid. Anything else = warn and skip: "Anthropic key invalid (HTTP [code]). Skipping."

Clean up temp files after validation.

## Commands

| Command | What it does | API calls? |
|---------|-------------|:---:|
| `/ai-router` | First-run setup or command menu | No |
| `/ai-router setup` | Configure/reconfigure API keys | Validation only |
| `/ai-router route <task>` | Suggest best model tier | No |
| `/ai-router ask <prompt>` | Send to one external model | Yes |
| `/ai-router ensemble <prompt>` | Send to all configured models, synthesize | Yes |
| `/ai-router review` | Ensemble PR review | Yes |
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
> `/ai-router setup` — reconfigure keys (validates and overwrites config)

---

## `/ai-router route <task>`

Analyze the task description and recommend model tiers using this matrix:

| Signal words | CC Model | External | Reason |
|-------------|----------|----------|--------|
| plan, architect, design, strategy, system design | Opus | Anthropic (Opus) | Deep reasoning, long coherence |
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

1. Read config. Validate the provider key exists and is not null/empty before calling.
2. If only one provider configured, use it. If multiple, ask: "Which provider? (anthropic/openai/gemini)" — or auto-route using the routing matrix.
3. Call the API (see API Call Templates below).
4. Display the response with provider attribution.

**Output format:**

```
## [Provider] ([model])

[response content]
```

---

## `/ai-router ensemble <prompt>`

Send to all configured providers in parallel, then synthesize.

1. Read config. Identify active providers (key exists and is not null/empty).
2. If only one provider: fall back to `/ai-router ask` behavior.
3. Run all API calls in parallel using separate Bash tool calls where supported; otherwise run sequentially.
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

1. Get the diff to review (in priority order):
   - If user provides a PR number: `gh pr diff <number>`
   - If on a branch: `git diff $(git merge-base HEAD main)..HEAD`
   - If staged changes exist: `git diff --cached`
   - Last resort: `git diff HEAD~1` (check `git rev-list --count HEAD` > 1 first)
2. Check diff size. If > 80K characters, warn user and ask to scope (specific files or truncate).
3. Construct a review prompt using the full rubric:
   > "Review this code diff. Evaluate: (1) Correctness — logic errors, off-by-one, null handling, race conditions. (2) Security — injection, auth bypass, secrets exposure, OWASP top 10. (3) Performance — N+1 queries, unnecessary allocations, missing indexes. (4) Maintainability — naming, complexity, dead code, missing error handling. (5) Tests — coverage gaps, flaky patterns, missing edge cases. Be specific with file and line references. Categorize each finding as critical, suggestion, or nit."
4. Prepend the diff to the prompt.
5. Send to all configured providers in parallel.
6. Synthesize using the PR Review Synthesis format.

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

1. Read config. Identify active providers.
2. If only one provider: show single response with a note that compare requires 2+ providers.
3. Send to all configured providers in parallel.
4. Display each response under its own heading. No synthesis.

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
| Anthropic | sk-ant-...qAAA | claude-sonnet-4-6 | Active |
| OpenAI | sk-pro...DcA | gpt-5.4 | Active |
| Gemini | — | — | Not configured |

Config: ~/.orchestrator-config.json
```

Redact keys: if length > 12, show first 6 + last 4 characters. If shorter, show first 3 + "...". Show "Not configured" for missing/null providers.

---

## `/ai-router setup`

Re-run the first-run setup flow. Before overwriting, back up existing config:
```bash
cp ~/.orchestrator-config.json ~/.orchestrator-config.json.bak
```
Confirm with user: "This will overwrite your current config (backup saved to .bak). Continue?"

---

## API Call Templates

Use python3 for safe JSON construction. Write request body to a temp file, call curl with the file. This avoids shell injection and control character issues.

**Before any API call**, validate the provider key from config:
```bash
KEY=$(python3 -c "import json; c=json.load(open('$HOME/.orchestrator-config.json')); k=c.get('anthropic_api_key',''); print(k if k else '')")
[ -z "$KEY" ] && echo "Anthropic not configured" && exit 1
```

### Anthropic

```bash
python3 << 'PYEOF'
import json, subprocess, os

config = json.load(open(os.path.expanduser("~/.orchestrator-config.json")))
body = json.dumps({
    "model": config["default_anthropic_model"],
    "max_tokens": 4096,
    "messages": [{"role": "user", "content": PROMPT}]
})

result = subprocess.run([
    "curl", "-sS", "--max-time", "120", "--connect-timeout", "10",
    "-o", "/tmp/ai-router-resp.json", "-w", "%{http_code}",
    "https://api.anthropic.com/v1/messages",
    "-H", f"x-api-key: {config['anthropic_api_key']}",
    "-H", "anthropic-version: 2023-06-01",
    "-H", "content-type: application/json",
    "-d", body
], capture_output=True, text=True)

status = result.stdout.strip()
if status != "200":
    print(f"Anthropic error: HTTP {status}")
    print(open("/tmp/ai-router-resp.json").read()[:500])
else:
    resp = json.load(open("/tmp/ai-router-resp.json"))
    print(resp["content"][0]["text"])
    print("---USAGE---")
    u = resp.get("usage", {})
    print(json.dumps({"input": u.get("input_tokens", 0), "output": u.get("output_tokens", 0)}))
PYEOF
```

### OpenAI

```bash
python3 << 'PYEOF'
import json, subprocess, os

config = json.load(open(os.path.expanduser("~/.orchestrator-config.json")))
body = json.dumps({
    "model": config["default_openai_model"],
    "max_completion_tokens": 4096,
    "messages": [{"role": "user", "content": PROMPT}]
})

result = subprocess.run([
    "curl", "-sS", "--max-time", "120", "--connect-timeout", "10",
    "-o", "/tmp/ai-router-resp.json", "-w", "%{http_code}",
    "https://api.openai.com/v1/chat/completions",
    "-H", f"Authorization: Bearer {config['openai_api_key']}",
    "-H", "Content-Type: application/json",
    "-d", body
], capture_output=True, text=True)

status = result.stdout.strip()
if status != "200":
    print(f"OpenAI error: HTTP {status}")
    print(open("/tmp/ai-router-resp.json").read()[:500])
else:
    resp = json.load(open("/tmp/ai-router-resp.json"))
    print(resp["choices"][0]["message"]["content"])
    print("---USAGE---")
    u = resp.get("usage", {})
    print(json.dumps({"input": u.get("prompt_tokens", 0), "output": u.get("completion_tokens", 0)}))
PYEOF
```

### Gemini

```bash
python3 << 'PYEOF'
import json, subprocess, os

config = json.load(open(os.path.expanduser("~/.orchestrator-config.json")))
model = config["default_gemini_model"]
body = json.dumps({
    "contents": [{"parts": [{"text": PROMPT}]}]
})

result = subprocess.run([
    "curl", "-sS", "--max-time", "120", "--connect-timeout", "10",
    "-o", "/tmp/ai-router-resp.json", "-w", "%{http_code}",
    f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent",
    "-H", "Content-Type: application/json",
    "-H", f"x-goog-api-key: {config['gemini_api_key']}",
    "-d", body
], capture_output=True, text=True)

status = result.stdout.strip()
if status != "200":
    print(f"Gemini error: HTTP {status}")
    print(open("/tmp/ai-router-resp.json").read()[:500])
else:
    resp = json.load(open("/tmp/ai-router-resp.json"))
    print(resp["candidates"][0]["content"]["parts"][0]["text"])
    print("---USAGE---")
    u = resp.get("usageMetadata", {})
    print(json.dumps({"input": u.get("promptTokenCount", 0), "output": u.get("candidatesTokenCount", 0)}))
PYEOF
```

### Error Handling

Each template captures HTTP status and handles errors inline:
1. Non-200 status: print error with status code and first 500 chars of response body.
2. If a provider fails during ensemble, continue with remaining providers.
3. Note failures in the synthesis: "[Provider]: unavailable (HTTP [code])."
4. If all providers fail, report the errors — do not synthesize from nothing.

### Parallel Execution

For ensemble and compare commands, run all API calls as separate Bash tool calls in a single response where supported. Otherwise run sequentially. Each call writes to a provider-specific temp file to avoid conflicts.

### Prompt Construction

Use python3 `json.dumps()` to safely escape prompts for JSON embedding. Never interpolate raw user input into shell strings or JSON templates. For review commands, prepend the diff to the prompt string in Python before JSON-encoding.

### Model Override

To use a non-default model: `/ai-router ask --model claude-opus-4-6 "question"`. Parse `--model <value>` from the prompt. Validate model name contains only `[a-zA-Z0-9._-]` before substituting. Override the config default for that single call only.

---

## Cost Tracking

After every API call, extract token usage from the `---USAGE---` line and calculate cost.

### Pricing Table (per 1M tokens, estimates as of 2026-03)

| Provider | Model | Input | Output |
|----------|-------|------:|-------:|
| Anthropic | claude-sonnet-4-6 | $3.00 | $15.00 |
| Anthropic | claude-opus-4-6 | $5.00 | $25.00 |
| Anthropic | claude-haiku-4-5 | $1.00 | $5.00 |
| OpenAI | gpt-5.4 | $2.50 | $15.00 |
| Gemini | gemini-3-flash-preview | $0.50 | $3.00 |

Prices may change. See REFERENCE.md for latest known rates.

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
