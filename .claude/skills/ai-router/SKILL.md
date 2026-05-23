---
name: ai-router
version: "1.3"
description: "Route tasks to optimal model tiers and ensemble responses across Claude, GPT, and Gemini APIs. Headless-safe with --post-to-pr for shadow review."
trigger: /ai-router
---

## Version Check
To check for updates: `curl -s https://raw.githubusercontent.com/My-Stacks/claude-code-skills/main/versions.yaml`
Compare against this file's version in frontmatter.

# AI Router Skill

Route tasks to the best Claude Code model tier, and optionally call external model APIs (Anthropic, OpenAI, Gemini) for ensemble responses. Requires `curl`, `jq`, `python3`, and (for `--post-to-pr` / `shadow-review`) `gh`.

External API calls go through `scripts/call-provider.sh` so they pass Claude Code's auto-mode classifier with a single `permissions.allow` rule per script.

## Config

File: `~/.orchestrator-config.json`

```json
{
  "anthropic_api_key": "sk-ant-...",
  "openai_api_key": "sk-...",
  "gemini_api_key": "AIza...",
  "default_anthropic_model": "claude-sonnet-4-6",
  "default_openai_model": "gpt-5.5",
  "default_gemini_model": "gemini-3-flash-preview"
}
```

All keys optional. At least one required for API commands.

## First Run Setup

On first invocation, check for `~/.orchestrator-config.json`.

If missing, run setup:

1. Check dependencies: `command -v jq && command -v curl && command -v python3`. If missing, tell user to install and stop.
2. Prompt for each API key (Enter to skip):
   > "Anthropic API key (sk-ant-...): "
   > "OpenAI API key (sk-...): "
   > "Gemini API key (AIza...): "
3. Require at least one key. If all skipped: "At least one API key is required."
4. **Validate each key BEFORE writing the config** so invalid keys never land on disk:
   ```bash
   PROBE=$(umask 077; mktemp "${TMPDIR:-/tmp}/ai-router-probe.XXXXXX")
   trap 'rm -f "$PROBE"' EXIT
   AI_ROUTER_CONFIG="$PROBE"
   # write a one-key probe config, run validate-key.sh <provider>, drop key if non-zero
   ```
   Exit 0 = valid; non-zero = warn "[Provider] key invalid (HTTP [code]). Skipping." and drop from the candidate set.
5. After validation, write the surviving keys to the real config with restrictive permissions. Pass the config object on stdin so no secrets land in argv:
   ```bash
   umask 077
   python3 -c 'import json,sys; json.dump(json.load(sys.stdin), open(sys.argv[1], "w"))' \
     ~/.orchestrator-config.json <<JSON
   {
     "anthropic_api_key": "$ANTHROPIC_KEY",
     "openai_api_key": "$OPENAI_KEY",
     "gemini_api_key": "$GEMINI_KEY",
     "default_anthropic_model": "claude-sonnet-4-6",
     "default_openai_model": "gpt-5.5",
     "default_gemini_model": "gemini-3-flash-preview"
   }
   JSON
   ```
6. Confirm: "ai-router configured. [N] provider(s) active: [list]."

## Commands

| Command | What it does | API calls? |
|---------|-------------|:---:|
| `/ai-router` | First-run setup or command menu | No |
| `/ai-router setup` | Configure/reconfigure API keys | Validation only |
| `/ai-router route <task>` | Suggest best model tier | No |
| `/ai-router ask <prompt>` | Send to one external model | Yes |
| `/ai-router ensemble <prompt>` | Send to all configured models, synthesize | Yes |
| `/ai-router review [<pr>] [--post-to-pr <pr>]` | Ensemble PR review; optionally post to PR | Yes |
| `/ai-router shadow-review` | Spawn a headless background review, poll for comments | Yes |
| `/ai-router shadow-cancel` | Stop a running shadow-review | No |
| `/ai-router compare <prompt>` | Side-by-side without synthesis | Yes |
| `/ai-router config` | Show current config (redacted keys) | No |

### `/ai-router` and `/ai-router help`

After setup, show the command menu:

> **AI Router** ([N] providers active: [list])
>
> `/ai-router route <task>` — suggest best model for a task
> `/ai-router ask <prompt>` — send to one external model
> `/ai-router ensemble <prompt>` — multi-model synthesis
> `/ai-router review` — ensemble PR review (add `--post-to-pr <#>` to post)
> `/ai-router shadow-review` — background review + PR-comment polling
> `/ai-router compare <prompt>` — side-by-side responses
> `/ai-router config` — show config
> `/ai-router setup` — reconfigure keys

---

## `/ai-router route <task>`

Recommend Claude Code model tier and whether to also call externals:

