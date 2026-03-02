---
name: commit-push-pr
version: "1.0"
description: "Full pipeline: commit, push, and create a PR via gh CLI."
allowed-tools: Bash, Read, Glob, Grep
---

# /commit-push-pr — Full Pipeline

Commit → push → PR in one flow. Requires `gh` CLI (`gh auth status`).

## 1. Gather context

Run in parallel: `git status`, `git branch --show-current`, `git diff`, `git diff --cached`, `git log --oneline -5`.

## 2. Branch check

If on `main`, `master`, or `dev`, create a feature branch:

- `fix/<desc>`, `feature/<desc>`, `refactor/<desc>`, `chore/<desc>`, `docs/<desc>`
- `git checkout -b <type>/<short-description>`
- Never commit directly to protected branches in this pipeline.

## 3. Stage and commit

Stage all changes: `git add .` (exclude `.env`, credentials, tokens, private keys first).

Draft a conventional commit message:

```
type(scope): summary

Optional body explaining why.

Co-Authored-By: Claude <noreply@anthropic.com>
```

Preview staged files + message. Wait for approval. Commit (never `--no-verify`). If hooks fail, fix and create a new commit.

## 4. Push

```bash
git push -u origin <branch>      # first push
git push                          # has upstream
```

## 5. Create PR

Detect base branch: `gh repo view --json defaultBranchRef -q '.defaultBranchRef.name'`

Gather full branch context: `git log <base>..HEAD --oneline` and `git diff <base>...HEAD`.

- **Title:** Under 72 chars, describes the change
- **Body:**
  ```markdown
  ## Summary
  <1-3 bullets covering all commits>

  ## Test plan
  - [ ] <verification steps>

  🤖 Generated with [Claude Code](https://claude.com/claude-code)
  ```

Preview title + body. Wait for approval.

```bash
gh pr create --title "..." --body "$(cat <<'EOF'
...
EOF
)"
```

Return the PR URL.

## Important

- Self-contained — does not call other commands
- Never `--no-verify` — hooks run as intended
- Never force push unless explicitly asked
- PR covers all branch commits, not just the latest
