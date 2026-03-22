# Claude Code Skills & Components

Reusable Claude Code components for the Stacklist ecosystem: skills, agents, commands, and more.

## Repo Structure

```
.claude/
  skills/       — SKILL.md files (mirrors ~/.claude/skills/)
  agents/       — Agent definitions (mirrors ~/.claude/agents/)
  commands/     — Command .md files (mirrors ~/.claude/commands/)
versions.yaml   — Version registry for all components
```

## Conventions

### Adding a skill
1. Create `.claude/skills/<name>/SKILL.md` with YAML frontmatter (`name`, `version`, `description`, `trigger`).
2. Optional: add `REFERENCE.md` for on-demand reference material.
3. Add an entry to `versions.yaml`.
4. Update `README.md` with a row in the component table.

### Adding an agent
1. Create `.claude/agents/<name>.md` with agent definition.
2. Add an entry to `versions.yaml`.
3. Update `README.md`.

### Adding a command
1. Create `.claude/commands/<name>.md` with YAML frontmatter (`name`, `version`, `description`).
2. Add an entry to `versions.yaml`.
3. Update `README.md` with a row in the component table.

## Design Principles

- **Token efficiency.** Every instruction competes for context window space. Keep formats lean. If removing a line wouldn't cause the LLM to make a mistake, cut it.
- **Cross-model compatibility.** Standard markdown + YAML frontmatter. No model-specific syntax. Works in Claude Code, Cursor, Windsurf, or any tool that reads markdown.
- **Progressive disclosure.** Reference files load on demand. Not everything loads at once.

## Version Tracking

All component versions are tracked in `versions.yaml`. Each SKILL.md/agent/command has a version in its frontmatter that should match.