| Signal words | CC Model | External | Reason |
|-------------|----------|----------|--------|
| plan, architect, design, strategy, system design | Opus | Anthropic (Opus) | Deep reasoning, long coherence |
| code, implement, refactor, debug, fix, build | Sonnet | — | Best cost/quality for coding |
| format, rename, lookup, quick question, typo, lint | Haiku | — | Fast and cheap |
| review, audit, security, vulnerability | Sonnet | Ensemble (all) | Multiple perspectives catch more |
| brainstorm, explore, compare options, tradeoffs | Sonnet | Ensemble (all) | Diversity of thought |

**Output format:**

```text
## Route: [task summary]

**Claude Code:** Switch to [Model] -> run `/model [model-name]`
**External:** [None | Single provider | Ensemble recommended]
**Why:** [one line reasoning]
```

If already on the right model: "Already on [Model] — good fit for this task."

---

## `/ai-router ask <prompt>`

Send a prompt to a single external model.

1. Read config; ensure the chosen provider's key is set.
2. If multiple configured: ask "Which provider? (anthropic/openai/gemini)" or auto-route via the matrix above.
3. Call the API via `scripts/call-provider.sh`.
4. Display the response with provider attribution.

```text
## [Provider] ([model])

[response content]
```

---

## `/ai-router ensemble <prompt>`

Send to all configured providers in parallel, then synthesize.

1. Read config; identify active providers (key present and non-empty).
2. If only one provider: fall back to `ask` behavior.
3. Run all API calls in parallel (separate Bash tool calls).
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

Omit sections with no content. If a provider failed: "Gemini: unavailable (HTTP 429)."

---

## `/ai-router review [<pr-number>] [--post-to-pr <pr>]`

Ensemble PR review. Gathers diff context, sends to all configured models, synthesizes. Optionally posts the synthesis as a PR comment.

1. Get the diff to review (priority order):
   - PR number given: `gh pr diff <number>`
   - On a branch: `git diff $(git merge-base HEAD main)..HEAD`
   - Staged: `git diff --cached`
   - Last resort: `git diff HEAD~1` (if `git rev-list --count HEAD` > 1)
2. If diff > 80K characters, warn and ask to scope.
3. Construct the review prompt with the full rubric:
   > "Review this code diff. Evaluate: (1) Correctness — logic errors, off-by-one, null handling, race conditions. (2) Security — injection, auth bypass, secrets exposure, OWASP top 10. (3) Performance — N+1 queries, unnecessary allocations, missing indexes. (4) Maintainability — naming, complexity, dead code, missing error handling. (5) Tests — coverage gaps, flaky patterns, missing edge cases. Be specific with file and line references. Categorize each finding as critical, suggestion, or nit."
4. Prepend the diff to the prompt.
5. Send to all configured providers in parallel.
6. Synthesize using the PR Review Synthesis format below into a temp markdown file.
7. If `--post-to-pr <#>` (or a PR was resolved and the user passed `--post`):
   ```bash
   bash ~/.claude/skills/ai-router/scripts/post-review.sh <pr-number> <synth-file>
   ```
8. **Always print** the final markdown to stdout — required for headless mode (`claude -p`) where there is no interactive output.

**Headless contract:** `claude -p "/ai-router review 42 --post-to-pr 42"` exits 0 iff (a) ≥1 provider returned 200 and (b) the PR comment posted. Providers rendered in stable order: Anthropic → OpenAI → Gemini.

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

## `/ai-router shadow-review`

Run an ensemble PR review in a background headless Claude Code instance ("shadow") that has zero context bleed from the active session. The shadow posts the synthesized review to the PR as a comment; the active session polls the PR every 3 minutes for both the ai-router comment AND any CodeRabbit comment, then surfaces a synthesized handoff when both arrive.

Flow:

1. **Detect PR** for the current branch:
   ```bash
   gh pr view --json number,headRefName,url -q '.number'
   ```
   If empty: tell user "No PR for branch `<name>`. Push and open one first." and stop.

2. **Detect CodeRabbit** by checking the SAME endpoints the poller polls (issue comments on THIS PR + formal reviews on THIS PR). A repo-wide check would false-positive on a CodeRabbit comment from any past PR and trap us at the 30-min timeout.
   ```bash
   REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
   CR_ISSUE=$(gh api "repos/$REPO/issues/$PR/comments?per_page=100" --paginate \
     --jq '[.[] | select((.user.login // "")=="coderabbitai[bot]" or (.user.login // "")=="coderabbitai")] | length' 2>/dev/null || echo 0)
   CR_REVIEWS=$(gh api "repos/$REPO/pulls/$PR/reviews?per_page=100" --paginate \
     --jq '[.[] | select((.user.login // "")=="coderabbitai[bot]" or (.user.login // "")=="coderabbitai")] | length' 2>/dev/null || echo 0)
   if (( CR_ISSUE + CR_REVIEWS == 0 )); then
     # Fall back to a recent-activity probe on the repo (last 100 issue-comments)
     # so a brand-new PR with no CR history yet still benefits from CR detection.
     CR_RECENT=$(gh api "repos/$REPO/issues/comments?per_page=100" \
       --jq '[.[] | select((.user.login // "")=="coderabbitai[bot]" or (.user.login // "")=="coderabbitai")] | length' 2>/dev/null || echo 0)
     (( CR_RECENT > 0 )) || WAIT_FOR_CR=false
   fi
   ```
   If `WAIT_FOR_CR=false`: tell user "CodeRabbit not detected on this repo — polling for ai-router only."

