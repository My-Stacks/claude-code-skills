---
name: commit
version: "1.0"
description: "Smart commit with conventional format, staged diffs, and hook compliance."
allowed-tools: Bash, Read, Glob, Grep
---

# /commit — Smart Git Commit

## 1. Gather context

Run in parallel:

- `git status` — changed/untracked files
- `git branch --show-current` — current branch
- `git diff` and `git diff --cached` — all changes
- `git log --oneline -5` — recent commit style

## 2. Branch check

If on `main`, `master`, or `dev`: warn and offer to create a feature branch.

- `fix/<desc>`, `feature/<desc>`, `refactor/<desc>`, `chore/<desc>`, `docs/<desc>`
- `git checkout -b <type>/<short-description>`

## 3. Analyze and stage

- Stage specific files by name — never `git add -A` or `git add .`
- Skip `.env`, credentials, tokens, private keys
- Determine commit type: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `build`, `ci`, `perf`, `style`
- Determine optional scope from file paths

## 4. Draft commit message

```
type(scope): summary

Optional body explaining *why*, not *what*.

Co-Authored-By: Claude <noreply@anthropic.com>
```

Body only when the "why" isn't obvious. No body for trivial changes.

## 5. Preview and confirm

Show staged files + full commit message. Wait for explicit approval.

## 6. Commit

```bash
git commit -m "$(cat <<'EOF'
type(scope): summary

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

If hooks fail, fix the issue and create a **new** commit (never amend).

## 7. Confirm

Show `git log --oneline -1`.

## Important

- Never `--no-verify` — let hooks run
- Never stage secrets
- Always use conventional commit format
- Always use HEREDOC for commit messages
