# AI Router Reference

This file is not needed for `route`, `config`, or `setup` commands. Load on demand.

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
| OpenAI | gpt-5.5 | Broad knowledge, creative writing, multimodal, reasoning | 1M |
| Gemini | gemini-3-flash-preview | Speed, long context, multimodal, cost efficiency | 1M |

### Model Override

To use a non-default model for a single call:
> `/ai-router ask --model claude-opus-4-6 "deep architecture question"`

Parse `--model <value>` from the prompt. Validate the model name contains only `[a-zA-Z0-9._-]`. Substitute into the API call, overriding the config default for that single call.

For Anthropic/OpenAI: substitute in the `model` field of the JSON body.
For Gemini: substitute in the URL path.

## PR Review Rubric

When constructing review prompts, instruct each model to evaluate:

1. **Correctness** — Logic errors, off-by-one, null handling, race conditions
2. **Security** — Injection, auth bypass, secrets exposure, OWASP top 10
3. **Performance** — N+1 queries, unnecessary allocations, missing indexes
4. **Maintainability** — Naming, complexity, dead code, missing error handling
5. **Tests** — Coverage gaps, flaky patterns, missing edge cases

Ask models to reference specific lines/hunks and categorize severity (critical/suggestion/nit).

## Orchestrated review (`/ai-router review` / `/ensemble-review`)

Since v1.4, `review` defaults to a multi-phase **review → fix → re-review → merge-confidence** cycle. Full phase-by-phase instructions live in SKILL.md → "Orchestrated review-and-fix"; this section captures the supporting detail.

### Mode selection