3. **Confirm** with a single Y/N: "Shadow-review PR #N. Spawns a headless claude in background, polls every 3 min, 30 min timeout. OK?"

4. **Spawn:**
   ```bash
   STATE=$(bash ~/.claude/skills/ai-router/scripts/shadow-spawn.sh <PR> --wait-for-cr <true|false>)
   ```

5. **Schedule the poll** via `CronCreate` with cron `*/3 * * * *`. Save the cron ID to `$STATE/cron.id`. Use this prompt verbatim (substituting `<PR>` and `<STATE>`):
   ```text
   Run: bash ~/.claude/skills/ai-router/scripts/shadow-poll.sh <STATE>

   Read the first line of stdout:
   - BOTH_READY            → load <STATE>/both.json, render Shadow Handoff (see SKILL.md), CronDelete <cron-id>, summarize the two reviews in chat.
   - ONLY_AI_ROUTER_READY  → load <STATE>/both.json, render Shadow Handoff with CodeRabbit omitted, CronDelete <cron-id>.
   - WAITING               → do nothing, stay quiet.
   - TIMEOUT               → surface partial results from <STATE>/both.json if present plus last 50 lines of <STATE>/shadow.log; ask user to keep waiting or stop; do NOT auto-delete the cron.
   - FAILED:<status>       → show last 50 lines of <STATE>/shadow.log, CronDelete.
   ```

6. **Print to user:** "Shadow review running for PR #N (state: `$STATE`). Polling every 3 min. I'll surface results when ready. Stop early with `/ai-router shadow-cancel`."

7. **Return control immediately.** The user keeps working; the cron fires when there's news.

### `/ai-router shadow-cancel`

Two-step procedure (the parent assistant runs step 1 as a tool call, then step 2 as shell):

1. **Find state dir for this repo + delete the cron via the `CronDelete` tool:**
   ```bash
   REPO_SLUG=$(gh repo view --json nameWithOwner -q .nameWithOwner | tr '/' '-')
   SHADOW_BASE="${AI_ROUTER_SHADOW_DIR:-${AI_ROUTER_TMPDIR:-${TMPDIR:-/tmp}}/ai-router-shadow}"
   STATE=$(ls -dt "$SHADOW_BASE/${REPO_SLUG}-pr"*/ 2>/dev/null | grep -v '\.stale\.' | head -1 | sed 's:/$::')
   [ -z "$STATE" ] && echo "No active shadow for this repo." && exit 0
   [ -f "$STATE/cron.id" ] && echo "Cron to delete: $(cat "$STATE/cron.id")"
   ```
   Then the assistant invokes `CronDelete` (the Claude Code tool, not a shell command) with the printed ID.

2. **Kill the process group + clear state:**
   ```bash
   [ -f "$STATE/shadow.pgid" ] && kill -TERM -"$(cat "$STATE/shadow.pgid")" 2>/dev/null || true
   rm -rf "$STATE"
   ```

### Shadow Handoff Format

Rendered by the parent assistant when the poll returns `BOTH_READY` or `ONLY_AI_ROUTER_READY`. Synthesis is done in-session from `$STATE/both.json` — no extra API calls.

```markdown
## Shadow Review #<PR> — reviews are in
**AI Router ensemble** ([link])   ← link is `both.json` .ai_router.url
**CodeRabbit** ([link])           ← omit this line if CodeRabbit was skipped

### Where they agree
- <bullets from the intersection: same file/line, same finding category>

### AI Router caught (CodeRabbit did not)
- <bullets, with file:line>

### CodeRabbit caught (AI Router did not)
- <bullets, with file:line>

### Conflicts
- <if one says ship and the other flags critical, surface here>

### Recommended next step
<1-2 sentences>
```

### Comment Signature

`post-review.sh` wraps every PR comment with a signature marker block so the poll can identify the comment from a specific shadow run:

```html
<!-- ai-router:review:v<MAJ.MIN> ts=<ISO-UTC> run-id=<uuid> -->
<!-- providers: anthropic,openai,gemini -->

<review markdown>

<!-- /ai-router:review:v<MAJ.MIN> run-id=<uuid> -->
```

