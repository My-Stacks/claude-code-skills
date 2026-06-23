# Claude Code Skills & Components

Reusable components for [Claude Code](https://docs.anthropic.com/en/docs/claude-code): skills, agents, commands, and more. Built for token efficiency, cross-model compatibility, and minimal friction.

## Components

| Component | Type | Version | What it does |
|-----------|------|---------|-------------|
| [linear](./.claude/skills/linear/) | Skill | 0.5.1 | Linear project management with session continuity. Buffered writes, board management, ticket creation, structured handoffs persisted to Linear. Auto-maintains `.latest-status.md`. |
| [vault-backup](./.claude/skills/vault-backup/) | Skill | 1.0 | Save research, project outputs, and knowledge artifacts from any Claude Code workspace into a shared Obsidian knowledge vault. |
| [ai-router](./.claude/skills/ai-router/) | Skill | 1.8 | Route tasks to optimal model tiers and ensemble responses across Claude, GPT, and Gemini APIs. Grounded PR review: line-numbered diff + anti-hallucination rules, findings **verified against the diff** (hallucinated ones dropped), posted as **inline comments** with committable suggestions by default, **auto-resolves its own stale threads**, and a **persona-gated auto-fixer** — interactive (`--fix=propose\|auto`) and **always-on** via the shadow flow (`shadow-review --fix`), which fixes in an isolated `git worktree` so it never touches your checkout. Headless-safe with `--post-to-pr` and `/ai-router shadow-review`. Requires `curl`, `jq`, `python3`, and (for PR posting) `gh`. |
| [create-client-pdf](./.claude/skills/create-client-pdf/) | Skill | 1.2.1 | Convert a Markdown file with YAML frontmatter into a client-presentable PDF, branded for Stacklab or Stacklist. Requires Python + Playwright (see `INSTALL.md`). |
| [preflight](./.claude/skills/preflight/) | Skill | 5.0 | Pre-session safe-sync briefing for git repos: fast-forwards active branches to origin, flags stale ones, then reports local state, open PRs, and where new work should branch from. Only safe, non-destructive writes (ff-only sync); config is stored per-user outside the repo and the skill makes zero commits. Requires `git`; PR features require authenticated `gh`. |
| [prod-readiness-audit](./.claude/skills/prod-readiness-audit/) | Skill | 1.1 | Read-only audit of any codebase across four buckets — infra/security/compliance, engineering, design/UX, and product analytics — returning a red/yellow/green scorecard and the single highest-priority fix. Accepts an optional path argument to scope to a subdirectory. |
| [pull-and-sync](./.claude/commands/pull-and-sync.md) | Command | 1.0 | Sync working branch with latest from default branch using merge --no-ff. |
| [commit](./.claude/commands/commit.md) | Command | 1.0 | Smart commit with conventional format, staged diffs, and hook compliance. |
| [push](./.claude/commands/push.md) | Command | 1.0 | Push with safety checks, branch protection, and tracking setup. |
| [commit-push-pr](./.claude/commands/commit-push-pr.md) | Command | 1.0 | Full pipeline: commit, push, and create a PR via gh CLI. |
| [update-skills](./.claude/commands/update-skills.md) | Command | 1.0 | Check installed Stacklist components for available updates. |

## Install

Copy a component to your Claude Code config directory:

```bash
# Install a skill
cp -r .claude/skills/linear/ ~/.claude/skills/linear/

# Install an agent
cp .claude/agents/<name>.md ~/.claude/agents/

# Install a command
cp .claude/commands/commit.md ~/.claude/commands/
```

Then reference skills in your project's CLAUDE.md:

```markdown
## Skills
Load skills from ~/.claude/skills/ as needed.
```

## Check for Updates

Each component has a version in its frontmatter. Compare against `versions.yaml` in this repo:

```bash
curl -s https://raw.githubusercontent.com/stacklist/claude-code-skills/main/versions.yaml
```

Or check locally if you've cloned the repo:

```bash
cat versions.yaml
```

## Repo Structure

```
claude-code-skills/
├── README.md
├── CLAUDE.md
├── versions.yaml
└── .claude/
    ├── skills/
    │   ├── linear/
    │   │   ├── SKILL.md
    │   │   └── REFERENCE.md
    │   ├── vault-backup/
    │   │   └── SKILL.md
    │   ├── ai-router/
    │   │   ├── SKILL.md
    │   │   ├── REFERENCE.md
    │   │   └── scripts/        # provider dispatcher + shadow-review helpers
    ├── agents/
    │   └── .gitkeep
    └── commands/
        ├── commit.md
        ├── push.md
        ├── commit-push-pr.md
        ├── pull-and-sync.md
        ├── update-skills.md
        └── vault-backup.md
```

## Design Principles

These components are built around a few constraints that shape every decision.

**Token efficiency is a first-class concern.** Every instruction competes for context window space. Templates and formats are as lean as possible without sacrificing clarity. If removing a line wouldn't cause the LLM to make a mistake, the line gets cut.

**Cross-model compatibility.** Components use standard markdown with YAML frontmatter. No model-specific syntax or features. They should work in Claude Code, Cursor, Windsurf, or any tool that reads markdown skill files.

**Progressive disclosure.** Not everything loads at once. Reference files are loaded on demand. The agent gets what it needs for the current command, not the entire knowledge base.

## Upgrade Notes

### Handoff retired

The `handoff` skill has been retired. Session continuity is now part of the `linear` skill via its auto-maintained `.latest-status.md`. If you previously installed `handoff` globally, remove it:

```bash
rm -rf ~/.claude/skills/handoff/
```

### AI Router v1.8

**Always-on auto-fix in the shadow flow.** `shadow-review --fix` runs the Phase 3 auto-fixer on every PR in the background (the `guided` persona's default). Because the shadow shares your working directory, it does **not** fix in place: `shadow-runner.sh` checks out the PR's head branch in an isolated detached `git worktree`, runs `review --fix=auto` there, and pushes `HEAD` to the PR branch (`fix-findings.sh` gained `AI_ROUTER_FIX_PUSH_REF` for the detached-push case). Your checkout and current branch are never touched; the worktree is removed on every exit. Auto-fix is skipped (review-only) for fork PRs or when `AI_ROUTER_FIX_VERIFY_CMD` is unset. Verified in a sandbox: worktree isolate/cleanup leaves the user's branch + uncommitted work untouched; detached-worktree fix commits and pushes to the PR branch. No new allow-rules (shadow scripts already allowlisted). This completes the CodeRabbit replacement: grounded, verified, inline, self-resolving, and self-fixing on every PR.

To upgrade:

```bash
cp -r .claude/skills/ai-router/ ~/.claude/skills/ai-router/
```

### AI Router v1.7

Phase 3: **the auto-fixer.** Opt-in, persona-gated application of findings' suggestions. `apply-fix.py` replaces lines only if their current content still matches the grounded `shown_code` (so a shifted/stale file or wrong branch can't be corrupted); `fix-findings.sh` orchestrates with guardrails: refuses on main/master, applies bottom-up per file, and runs as **`propose`** (apply to the working tree, show diff, commit nothing — developer default) or **`auto`** (apply only the conservative allowlist — confirmed + suggestion + safe category + non-sensitive path + small — run `$AI_ROUTER_FIX_VERIFY_CMD`, then commit + push + resolve threads on pass, or revert on fail; never pushes untested — guided default). Set posture via `review_persona` in config (`developer`/`guided`) or `--fix=<report|suggest|propose|auto>` per run. Verified end-to-end in a sandbox repo (propose, auto-pass commit+push, auto-fail revert, allowlist/denylist exclusion, main guardrail). Shadow (always-on) auto-fix is the next step — it needs `git worktree` isolation so it can't touch your checked-out tree.

To upgrade:

```bash
cp -r .claude/skills/ai-router/ ~/.claude/skills/ai-router/
```

Then add the new allow-rules to `~/.claude/settings.json` `permissions.allow` (auto-mode users). Note these can edit files and, in `--fix=auto`, commit + push the current branch (never main) — review the guardrails before allowlisting on a shared machine:

```json
"Bash(python3 ~/.claude/skills/ai-router/scripts/apply-fix.py:*)",
"Bash(bash ~/.claude/skills/ai-router/scripts/fix-findings.sh:*)"
```

### AI Router v1.6

Phase 2.5: **ai-router resolves its own inline threads** (CodeRabbit-style hygiene). Every inline comment now carries a hidden `<!-- ai-router-finding -->` marker. `scripts/resolve-threads.sh` (GraphQL — REST can't resolve threads) resolves ai-router's own threads, never a human's: by default only the **outdated** ones (the code they anchor to changed, so the finding was almost certainly addressed), or all of them with `--all`. The review flow runs the outdated pass automatically after an inline post, so stale threads don't pile up across pushes; `/ai-router resolve <pr> [--all]` does it manually. Verified live (post marked thread → resolve → gone). Sets up Phase 3, where the fixer resolves each thread it fixes.

To upgrade:

```bash
cp -r .claude/skills/ai-router/ ~/.claude/skills/ai-router/
```

Then add the new allow-rule to `~/.claude/settings.json` `permissions.allow` (auto-mode users):

```json
"Bash(bash ~/.claude/skills/ai-router/scripts/resolve-threads.sh:*)"
```

### AI Router v1.5

Phase 2 of the CodeRabbit replacement: **verified findings + inline comments.** After the ensemble reviews the grounded diff, every finding is checked against the diff the models actually saw (`scripts/verify-findings.py`): `confirmed` (all cited lines were in the diff), `partial`, or `unverified` (file/lines not in the diff — the usual hallucination signature). Unverified findings are demoted and never asserted as bugs. When a PR is given, grounded findings post as inline PR review comments at the real lines **by default** (`scripts/post-inline.sh`), with a committable ```suggestion block where a provider gave safe replacement code; ungrounded findings go in the review body, never inline. Pass `--summary-only` to post a single summary comment instead. Verifying against the diff (not the working tree) keeps it correct even when reviewing a PR number from another branch. `shadow-review --post` also posts inline by default now; its poller matches ai-router's post by `run-id` across both the issue-comments and pulls/reviews endpoints, so it detects an inline review or a summary comment either way. Config schema unchanged — back-compat.

To upgrade:

```bash
cp -r .claude/skills/ai-router/ ~/.claude/skills/ai-router/
```

Then add the two new allow-rules to `~/.claude/settings.json` `permissions.allow` (auto-mode users):

```json
"Bash(python3 ~/.claude/skills/ai-router/scripts/verify-findings.py:*)",
"Bash(bash ~/.claude/skills/ai-router/scripts/post-inline.sh:*)"
```

Roadmap: Phase 3 — an opt-in `fix-findings` step that *applies* suggestions, persona-gated (developers get suggestions; a `guided` persona gets a guarded auto-fixer on a conservative allowlist, never main, tests must pass).

### AI Router v1.4

Grounded PR review — the first phase of replacing CodeRabbit with ai-router's own ensemble. `/ai-router review` now reformats the diff before any model sees it: local diffs are fetched with expanded context (`git diff -U8`) and piped through a new read-only pre-processor, `scripts/format-diff.py`, which splits each hunk into a line-numbered `__new hunk__` section and an `__old hunk__` section. Models cite **real** line numbers instead of inventing them, and the review prompt adds explicit anti-hallucination rules (don't flag names defined elsewhere, don't claim breakage you can't see, prefer not-reporting over guessing). Findings carry a real `file:line` and are deduped across providers by location. Technique adapted from [PR-Agent](https://github.com/The-PR-Agent/pr-agent) (Apache-2.0); algorithms reimplemented, no prompt text copied. Config schema unchanged — back-compat.

To upgrade:

```bash
cp -r .claude/skills/ai-router/ ~/.claude/skills/ai-router/
```

Then add the new allow-rule to `~/.claude/settings.json` `permissions.allow` (auto-mode users):

```json
"Bash(python3 ~/.claude/skills/ai-router/scripts/format-diff.py:*)"
```

Roadmap: Phase 2 — a deterministic repo-grounded verify pass + inline `suggestion` comments; Phase 3 — an opt-in `fix-findings` step, persona-gated (devs get suggestions, a `guided` persona gets a guarded auto-fixer on a conservative allowlist).

### AI Router v1.3

External API calls moved out of inline `python3` heredocs and into checked-in helper scripts under `.claude/skills/ai-router/scripts/`. This unblocks `permissions.defaultMode: "auto"` users (Claude Code's auto-mode classifier was denying the heredocs as "exfiltration to untrusted endpoint"). Adds `/ai-router review --post-to-pr <#>` and a new `/ai-router shadow-review` that spawns a headless background review and polls the PR for both ai-router and CodeRabbit comments. Config schema (`~/.orchestrator-config.json`) is unchanged — fully back-compat.

To upgrade:

```bash
cp -r .claude/skills/ai-router/ ~/.claude/skills/ai-router/
```

Then add the five script allow-rules to `~/.claude/settings.json` `permissions.allow` (see REFERENCE.md → "Pre-authorizing the scripts").

### Linear v0.5.1

Fixes a frontmatter parsing bug. The `## Version Check` section was placed before the YAML frontmatter, preventing the parser from reading `trigger`, `description`, and other metadata. This caused `/linear update` to run a version check instead of posting a project status update, and the skill to appear as "Version Check" in the skill list.

To upgrade:

```bash
cp -r .claude/skills/linear/ ~/.claude/skills/linear/
```

### Linear v0.5.0

The linear skill now auto-maintains `.latest-status.md` at project root, providing cross-session resume context without a separate command.

- **Auto-updates:** `.latest-status.md` updates on plan start and plan completion when the linear skill is active
- **Resume priority:** `/linear resume` reads `.latest-status.md` first, then `.linear/last-handoff.md` for expanded detail, then falls back to Linear API
- **Three handoff destinations:** `.latest-status.md` (universal, 100-300 words), `.linear/last-handoff.md` (full detail), Linear project update (lean, 150-300 words)

To upgrade:

```bash
cp -r .claude/skills/linear/ ~/.claude/skills/linear/
```

## License

MIT
