---
name: ai-router
version: "1.5"
description: "Route tasks to optimal model tiers and ensemble responses across Claude, GPT, and Gemini APIs. Grounded PR review (line-numbered diff, anti-hallucination rules, findings verified against the diff, inline comments). Headless-safe with --post-to-pr for shadow review."
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
5. After validation, write the surviving keys to the real config with restrictive permissions. Build the JSON inside Python so `json.dump` escapes everything correctly — never interpolate raw keys into a JSON heredoc (`"`, `\`, `$`, newline in a key would corrupt the file or trigger shell expansion). Keys are passed via env vars so they never appear in argv:
   ```bash
   umask 077
   ANTHROPIC_KEY="$ANTHROPIC_KEY" \
   OPENAI_KEY="$OPENAI_KEY" \
   GEMINI_KEY="$GEMINI_KEY" \
   python3 - "$HOME/.orchestrator-config.json" <<'PY'
   import json, os, sys
   cfg = {
       "anthropic_api_key": os.environ.get("ANTHROPIC_KEY", "") or None,
       "openai_api_key":    os.environ.get("OPENAI_KEY", "")    or None,
       "gemini_api_key":    os.environ.get("GEMINI_KEY", "")    or None,
       "default_anthropic_model": "claude-sonnet-4-6",
       "default_openai_model":    "gpt-5.5",
       "default_gemini_model":    "gemini-3-flash-preview",
   }
   # Drop providers the user skipped so config_exists / *_key() return ""
   cfg = {k: v for k, v in cfg.items() if v is not None}
   with open(sys.argv[1], "w") as f:
       json.dump(cfg, f, indent=2)
   PY
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
| `/ai-router review [<pr>] [--post-to-pr <pr>] [--summary-only]` | Ensemble PR review, verified against the diff; posts inline comments by default (`--summary-only` for one comment) | Yes |
| `/ai-router shadow-review [--post] [--pr <#>] [--wait-cr] [--wait-reviewers]` | Spawn a background review; default stdout-only and surfaces as soon as ai-router finishes. `--wait-cr` adds CodeRabbit to the AND-wait, `--wait-reviewers` adds any non-author reviewer. | Yes |
| `/ai-router shadow-list` | List active shadow runs for this repo | No |
| `/ai-router shadow-cancel [<pr>]` | Stop a running shadow-review (most-recent if no PR given) | No |
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

## `/ai-router review [<pr-number>] [--post-to-pr <pr>] [--summary-only]`

Ensemble PR review. Gathers diff context, sends to all configured models, synthesizes, **verifies each finding against the reviewed diff**, then — when a PR is given — posts grounded findings as **inline comments** at the real lines with committable suggestions. Posting is opt-in (needs `<pr-number>` or `--post-to-pr <#>`); pass `--summary-only` to post one summary comment instead of inline threads.

1. Get the diff to review (priority order). Use expanded context (`-U`) on local diffs so models see the enclosing scope, not just 3 lines — part of the grounding below:
   - PR number given: `gh pr diff <number>` (GitHub serves a fixed-context diff)
   - On a branch: `git diff -U${AI_ROUTER_DIFF_CONTEXT:-8} "$(git merge-base HEAD main)"..HEAD`
   - Staged: `git diff -U${AI_ROUTER_DIFF_CONTEXT:-8} --cached`
   - Last resort: `git diff -U${AI_ROUTER_DIFF_CONTEXT:-8} HEAD~1` (if `git rev-list --count HEAD` > 1)
2. **Ground the diff (anti-hallucination — do this before any model sees it).** Pipe the raw diff through the line-numbering pre-processor:
   ```bash
   RUN=$(mktemp -d "${TMPDIR:-/tmp}/ai-router-run-XXXXXX")
   <diff-command> | python3 ~/.claude/skills/ai-router/scripts/format-diff.py > "$RUN/diff.txt"
   ```
   It splits each hunk into a `__new hunk__` section (every line prefixed with its **real** new-file line number) and an optional `__old hunk__` section (removed code). Models then cite actual line numbers instead of inventing them, and a future verify pass can map each finding back to the working tree. Feed `$RUN/diff.txt` — never the raw diff — to the providers. If it's empty, there's nothing to review; say so and stop.
3. **Scope-check `$RUN/diff.txt`.** Branches on whether we're running headless (shadow) vs interactive:
   - **Headless mode** — detected by `[ -n "$AI_ROUTER_RUN_ID" ]` (set by `lib/shadow-runner.sh`). NEVER ask the user; there is no interactive user. If it's > 500K chars, truncate to the last 500K and prepend a header line: `[diff truncated from <N>K chars to 500K — showing tail]`. Otherwise pass through. Cost is already bounded by the shadow's runtime cap + per-call `MAX_TOKENS`.
   - **Interactive mode** — if > 150K chars, warn and ask the user to scope. Below 150K, pass through (modern provider context windows handle this comfortably).
4. Construct the review prompt. It MUST explain the grounded format and enforce the grounding rules — these are what keep the review from hallucinating:
   > "You are reviewing a Git PR diff in a grounded format. Each file is introduced by `## File: '<path>'`. Each hunk is split into a `__new hunk__` section (code after the change, every line prefixed with its real line number) and an optional `__old hunk__` section (removed code, no numbers). Leading `+`/`-`/space marks added/removed/unchanged lines; the line numbers are reference-only, not part of the code.
   >
   > Review ONLY new code (lines starting with `+`) and issues this PR introduces. Evaluate: (1) Correctness — logic errors, off-by-one, null handling, race conditions. (2) Security — injection, auth bypass, secrets exposure, OWASP top 10. (3) Performance — N+1 queries, unnecessary allocations, missing indexes. (4) Maintainability — naming, complexity, dead code, missing error handling. (5) Tests — coverage gaps, flaky patterns, missing edge cases.
   >
   > Grounding rules (follow strictly — they cut false positives): You see only changed segments, not the whole repository. Do NOT flag imports, declarations, or names that may be defined elsewhere. Do NOT claim a change breaks other code unless the specific affected path is visible in the diff. Prefer not reporting over guessing — only flag an issue you can tie to a concrete trigger scenario. For a high-impact but uncertain issue (e.g. data loss, security), you may report it but must state what remains uncertain. Cite real line numbers taken from a `__new hunk__` section.
   >
   > For each issue, output exactly this block:
   > ### \<CRITICAL|SUGGESTION|NIT\>: \<short title\>
   > - **file:** \`path:Lstart-Lend\`
   > - **category:** correctness | security | performance | maintainability | tests
   > - **issue:** what is wrong and the concrete scenario that triggers it
   > - **fix:** one-line direction (no code dump)
   > - **suggestion:** (optional) the exact replacement code for the cited lines — include ONLY for a safe, mechanical, single-hunk fix; omit otherwise
   >
   > If you find no issues, output exactly: No issues found."
5. Prepend `$RUN/diff.txt` to the prompt under a `The PR code diff:` header.
6. Send to all configured providers in parallel.
7. **Extract findings to JSON.** From the per-provider finding blocks, build `$RUN/findings.json` — an array of objects:
   ```json
   {"severity":"CRITICAL|SUGGESTION|NIT","category":"...","file":"path","start_line":13,"end_line":14,"issue":"...","fix":"...","suggestion":"<optional replacement code>","sources":["anthropic","gemini"]}
   ```
   Dedup across providers by `file:line` + category, merging `sources` (two models at the same spot = one finding, higher confidence). Carry `suggestion` only when a provider gave safe single-hunk replacement code.
8. **Verify against the reviewed diff (repo-grounding — the anti-hallucination gate):**
   ```bash
   python3 ~/.claude/skills/ai-router/scripts/verify-findings.py --diff "$RUN/diff.txt" < "$RUN/findings.json" > "$RUN/verified.json"
   ```
   Each finding gains `verify.status`: **confirmed** (all cited lines were in the diff), **partial** (some), or **unverified** (file/lines not in the reviewed diff — the usual hallucination signature). Treat `unverified` as untrusted: never present it as a confirmed bug; surface it separately as "could not ground."
9. Synthesize using the PR Review Synthesis format below into `$RUN/synth.md`, ordered by verified status (confirmed first; unverified demoted to its own section).
10. **Post — opt-in via `<pr-number>` or `--post-to-pr <#>`; inline is the default style.** When a PR is resolved and posting is requested:
    - **default (inline):** post grounded findings as a PR review — one inline comment per confirmed/partial finding at its real line(s), with a committable ```suggestion block where `suggestion` is present. Ungrounded findings go in the review body, never inline (GitHub rejects out-of-diff lines):
      ```bash
      bash ~/.claude/skills/ai-router/scripts/post-inline.sh <pr-number> "$RUN/verified.json" "$RUN/synth.md"
      ```
    - **`--summary-only`:** opt down to a single summary comment instead of inline threads:
      ```bash
      bash ~/.claude/skills/ai-router/scripts/post-review.sh <pr-number> "$RUN/synth.md"
      ```
    Running `review` with no PR resolved posts nothing — it just prints to stdout (step 11).
11. **Always print** the final markdown to stdout — required for headless mode (`claude -p`) where there is no interactive output. Then `rm -rf "$RUN"`.

**Headless contract:** `claude -p "/ai-router review 42 --post-to-pr 42"` exits 0 iff (a) ≥1 provider returned 200 and (b) the PR comment posted (the inline review by default, or a summary comment with `--summary-only`). Providers rendered in stable order: Anthropic → OpenAI → Gemini.

### PR Review Synthesis Format

Because the diff is grounded, every finding carries a real `file:line`. Dedup across providers by `file:line` + category: two models flagging the same location is one finding (flag it as cross-model — higher confidence), not two. Keep the `file:line` on every bullet so the reader can jump straight to the code. Order by `verify.status` from step 8 — confirmed findings first, unverified demoted to their own section and never asserted as bugs.

```markdown
## Ensemble PR Review

### Critical Issues (flagged by 2+ models)
[Highest priority — issues multiple models independently caught. Each: `file:line` — issue.]

### Suggestions
[Deduplicated improvements from any model. Each: `file:line` — issue.]

### Model-Specific Catches
[Issues found by only one model — lower confidence, worth checking. Each: `file:line` — issue.]

### Could not ground (excluded from inline)
[Findings whose `verify.status` is `unverified` — they cite code outside the reviewed diff (often hallucinated or out of scope). List them, do not assert them. Omit this section if empty.]

### Summary
[Overall assessment]
```

---

## `/ai-router shadow-review [--post] [--pr <#>] [--wait-cr] [--wait-reviewers]`

Run an ensemble PR review in a background headless Claude Code instance ("shadow") that has minimal context bleed from the active session (see Isolation below). The shadow writes the synthesized review to `$STATE/shadow.log`; the active session polls every 3 minutes and surfaces the review when ready.

**Posting is opt-in.** Default is stdout/log only — the user reads the synthesis, decides what to keep, and posts in their own voice. Pass `--post` to also post the raw synthesis as a PR comment with the `<!-- ai-router:review:v… -->` signature marker.

**Waiting is opt-in (AND semantics).** With no `--wait-*` flag, the run surfaces as `ONLY_AI_ROUTER_READY` as soon as the headless ai-router review finishes (usually 2–4 min). Add flags to extend the wait — every flag is an AND clause:

- `--wait-cr` — also wait for CodeRabbit to post a fresh review/comment on this PR after spawn time.
- `--wait-reviewers` — also wait for any non-author reviewer (humans, other bots) to post a fresh review or comment.

Both can be combined. The run surfaces `ALL_READY` only when ai-router AND every requested wait source has landed. A pre-spawn freshness check warns the user when the wait source has already reviewed the latest commit and is unlikely to re-review.

### Isolation (what "zero context bleed" actually means)

- The shadow is a fresh `claude -p` process. It has **no access** to the parent session's conversation history, no shared memory, no plan/task state.
- It **does** inherit `HOME`, `PATH`, `TMPDIR`, locale, the documented `AI_ROUTER_*` overrides, and — *if set in the parent* — `GH_TOKEN` / `GITHUB_TOKEN`. Everything else is scrubbed via `env -i` in `lib/shadow-runner.sh`.
- **Provider API keys** (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, etc.) are always scrubbed regardless of whether they're set in the parent. The shadow reads provider keys from `~/.orchestrator-config.json` only.
- **`GH_TOKEN` / `GITHUB_TOKEN` passthrough is intentional** for CI compatibility — GitHub Actions and most CI runners authenticate `gh` solely via env tokens, not via a `~/.config/gh/hosts.yml` file. Interactive local users typically have file-backed `gh` auth and no `GH_TOKEN` set, so nothing leaks. If you want to scrub them anyway (e.g. running under a service account with a different `gh` identity than the parent), unset the var before invoking the skill.
- The shadow has a hard runtime cap (default 600s, `AI_ROUTER_SHADOW_RUNTIME` to override). The cap is enforced by `subprocess.Popen(start_new_session=True)` + `Popen.wait(timeout=…)` + `os.killpg(SIGTERM→SIGKILL)` in `lib/shadow-runner.sh`, so the `claude` child sits in its own process group and is killed cleanly when the cap fires (no orphan to launchd/init).

### Orphan warning

If the parent session ends after spawning but before the cron fires `ALL_READY` / `ONLY_AI_ROUTER_READY`, the shadow keeps running until it (a) finishes its `claude -p` review or (b) hits the runtime cap. The cron dies with the session, so the result won't be surfaced — but if `--post` was set, the comment will still land on the PR. Use `/ai-router shadow-list` to find orphaned state dirs and `/ai-router shadow-cancel <pr>` to terminate one.

### Flow

1. **Detect PR** for the current branch (or honor `--pr <#>` if passed):
   ```bash
   gh pr view --json number,headRefName,url -q '.number'
   ```
   If empty: tell user "No PR for branch `<name>`. Push and open one first." and stop.

2. **Freshness check (only when `--wait-cr` or `--wait-reviewers` was passed).** Don't auto-detect anything — the wait flags are explicit user opt-in. But warn the user when the requested wait source has already reviewed the latest commit (in which case it won't post again unless they push):
   ```bash
   REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
   LATEST_COMMIT_AT=$(gh api "repos/$REPO/pulls/$PR/commits" \
     --jq '[.[] | .commit.committer.date] | max // ""')

   if [[ "$WAIT_CR" == "true" ]]; then
     LAST_CR_AT=$(gh api "repos/$REPO/pulls/$PR/reviews" \
       --jq '[.[] | select((.user.login // "") | test("coderabbit"; "i"))] | max_by(.submitted_at) | .submitted_at // ""')
     if [[ -n "$LAST_CR_AT" && "$LAST_CR_AT" > "$LATEST_COMMIT_AT" ]]; then
       # warn: "CodeRabbit already reviewed the latest commit (at $LAST_CR_AT).
       # It won't re-review unless you push new commits. Wait anyway? (y/N)"
     fi
   fi
   if [[ "$WAIT_REVIEWERS" == "true" ]]; then
     LAST_REVIEWER_AT=$(gh api "repos/$REPO/pulls/$PR/reviews" \
       --jq "[.[] | select((.user.login // \"\") != \"$PR_AUTHOR\")
                  | select((.user.login // \"\") | test(\"coderabbit\"; \"i\") | not)]
              | max_by(.submitted_at) | .submitted_at // \"\"")
     if [[ -n "$LAST_REVIEWER_AT" && "$LAST_REVIEWER_AT" > "$LATEST_COMMIT_AT" ]]; then
       # warn similarly and confirm
     fi
   fi
   ```
   If the user declines, drop the corresponding flag and proceed without it (or stop, per their choice).

3. **Confirm** with a single Y/N: "Shadow-review PR #N. Spawns a headless claude in background, polls every 3 min, 30 min timeout. Posting to PR: \<yes/no\>. Waiting: \<none | CodeRabbit | reviewers | CodeRabbit+reviewers\>. OK?"

4. **Spawn** (pass only the flags the user actually opted into):
   ```bash
   STATE=$(bash ~/.claude/skills/ai-router/scripts/shadow-spawn.sh <PR> \
     [--wait-cr] \
     [--wait-reviewers] \
     [--post])
   ```

5. **Schedule the poll** via `CronCreate` with cron `*/3 * * * *`. Save the cron ID to `$STATE/cron.id`. Use this prompt verbatim (substituting `<PR>` and `<STATE>`):
   ```text
   Run: bash ~/.claude/skills/ai-router/scripts/shadow-poll.sh <STATE>

   Read the first line of stdout:
   - ALL_READY             → load <STATE>/both.json, render Shadow Handoff (see SKILL.md), CronDelete <cron-id>, summarize the reviews in chat, then `rm -rf <STATE>` (synthesis is in chat, state dir is dead weight).
   - ONLY_AI_ROUTER_READY  → load <STATE>/both.json, render Shadow Handoff with the ai-router section only, CronDelete <cron-id>, then `rm -rf <STATE>`.
   - WAITING               → do nothing, stay quiet.
   - TIMEOUT               → surface partial results from <STATE>/both.json if present plus last 50 lines of <STATE>/shadow.log; ask user to keep waiting or stop; do NOT auto-delete the cron and do NOT remove <STATE> (user may want to inspect).
   - FAILED:<status>       → show last 50 lines of <STATE>/shadow.log and <STATE>/poll.err if present, CronDelete. Do NOT remove <STATE> — diagnostics are still useful.
   ```

   Cleanup policy: successful terminal states (ALL_READY / ONLY_AI_ROUTER_READY) auto-remove the state dir because the synthesis is already rendered in chat. Failure modes (TIMEOUT / FAILED) keep the state dir so the user can `cat <STATE>/shadow.log` / `cat <STATE>/poll.err` for diagnosis.

6. **Print to user:** "Shadow review running for PR #N (state: `$STATE`). Polling every 3 min. I'll surface results when ready. Stop early with `/ai-router shadow-cancel`."

7. **Return control immediately.** The user keeps working; the cron fires when there's news.

### `/ai-router shadow-list`

Lists active shadow runs for this repo (skipping `.stale.*` archives):

```bash
bash ~/.claude/skills/ai-router/scripts/shadow-list.sh
```

Output is tab-separated: `PR  STATUS  STARTED_AT  STATE_DIR  PID  ALIVE`. Use when investigating why a poll never fired, or to find orphans after a session ended uncleanly.

### `/ai-router shadow-cancel [<pr>]`

Two-step procedure (assistant invokes `CronDelete` as a tool, then runs the shell).

1. **Locate the state dir** (by PR if provided, else most-recent for this repo) and print the cron ID:
   ```bash
   REPO_SLUG=$(gh repo view --json nameWithOwner -q .nameWithOwner | tr '/' '-')
   SHADOW_BASE="${AI_ROUTER_SHADOW_DIR:-${AI_ROUTER_TMPDIR:-${TMPDIR:-/tmp}}/ai-router-shadow}"
   if [[ -n "${1:-}" ]]; then
     [[ "$1" =~ ^[1-9][0-9]*$ ]] || { echo "invalid PR: $1" >&2; exit 2; }
     STATE="$SHADOW_BASE/${REPO_SLUG}-pr$1"
     [[ -d "$STATE" ]] || { echo "No shadow for PR $1." && exit 0; }
   else
     STATE=$(ls -dt "$SHADOW_BASE/${REPO_SLUG}-pr"*/ 2>/dev/null | grep -v '\.stale\.' | head -1 | sed 's:/$::')
     [ -z "$STATE" ] && echo "No active shadow for this repo." && exit 0
   fi
   [ -f "$STATE/cron.id" ] && echo "Cron to delete: $(cat "$STATE/cron.id")"
   ```
   The assistant then invokes the `CronDelete` Claude tool with the printed ID.

2. **Kill BOTH process groups + clear state:**
   ```bash
   # claude.pgid: the actual reviewer (start_new_session=True puts it in its
   # own pgid, distinct from the runner). Killing only shadow.pgid would
   # leave claude detached. Signal claude first so the runner can write the
   # status file before its own pgid gets killed.
   for f in claude.pgid shadow.pgid; do
     if [[ -f "$STATE/$f" ]]; then
       PGID=$(cat "$STATE/$f")
       [[ "$PGID" =~ ^[0-9]+$ ]] && kill -TERM -"$PGID" 2>/dev/null || true
     fi
   done
   rm -rf "$STATE"
   ```

### Shadow Handoff Format

Rendered by the parent assistant when the poll returns `ALL_READY` or `ONLY_AI_ROUTER_READY`. Synthesis is done in-session from `$STATE/both.json` — no extra API calls. In `--post=false` mode, the ai-router body comes from `$STATE/shadow.log` (the `source` field of the JSON record is `"shadow.log"`); link is null. In `--post=true` mode, link is the PR comment URL.

`both.json` shape — `coderabbit` and `reviewers` are present only when their respective wait flags fired:
```json
{
  "ai_router":  {"body": "...", "url": "...|null", "id": 12345},
  "coderabbit": {"body": "...", "url": "...", "id": 12346},
  "reviewers":  [{"user": "alice", "body": "...", "url": "...", "id": 12347, "at": "2026-..."}]
}
```

```markdown
## Shadow Review #<PR> — reviews are in
**AI Router ensemble** ([link or "(stdout only — not posted)"])
**CodeRabbit** ([link])                 ← omit if `coderabbit` key not in both.json
**Reviewers**: alice, bob ([links])     ← omit if `reviewers` array empty/absent

### Where they agree
- <bullets from the intersection: same file/line, same finding category>

### AI Router caught (others did not)
- <bullets, with file:line>

### Others caught (AI Router did not)
- <bullets, attributed: "CodeRabbit:", "alice:" — file:line>

### Conflicts
- <if one says ship and another flags critical, surface here>

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
# Use a per-run temp dir so concurrent invocations never clobber each other.
# After parsing the per-provider outputs, clean up the run dir — otherwise
# /tmp accumulates one dir per ensemble call (the shadow flow alone can leave
# dozens over a session).
RUN=$(mktemp -d "${TMPDIR:-/tmp}/ai-router-run-XXXXXX")
echo "$PROMPT" | bash "$SCRIPT" anthropic > "$RUN/claude.out"  2>"$RUN/claude.err"  &
echo "$PROMPT" | bash "$SCRIPT" openai    > "$RUN/gpt.out"     2>"$RUN/gpt.err"     &
echo "$PROMPT" | bash "$SCRIPT" gemini    > "$RUN/gemini.out"  2>"$RUN/gemini.err"  &
wait
# ... read $RUN/*.out, $RUN/*.err, synthesize ...
rm -rf "$RUN"
```

Stdout shape:

```text
<response text>
---USAGE---
{"input":N,"output":N,"provider":"...","model":"..."}
```

Exit codes: `0` ok | `2` not configured | `3` missing deps | `4` HTTP non-200 | `5` network/timeout | `6` 2xx with empty text (safety-blocked, token-capped, or error envelope returned as 2xx) — usage line still emitted so cost accounting works.

The prompt is piped on stdin and never appears on a command line — the auto-mode classifier sees a constant `bash …/call-provider.sh <provider>` invocation, which can be pre-authorized with a single `permissions.allow` rule per script.

### Required permissions.allow snippet

Add to `~/.claude/settings.json` `permissions.allow`:

```json
"Bash(bash ~/.claude/skills/ai-router/scripts/call-provider.sh:*)",
"Bash(bash ~/.claude/skills/ai-router/scripts/validate-key.sh:*)",
"Bash(bash ~/.claude/skills/ai-router/scripts/post-review.sh:*)",
"Bash(bash ~/.claude/skills/ai-router/scripts/shadow-spawn.sh:*)",
"Bash(bash ~/.claude/skills/ai-router/scripts/shadow-poll.sh:*)",
"Bash(python3 ~/.claude/skills/ai-router/scripts/format-diff.py:*)",
"Bash(python3 ~/.claude/skills/ai-router/scripts/verify-findings.py:*)",
"Bash(bash ~/.claude/skills/ai-router/scripts/post-inline.sh:*)"
```

Without these, `defaultMode: "auto"` will prompt on every call. (`format-diff.py` and `verify-findings.py` are read-only — no network, no writes; `post-inline.sh` posts to a PR, same trust model as `post-review.sh`.) (Allow-rule paths must match the literal command Claude invokes; if `~` doesn't expand in your Claude Code version, use `/Users/<you>/.claude/skills/ai-router/scripts/...`.)

### Model Override

To use a non-default model for one call: pass `--model <id>` after the provider. Model IDs must match `[A-Za-z0-9._-]+` (validated by the script).

### Error Handling

`call-provider.sh` writes errors to stderr with `<provider>: HTTP <code>` and the first 500 chars of the response body. Exit code distinguishes config (2), deps (3), HTTP (4), network (5), empty-2xx (6). For ensembles, treat non-zero exits per-provider — continue with the others and note the failure: "Gemini: unavailable (HTTP 429)" or "Gemini: empty response (safety-blocked or token-capped)" for exit 6.

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
