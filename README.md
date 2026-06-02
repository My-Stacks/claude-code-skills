# Claude Code Skills & Components

Reusable components for [Claude Code](https://docs.anthropic.com/en/docs/claude-code): skills, agents, commands, and more. Built for token efficiency, cross-model compatibility, and minimal friction.

## Components

| Component | Type | Version | What it does |
|-----------|------|---------|-------------|
| [linear](./.claude/skills/linear/) | Skill | 0.5.1 | Linear project management with session continuity. Buffered writes, board management, ticket creation, structured handoffs persisted to Linear. Auto-maintains `.latest-status.md`. |
| [vault-backup](./.claude/skills/vault-backup/) | Skill | 1.0 | Save research, project outputs, and knowledge artifacts from any Claude Code workspace into a shared Obsidian knowledge vault. |
| [ai-router](./.claude/skills/ai-router/) | Skill | 1.3 | Route tasks to optimal model tiers and ensemble responses across Claude, GPT, and Gemini APIs. Headless-safe with `--post-to-pr` and `/ai-router shadow-review` (background review + PR-comment polling). Requires `curl`, `jq`, `python3`, and (for PR posting) `gh`. |
| [create-client-pdf](./.claude/skills/create-client-pdf/) | Skill | 1.2.1 | Convert a Markdown file with YAML frontmatter into a client-presentable PDF, branded for Stacklab or Stacklist. Requires Python + Playwright (see `INSTALL.md`). |
| [preflight](./.claude/skills/preflight/) | Skill | 4.0 | Pre-session safe-sync briefing for git repos: fast-forwards active branches to origin, flags stale ones, then reports local state, open PRs, and where new work should branch from. Only safe, non-destructive writes (ff-only sync + config setup), each narrated; never rewrites history. |
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
