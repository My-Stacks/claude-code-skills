---
name: update-skills
version: "1.0"
description: "Check installed Stacklist components for available updates."
allowed-tools: Bash, Read, Glob, Grep
---

# /update-skills — Check for Updates

Read-only — never modifies files.

## 1. Fetch remote versions

```bash
curl -s https://raw.githubusercontent.com/My-Stacks/claude-code-skills/main/versions.yaml
```

If fetch fails, report error and stop.

## 2. Scan installed components

Check for files with YAML frontmatter containing a `version` field:

- `~/.claude/skills/*/SKILL.md` — user-global skills
- `~/.claude/commands/*.md` — user-global commands
- `.claude/skills/*/SKILL.md` — project skills
- `.claude/commands/*.md` — project commands

## 3. Compare and report

Match installed `name`/`version` against remote `versions.yaml`.

```
| Component | Type    | Installed | Latest | Status           |
|-----------|---------|-----------|--------|------------------|
| handoff   | skill   | 2.0       | 2.1    | Update available |
| linear    | skill   | 0.4.0     | 0.4.0  | Up to date       |
| commit    | command | 1.0       | 1.0    | Up to date       |
```

## 4. Show update commands

For outdated components:

```bash
curl -s https://raw.githubusercontent.com/My-Stacks/claude-code-skills/main/.claude/skills/handoff/SKILL.md > ~/.claude/skills/handoff/SKILL.md
```

## Important

- Read-only — never modify installed files
- Graceful failures — skip files with no frontmatter/version
- Check both global (`~/.claude/`) and project-local (`.claude/`) installations
