---
name: ship-pr
description: One-command PR pass. Ensemble review + repo-grounded triage + architecture pass + Sonar, then either posts the verified findings as PR comments or fixes them and pushes. Stops before merge.
disable-model-invocation: true
argument-hint: "[pr-number] [comment|fix]"
---

# Ship PR

Input: `$ARGUMENTS`
- PR number: first number in the args. If none, use the current branch's PR (`gh pr view --json number -q .number`); if there is none, say so and stop.
- Mode: `comment` or `fix`. If neither is given, run steps 1-4, then ask "Comment or fix?" and wait.

## 1. Review + triage

1. Review the diff. If the `ai-router` skill is installed, run `/ai-router review <pr>` with NO posting (ensemble of models); otherwise review it yourself.
2. Verify every finding against the real repo before trusting it: read the cited file and the code around it, check what the claim depends on (imported helpers, column types, existing guards), and decide whether this PR introduced it.
3. Classify each finding with evidence: **REAL** (verified bug: concrete trigger and file:line), **NOT A BUG** (design choice or pre-existing; say why), **FALSE POSITIVE** (state the repo fact that disproves it). A finding without a concrete, repo-verified trigger is not REAL.

## 2. Architecture pass

Read the PR diff and the surrounding code. Check it against this codebase's conventions:
- Logic that should be extracted into smaller reusable components, services, utils or hooks.
- Something re-implemented that already exists in the repo (search for it; name the existing file).
- Patterns that differ from how neighboring code does the same thing.

Only report items you can point at with an existing file:line to reuse or a concrete extraction. Label them ARCH. No style nits.

## 3. Sonar

Check `gh pr checks <pr>` and the PR comments for a SonarCloud/SonarQube result. If issues are listed, triage them the same way (REAL vs noise). If there is no Sonar result, say "no Sonar result on this PR" and move on. Don't guess.

## 4. Summary (always shown)

One table: finding | bucket (REAL / ARCH / SONAR / NOT A BUG / FALSE POSITIVE) | file:line | one-line reason. Then the fix plan for REAL + ARCH + SONAR items, ordered by severity.

## 5a. Mode `comment`

Post the REAL, ARCH and SONAR items to the PR as ONE review with inline comments at their lines (`gh api repos/{owner}/{repo}/pulls/<pr>/reviews` with `event: COMMENT` and a `comments` array; items not on a diff line go in the review body). Each comment: the problem, the trigger, the suggested fix. Plain and short, no AI boilerplate, no "Great PR!".

Show the exact review draft first and wait for "post" (it goes out under the user's GitHub account). Never request changes or approve. NOT A BUG / FALSE POSITIVE items are never posted.

## 5b. Mode `fix`

1. Confirm you are on the PR's head branch (`gh pr view <pr> --json headRefName`), never main/master/dev. Check out the branch if needed; if the tree is dirty, stop and say so.
2. Apply fixes for REAL, ARCH and SONAR items. Smallest change that fixes each; no unrelated refactors.
3. Run `/verify` (the repo's safe Verify command from the Stacklist registry, plus screenshots for UI changes).
4. If `/verify` does not pass: stop, show the output, don't push.
5. Commit (one commit, message lists what was fixed) and push to the PR branch. No force push.
6. Report: what was fixed, what was deliberately left (with reason), test results.

## 6. Stop

End with: "Merge?" Do not merge, deploy, or resolve review threads without an explicit yes.