| Invocation | Mode |
|------------|------|
| `/ai-router review [<pr>]`, `/ensemble-review [<pr>]` (interactive, no single-pass flags) | Orchestrated (all 4 phases) |
| `--single` | Single-pass only |
| `--post-to-pr <#>` | Single-pass only (forces it — keeps CI from committing) |
| Headless (`AI_ROUTER_RUN_ID` set, e.g. `shadow-review`) | Single-pass only |
| **Non-interactive** (no TTY / `claude -p` / can't confirm with operator) | Single-pass only |

Orchestration runs **only** in an interactive session with none of the single-pass flags — so a background/CI run, or any non-interactive `claude -p` invocation, can never commit, push, or trigger CodeRabbit. When in doubt about interactivity, the skill falls back to single-pass.

### CodeRabbit handling

- **Trigger from the operator identity, not a bot token.** CodeRabbit ignores commands issued by bot tokens (`GH_TOKEN`/`GITHUB_TOKEN`-authored comments on a bot-authored PR get skipped), so always post the trigger with those unset:
  ```bash
  env -u GH_TOKEN -u GITHUB_TOKEN gh pr comment "$PR" --body "@coderabbitai full review"
  ```
- **Async, never blocked on.** CR reviews on its own schedule; the cycle proceeds with whatever CR has posted by triage time.
- **Stale-SHA detection.** CR's review carries the `commit_id` it reviewed. If that ≠ the PR head at triage time, the disposition must say so explicitly — CR's findings may predate the latest commit. Pull it via:
  ```bash
  gh api "repos/$REPO/pulls/$PR/reviews" \
    --jq '[.[] | select((.user.login//"")|test("coderabbit";"i"))] | max_by(.submitted_at) | {sha: .commit_id, at: .submitted_at}'
  ```
- **≤ 2 triggers per PR** (round-1 full review + at most one round-2 `@coderabbitai review`).

### Merge confidence

Default threshold **90%** (`merge_confidence_threshold` in config). Computed from: zero unresolved critical/major findings, tests green, ensemble/CodeRabbit convergence (or consciously-resolved divergence), and a clean round-2 verification. Scoring heuristic and the verdict block are in SKILL.md → Phase 4. Never auto-merges regardless of score.

### Config tunables

| Config key | Default | Effect |
|------------|---------|--------|
| `merge_confidence_threshold` | `90` | Phase-4 merge-recommend cutoff (0–100). |
| `round2_scope` | `fix-commits` | Phase-3 targeted-diff scope: `fix-commits` (`git diff <round1_head>..<new_head>`), a path-spec string, or `full`. |

## Headless / CI Usage

The skill is safe to run under `claude -p` (headless mode), which is how `/ai-router shadow-review` works. Key contract:

- All provider calls go through `scripts/call-provider.sh`. The prompt is piped on stdin so the literal Bash command line is constant — pattern-matching allow-rules work cleanly.
- `/ai-router review <PR#> --post-to-pr <PR#>` writes the synthesis to stdout AND posts it as a PR comment via `scripts/post-review.sh`. Exit 0 iff at least one provider returned 200 and `gh pr comment` succeeded.

### Env vars

| Variable | Default | Effect |
|----------|---------|--------|
| `AI_ROUTER_CONFIG` | `~/.orchestrator-config.json` | Override config path (useful for CI). |
| `AI_ROUTER_TMPDIR` | `$TMPDIR` or `/tmp` | Where temp body/response files live. |
| `AI_ROUTER_RUN_ID` | new UUID | Embedded in the comment marker so the shadow poll can match the comment from one specific run. |
| `AI_ROUTER_PROVIDERS` | `anthropic,openai,gemini` | CSV listed in the comment marker. |
| `AI_ROUTER_SHADOW_TIMEOUT` | `1800` (s) | Shadow poll timeout. |

### Exit codes

| Code | Meaning |
|-----:|---------|
| 0 | OK |
| 2 | Not configured (no key for that provider) |
| 3 | Missing dependency (`curl`, `jq`, `python3`, `gh`) |
| 4 | HTTP non-200 from provider |
| 5 | Network / timeout |
| 10 | `gh pr comment` failed (post-review.sh only) |
| 64 | Usage error |

### Finding the shadow's PR comment

```bash
gh api repos/OWNER/REPO/issues/<PR>/comments \
  --jq '[.[] | select(.body | contains("<!-- ai-router:review:v"))] | last'
```

To match a specific run:

```bash
gh api repos/OWNER/REPO/issues/<PR>/comments \
  --jq --arg rid "$RUN_ID" \
       '[.[] | select(.body | contains("run-id=" + $rid))] | last'
```

## Signature Marker Contract

`scripts/post-review.sh` prepends every PR comment with:

```html
<!-- ai-router:review:v<MAJ.MIN> ts=<ISO-UTC> run-id=<uuid> -->
<!-- providers: anthropic,openai,gemini -->

<review markdown>

<!-- /ai-router:review:v<MAJ.MIN> run-id=<uuid> -->
```

- Version is read from `SKILL.md` frontmatter, so the marker stays in sync with the skill.
- `run-id` is the polling key. Re-runs always create a new comment (per user preference); poll matching is exact on `run-id`.
- `providers` lists which providers actually contributed (for partial-quorum reviews).

## Pre-authorizing the scripts (auto-mode)

Users with `permissions.defaultMode: "auto"` in `~/.claude/settings.json` need to allowlist the helper scripts. Add to `permissions.allow`:

```json
"Bash(bash ~/.claude/skills/ai-router/scripts/call-provider.sh:*)",
"Bash(bash ~/.claude/skills/ai-router/scripts/validate-key.sh:*)",
"Bash(bash ~/.claude/skills/ai-router/scripts/post-review.sh:*)",
"Bash(bash ~/.claude/skills/ai-router/scripts/shadow-spawn.sh:*)",
"Bash(bash ~/.claude/skills/ai-router/scripts/shadow-poll.sh:*)"
```

If `~` is not expanded in your Claude Code version, use the absolute path form (`/Users/<you>/.claude/skills/...`).

Why this works: the auto-mode classifier scores the literal command string. A bash invocation of a checked-in script has constant shape — review once, allow forever. The previous v1.2 design embedded multi-line `python3 << 'PYEOF' … curl https://api.anthropic.com … PYEOF` heredocs that varied byte-for-byte every call, so no allow pattern could match cleanly and the classifier denied them by default.

## Troubleshooting

### Classifier denied a Bash call ("auto mode classifier")
You have `permissions.defaultMode: "auto"` and are missing the allow snippet above. Add the five `Bash(bash ~/.claude/skills/ai-router/scripts/...)` lines to `~/.claude/settings.json` `permissions.allow`.

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
Check model name is valid and prompt is not empty. If using `--model` override, verify the model ID exists with the provider.

### Config file permissions
The config contains API keys. Setup creates it with `umask 077`, but verify:
```bash
chmod 600 ~/.orchestrator-config.json
```

### Large diffs in review
If the diff exceeds ~80K characters, the skill warns and asks the user to scope the review. To manually scope: `gh pr diff 42 -- src/` or pass specific file paths.

## Pricing Reference (per 1M tokens, estimates as of 2026-03)

| Provider | Model | Input | Output |
|----------|-------|------:|-------:|
| Anthropic | claude-sonnet-4-6 | $3.00 | $15.00 |
| Anthropic | claude-opus-4-6 | $5.00 | $25.00 |
| Anthropic | claude-haiku-4-5 | $1.00 | $5.00 |
| OpenAI | gpt-5.5 | ~$2.50* | ~$15.00* |
| Gemini | gemini-3-flash-preview | $0.50 | $3.00 |

*gpt-5.5 pricing approximated from gpt-5.4 rates, not yet verified against platform.openai.com/pricing — OpenAI cost reports are estimates (shown with ~) until updated.

Prices may change. These are used for cost estimates only.

### Typical Cost Per Command

| Command | Calls | Est. cost (short prompt) | Est. cost (PR review ~5K lines) |
|---------|------:|-------------------------:|--------------------------------:|
| ask | 1 | ~$0.005 | ~$0.05 |
| ensemble | 3 | ~$0.012 | ~$0.12 |
| compare | 3 | ~$0.012 | ~$0.12 |
| review --single | 3 | ~$0.05 | ~$0.15 |
| review (orchestrated) | 6+ (2 rounds × providers) | ~$0.10 | ~$0.30+ |
| route/config/setup | 0 | $0 | — |

The orchestrated `review` runs up to two ensemble rounds (round-1 full diff + round-2 fix-commits diff), so budget roughly 2× a single-pass review plus the smaller round-2 pass. Emit the per-round cost summary each round.

When the prompt is large (e.g., PR diffs), note the approximate token count so the user can decide whether to proceed.