The `run-id` field is the contract — `shadow-poll.sh` matches `contains("run-id=<uuid>")` for the exact spawn. Re-running shadow-review on the same PR creates a new comment with a new `run-id`.

---

## `/ai-router compare <prompt>`

Side-by-side responses without synthesis. Otherwise identical to `ensemble`. Output:

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

Show config with redacted keys (first 6 + last 4 chars; first 3 + `...` if short):

```text
## AI Router Config

| Provider | Key | Model | Status |
|----------|-----|-------|--------|
| Anthropic | sk-ant-...qAAA | claude-sonnet-4-6 | Active |
| OpenAI    | sk-pro...DcA   | gpt-5.5           | Active |
| Gemini    | —              | —                 | Not configured |

Config: ~/.orchestrator-config.json
```

---

## `/ai-router setup`

Re-run first-run setup. Back up existing config first:
```bash
cp ~/.orchestrator-config.json ~/.orchestrator-config.json.bak
```
Confirm: "This will overwrite your current config (backup saved to .bak). Continue?"

---

## API Calls

All provider calls go through `scripts/call-provider.sh`. Pipe the prompt on stdin; read response from stdout; parse the trailing `---USAGE---` JSON line for cost.

```bash
SCRIPT="$HOME/.claude/skills/ai-router/scripts/call-provider.sh"

# Single call:
echo "$PROMPT" | bash "$SCRIPT" anthropic

# With overrides:
echo "$PROMPT" | bash "$SCRIPT" openai --model gpt-5.5 --max-tokens 8192 --timeout 300

# Ensemble (parallel — issue these as three separate Bash tool calls).
# Use a per-run temp dir so concurrent invocations never clobber each other:
RUN=$(mktemp -d "${TMPDIR:-/tmp}/ai-router-run-XXXXXX")
echo "$PROMPT" | bash "$SCRIPT" anthropic > "$RUN/claude.out"  2>"$RUN/claude.err"  &
echo "$PROMPT" | bash "$SCRIPT" openai    > "$RUN/gpt.out"     2>"$RUN/gpt.err"     &
echo "$PROMPT" | bash "$SCRIPT" gemini    > "$RUN/gemini.out"  2>"$RUN/gemini.err"  &
wait
```

Stdout shape:

```text
<response text>
---USAGE---
{"input":N,"output":N,"provider":"...","model":"..."}
```

Exit codes: `0` ok | `2` not configured | `3` missing deps | `4` HTTP non-200 | `5` network/timeout.

The prompt is piped on stdin and never appears on a command line — the auto-mode classifier sees a constant `bash …/call-provider.sh <provider>` invocation, which can be pre-authorized with a single `permissions.allow` rule per script.

### Required permissions.allow snippet

Add to `~/.claude/settings.json` `permissions.allow`:

```json
"Bash(bash ~/.claude/skills/ai-router/scripts/call-provider.sh:*)",
"Bash(bash ~/.claude/skills/ai-router/scripts/validate-key.sh:*)",
"Bash(bash ~/.claude/skills/ai-router/scripts/post-review.sh:*)",
"Bash(bash ~/.claude/skills/ai-router/scripts/shadow-spawn.sh:*)",
"Bash(bash ~/.claude/skills/ai-router/scripts/shadow-poll.sh:*)"
```

Without these, `defaultMode: "auto"` will prompt on every call. (Allow-rule paths must match the literal command Claude invokes; if `~` doesn't expand in your Claude Code version, use `/Users/<you>/.claude/skills/ai-router/scripts/...`.)

### Model Override

To use a non-default model for one call: pass `--model <id>` after the provider. Model IDs must match `[A-Za-z0-9._-]+` (validated by the script).

### Error Handling

`call-provider.sh` writes errors to stderr with `<provider>: HTTP <code>` and the first 500 chars of the response body. Exit code distinguishes config (2), deps (3), HTTP (4), network (5). For ensembles, treat non-zero exits per-provider — continue with the others and note the failure: "Gemini: unavailable (HTTP 429)."

---

## Cost Tracking

After every API call, parse the `---USAGE---` JSON line and compute cost from the table in REFERENCE.md.

```text
cost = (input_tokens / 1_000_000 * input_rate) + (output_tokens / 1_000_000 * output_rate)
```

Append a cost summary to every API response:

```text
---
**Cost:** Claude $0.0045 (312 in / 189 out) | GPT $0.0038 (298 in / 201 out) | Gemini $0.0008 (305 in / 195 out) | **Total: $0.0091**
```

For single-model calls, show just that provider. For multi-model, show per-provider breakdown + total.

---

## Reference

Model catalog, pricing, PR review rubric, troubleshooting, headless/CI usage, and signature marker contract: see REFERENCE.md. Load on demand, not by default.
