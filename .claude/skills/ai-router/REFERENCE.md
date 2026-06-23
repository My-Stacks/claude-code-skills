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

## Grounding (anti-hallucination) — `format-diff.py`

Raw `git diff` is a poor input for a reviewer: the model has to guess line numbers
(it routinely invents them) and only sees 3 lines of context, so it speculates about
code it can't see. `/ai-router review` mitigates both before any model is called:

1. **Expanded context.** Local diffs are fetched with `git diff -U${AI_ROUTER_DIFF_CONTEXT:-8}`
   (8 lines instead of 3), giving the model the enclosing scope. (`gh pr diff` serves a
   fixed-context diff — PR-number reviews get GitHub's default; local-branch reviews get
   the expansion.)
2. **Line-numbered, hunk-split reformat** via `scripts/format-diff.py` (stdin → stdout,
   read-only, stdlib-only). It rewrites the diff into:

   ```text
   ## File: 'src/auth.py'

   @@ ... @@ def login(user):
   __new hunk__
   13 +    cache.set(user.id, token, ttl=3600)
   14 +    audit_log(user.id, "login")
   15      return token
   __old hunk__
   -    cache.set(user.id, token)
        return token
   ```

   The `__new hunk__` numbers are the real new-file line numbers, so findings cite
   actual lines and a later verify pass can map each one back to the working tree.
   Binary files are dropped; deleted/renamed/new files are handled.
3. **Grounding rules in the prompt** (see SKILL.md → review step 4): only review `+`
   lines; don't flag names that may be defined elsewhere; don't claim a change breaks
   other code unless the path is visible; prefer not-reporting over guessing.

Findings are emitted as fixed blocks (`### <SEVERITY>: <title>` + `file:Lstart-Lend` +
category + issue + one-line fix) so synthesis can dedup across providers by `file:line`.

> Attribution: the line-numbered `__new hunk__`/`__old hunk__` reformat, expanded/asymmetric
> context, and self-reflection ideas are adapted from [PR-Agent](https://github.com/The-PR-Agent/pr-agent)
> (Apache-2.0). The algorithms are reimplemented here in our own code; no prompt text is
> copied verbatim.

## Verify pass + inline comments (v1.5)

PR-Agent can only *approximate* grounding with an LLM self-reflection pass — it has no
repo access. ai-router runs in the repo, so it grounds findings deterministically.

**`verify-findings.py`** (read-only, stdlib-only) — reads the findings JSON on stdin and
`--diff $RUN/diff.txt`, and annotates each finding with `verify.status`:

| status | meaning | inline? |
|--------|---------|:------:|
| `confirmed` | every cited line was in the reviewed diff | yes |
| `partial` | some cited lines were in the diff | yes |
| `unverified` | file/lines not in the reviewed diff — the usual hallucination signature | no (listed in body) |

It verifies against the **grounded diff**, not the working tree, on purpose: a review of a
PR *number* may run from a different branch, so the working tree can be the wrong content;
the diff is always exactly what the models saw. It also returns the real `shown_code` for the
grounded lines and which were `+` additions (safe targets for inline placement).

**`post-inline.sh`** + **`lib/build-review-payload.py`** — turn verified findings into a single
GitHub PR review (`POST /pulls/{pr}/reviews`, `event=COMMENT`):

- one inline comment per `confirmed`/`partial` finding, placed at its grounded line(s);
- a committable ```suggestion block when a `confirmed` finding carries `suggestion` (replacement
  code) — the human clicks "Commit suggestion" (this is the L1 "suggest" posture; auto-apply is Phase 3);
- `unverified` findings are appended to the review body under "Not grounded", never posted inline
  (GitHub rejects comments on out-of-diff lines — so the verify gate is also what makes inline posting valid);
- same input-file safety model as `post-review.sh` (trusted tmpdir, owner check, no symlinks);
- every inline comment carries a hidden `<!-- ai-router-finding -->` marker so its thread can
  later be identified and resolved without touching human threads.

## Resolving threads — `resolve-threads.sh` (v1.6)

CodeRabbit-style hygiene: ai-router resolves its **own** inline threads once they're stale, so
they don't pile up across pushes. REST can't resolve review threads, so this uses GraphQL
(`reviewThreads` query + `resolveReviewThread` mutation).

- Only threads whose first comment carries `<!-- ai-router-finding -->` are ever resolved.
- **default:** resolve only `isOutdated` threads — the code they anchor to changed since the
  comment was posted, so the finding was almost certainly addressed. The review flow runs this
  automatically right after an inline post (step 10), cleaning up the previous run's threads.
- **`--all`:** resolve every unresolved ai-router thread (manual cleanup via `/ai-router resolve <pr> --all`).

The hidden marker is the contract — a human's thread (no marker) is never touched, and a Phase 3
fixer can match a specific finding's thread by `path`/`line` to resolve exactly what it fixed.

Roadmap: Phase 3 — an opt-in `fix-findings` step that *applies* suggestions, persona-gated
(developers get suggestions; a `guided` persona gets a guarded auto-fixer on a conservative
allowlist, never main, tests must pass), resolving each thread it fixes via `resolve-threads.sh`.

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
| `AI_ROUTER_DIFF_CONTEXT` | `8` | Lines of context for local `git diff -U` before the grounding reformat. Higher = more enclosing scope, more tokens. |

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

### Finding the shadow's post

By default the post is an inline **review** (in `pulls/<PR>/reviews`); with `--summary-only` it's an issue **comment** (in `issues/<PR>/comments`). Both carry the same `run-id`, so match on it across both endpoints:

```bash
# inline review (default)
gh api repos/OWNER/REPO/pulls/<PR>/reviews \
  --jq --arg rid "$RUN_ID" '[.[] | select((.body // "") | contains("run-id=" + $rid))] | last'

# summary comment (--summary-only)
gh api repos/OWNER/REPO/issues/<PR>/comments \
  --jq --arg rid "$RUN_ID" '[.[] | select((.body // "") | contains("run-id=" + $rid))] | last'
```

`shadow-poll.sh` checks both automatically.

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
"Bash(bash ~/.claude/skills/ai-router/scripts/shadow-poll.sh:*)",
"Bash(python3 ~/.claude/skills/ai-router/scripts/format-diff.py:*)",
"Bash(python3 ~/.claude/skills/ai-router/scripts/verify-findings.py:*)",
"Bash(bash ~/.claude/skills/ai-router/scripts/post-inline.sh:*)",
"Bash(bash ~/.claude/skills/ai-router/scripts/resolve-threads.sh:*)"
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
The diff is reformatted by `format-diff.py` first, then size-checked: interactive mode warns and asks the user to scope above ~150K chars; headless (shadow) mode truncates to the last 500K chars. To manually scope: `gh pr diff 42 -- src/` or pass specific file paths. Lower `AI_ROUTER_DIFF_CONTEXT` (e.g. `3`) to shrink a borderline diff without dropping files.

### Review cites a line that looks off
Line numbers come from the `__new hunk__` side of `format-diff.py` (real new-file numbers). If a citation seems wrong, confirm you fed `$RUN/diff.txt` (the reformatted output) to the providers, not the raw `git diff`. Feeding the raw diff is the usual cause of hallucinated line numbers.

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
| review | 3 | ~$0.05 | ~$0.15 |
| route/config/setup | 0 | $0 | — |

When the prompt is large (e.g., PR diffs), note the approximate token count so the user can decide whether to proceed.
