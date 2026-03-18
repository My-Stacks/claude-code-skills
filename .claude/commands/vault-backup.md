Save the current work to the shared Obsidian knowledge vault using the Vault Backup skill.

Read the Vault Backup SKILL.md and follow its full workflow:

1. Check for config at ~/.vault-backup-config.json. If missing, run first-time setup.
2. Read the vault's current top-level folder structure.
3. Ask which top-level folder this should go under.
4. Ask what output type: context, drafts, synthesis, or final.
5. Confirm the target path.
6. Write the file(s) with proper YAML frontmatter.
7. Git commit (do not push).

If no specific content is referenced, ask what should be saved from this session.
