# Claude Code Skills

A collection of skills for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that optimize AI-assisted development workflows. Each skill is a structured SKILL.md file that teaches Claude specific capabilities: session continuity, project management, instruction optimization.

Skills are designed for token efficiency, cross-model compatibility, and minimal friction.

## Skills

| Skill | Version | What it does |
|-------|---------|-------------|
| [linear](./linear/) | 0.4.0 | Linear project management with session continuity. Buffered writes, board management, ticket creation, structured handoffs persisted to Linear. |
| [handoff](./handoff/) | 2.1 | Session continuity via markdown files in git. Full handoffs, quick checkpoints, resume, status reports, and cross-tool project transfers. |


## Install

Copy a skill folder to your Claude Code skills directory:

```bash
# Single skill
cp -r linear/ ~/.claude/skills/linear/

# Exclude dev artifacts (research, changelogs, prompts)
rsync -av --exclude='dev/' linear/ ~/.claude/skills/linear/
```

Then reference it in your project's CLAUDE.md:

```markdown
## Skills
Load skills from ~/.claude/skills/ as needed.
```

## Check for Updates

Each SKILL.md has a version in its frontmatter. Compare against `versions.yaml` in this repo:

```bash
curl -s https://raw.githubusercontent.com/stacklist/claude-code-skills/main/versions.yaml
```

Or just check locally if you've cloned the repo:

```bash
cat versions.yaml
```

## Repo Structure

```
claude-code-skills/
├── README.md
├── versions.yaml
├── linear/
│   ├── SKILL.md              ← Installed
│   ├── REFERENCE.md          ← Installed (loaded on demand by SKILL.md)
│   └── dev/                  ← Not installed
│       ├── CHANGELOG.md
│       └── research/
├── handoff/
│   ├── SKILL.md
│   └── dev/
│       └── CHANGELOG.md
└── claude-md-optimizer/
    ├── SKILL.md
    └── dev/
        └── CHANGELOG.md
```

Everything outside `dev/` is the installable skill. Everything inside `dev/` is how the skill was built: research, changelogs, cross-model prompts, iteration notes.

## Design Principles

These skills are built around a few constraints that shape every decision.

**Token efficiency is a first-class concern.** Every instruction competes for context window space. Templates and formats are as lean as possible without sacrificing clarity. If removing a line wouldn't cause the LLM to make a mistake, the line gets cut.

**Cross-model compatibility.** Skills use standard markdown with YAML frontmatter. No model-specific syntax or features. They should work in Claude Code, Cursor, Windsurf, or any tool that reads markdown skill files.

**Progressive disclosure.** Not everything loads at once. Reference files are loaded on demand. Dev artifacts stay out of the installed skill. The agent gets what it needs for the current command, not the entire knowledge base.

## License

MIT
