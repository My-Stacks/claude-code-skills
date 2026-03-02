# Claude Code Skills & Components

Reusable components for [Claude Code](https://docs.anthropic.com/en/docs/claude-code): skills, agents, commands, and more. Built for token efficiency, cross-model compatibility, and minimal friction.

## Components

| Component | Type | Version | What it does |
|-----------|------|---------|-------------|
| [linear](./.claude/skills/linear/) | Skill | 0.4.0 | Linear project management with session continuity. Buffered writes, board management, ticket creation, structured handoffs persisted to Linear. |
| [handoff](./.claude/skills/handoff/) | Skill | 2.1 | Session continuity via markdown files in git. Full handoffs, quick checkpoints, resume, status reports, and cross-tool project transfers. |
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
    │   └── handoff/
    │       └── SKILL.md
    ├── agents/
    │   └── .gitkeep
    └── commands/
        ├── commit.md
        ├── push.md
        ├── commit-push-pr.md
        └── update-skills.md
```

## Design Principles

These components are built around a few constraints that shape every decision.

**Token efficiency is a first-class concern.** Every instruction competes for context window space. Templates and formats are as lean as possible without sacrificing clarity. If removing a line wouldn't cause the LLM to make a mistake, the line gets cut.

**Cross-model compatibility.** Components use standard markdown with YAML frontmatter. No model-specific syntax or features. They should work in Claude Code, Cursor, Windsurf, or any tool that reads markdown skill files.

**Progressive disclosure.** Not everything loads at once. Reference files are loaded on demand. The agent gets what it needs for the current command, not the entire knowledge base.

## License

MIT
