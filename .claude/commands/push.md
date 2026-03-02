---
name: push
version: "1.0"
description: "Push with safety checks, branch protection, and tracking setup."
allowed-tools: Bash, Read, Glob, Grep
---

# /push — Push to Remote

## 1. Gather context

Run in parallel:

- `git branch --show-current` — current branch
- `git rev-parse --abbrev-ref @{upstream} 2>/dev/null` — tracking branch
- `git log @{upstream}..HEAD --oneline 2>/dev/null` — unpushed commits

## 2. Safety checks

- If on `main`/`master`, warn and confirm. Never force push to these.
- If no upstream, will use `git push -u origin <branch>`.
- Never force push unless user explicitly asks (warn about risks).

## 3. Preview

Show branch (`local → remote`), commits to push, whether `-u` needed. Wait for approval.

## 4. Push

```bash
git push                          # has upstream
git push -u origin <branch>      # first push
```

Report success or failure.

## Important

- Never force push to main/master — refuse even if asked
- Auto `-u` when no tracking branch exists
- Show commits before pushing
