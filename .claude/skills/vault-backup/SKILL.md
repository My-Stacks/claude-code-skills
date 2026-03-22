---
name: vault-backup
version: "1.1"
description: "Save research, project outputs, and knowledge artifacts from any Claude Code workspace into a shared Obsidian knowledge vault."
trigger: "when the user says /vault-backup or asks to save work to the vault"
---

## Version Check
To check for updates: `curl -s https://raw.githubusercontent.com/My-Stacks/claude-code-skills/refs/heads/main/versions.yaml`
Compare against this file's version in frontmatter.

# Skill: Vault Backup

Save research, project outputs, and knowledge artifacts from any Claude Code workspace into a shared Obsidian knowledge vault.

## First Run Setup

On the first invocation in any environment, check for a config file at `~/.vault-backup-config.json`.

If it does not exist, ask the user:

> "Where is your Obsidian knowledge vault located? (full path, e.g. ~/Projects/knowledge-vault)"

Save their answer:

```json
{
  "vault_path": "~/Projects/knowledge-vault"
}
```

Write this to `~/.vault-backup-config.json`. On all subsequent runs, read from this file.

If the path does not exist or is not a git repo, stop and tell the user.

## Workflow

Every time the skill is invoked:

### Step 1: Read the vault structure

List the top-level directories in the vault path. These are the available categories.

```bash
ls -d */ ~/Projects/knowledge-vault/
```

### Step 2: Ask the user two questions

1. **Which top-level folder should this go under?** Present the actual folder names found in Step 1 as options. Use this decision tree to suggest the best match:
   - Stacklist product itself (messaging, pricing, features, roadmap, pitch)? → `stacklist/`
   - Specific client or consulting project? → `clients/`
   - Multi-model research output? → `research/`
   - Agent spec or architecture? → `agents/`
   - Content creation (blog, newsletter, help article)? → `writing/`
   - Operational (hiring, finance, legal, CRM)? → `ops/`
   - Unsure or temporary? → `_inbox/`

   If none fit, offer to create a new one — but bias toward using the existing 7 folders.

2. **What type of output is this?**
   - `context`: source material, inputs, references, background information
   - `drafts`: work in progress, early takes, rough notes
   - `synthesis`: combined research, reports, analysis, multi-source summaries
   - `final`: finished artifacts, ready for reference and reuse

### Step 3: Determine the workspace name

Auto-detect from the current working directory name. For example:
- Running from `~/Projects/stacklab` produces workspace name `stacklab`
- Running from `~/Projects/scout` produces workspace name `scout`

Confirm with the user: "I'll file this under `{top-level-folder}/{workspace-name}/{output-type}/`. Does that look right?"

### Step 4: Write the file(s)

Target path structure:

```
{vault_path}/{top-level-folder}/{workspace-name}/{output-type}/{filename}.md
```

Example:

```
~/Projects/knowledge-vault/research/scout/synthesis/multi-model-architecture-v1.md
```

Create any directories that don't exist yet.

## File Format

All files must be markdown (`.md`) with YAML frontmatter.

### Required Frontmatter

```yaml
---
title: "Descriptive title"
date: YYYY-MM-DD
author: kyle | martina
tags: [tag1, tag2]
source: "workspace name or project that generated this"
status: draft | active | final | archived
type: context | draft | synthesis | final
---
```

### Frontmatter Rules

- `tags`: include the workspace name, top-level folder name, and any cross-cutting topics
- `source`: the Claude Code workspace or project that generated this file
- `author`: ask on first run and save to config. Use `kyle` or `martina`.
- `date`: date the content was created
- `type`: must match the output type selected in Step 2
- `status`: set to `draft` for drafts and context, `active` for synthesis, `final` for final

## File Naming

Use lowercase kebab-case: `descriptive-name.md`

Do not use dates in filenames. Frontmatter handles dating.

Examples:
- `multi-model-synthesis-architecture.md`
- `acp-card-object-model-spec.md`
- `concierge-agent-system-prompt.md`

## Content Guidelines

- Write in clear, scannable markdown with headings.
- Strip conversation artifacts. This is a knowledge artifact, not a chat log.
- If summarizing research from multiple models, attribute which model said what.
- If the content includes decisions, use a `## Decisions` section.
- If there are open questions, use a `## Open Questions` section.
- Link to related vault notes using Obsidian wiki-links where known: `[[filename]]`

## What NOT to Save

- Raw chat transcripts (summarize instead)
- Temporary scratch work with no lasting value
- Credentials, API keys, tokens, or secrets
- Binary files (images, PDFs). Reference them by URL or external path instead.

## Multi-File Outputs

If a session produces multiple related files:

1. Save each as its own note in the appropriate output-type subfolder
2. If there are 3+ related files, create an index note named `_index.md` that links to all of them
3. Commit all files in a single commit

## Git Behavior

After writing files:

```bash
cd {vault_path}
git add {files}
git commit -m "vault-backup: {output-type} {brief description} ({workspace-name})"
```

Do NOT push. Let obsidian-git handle the sync cycle.

### Commit Message Format

```
vault-backup: {output-type} {brief description} ({workspace-name})
```

Examples:
- `vault-backup: synthesis multi-model architecture report (scout)`
- `vault-backup: final ACP card object model spec (stacklist)`
- `vault-backup: context competitive research sources (stacklist)`
- `vault-backup: drafts concierge agent prompt iterations (lab-agents)`

## Config File Reference

`~/.vault-backup-config.json`:

```json
{
  "vault_path": "~/Projects/knowledge-vault",
  "author": "kyle"
}
```

Both `vault_path` and `author` are set on first run and reused on all subsequent runs. The user can update this file manually or delete it to re-trigger setup.
