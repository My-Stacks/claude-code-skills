---
name: copilot-scoring
version: "1.0"
description: "Evaluate a project's suitability for GitHub Copilot code review. Standardized rubric with weighted scoring across 5 dimensions."
trigger: "When the user runs /copilot-scoring or asks to evaluate a project for Copilot code review suitability."
---

## Version Check
To check for updates: `curl -s https://raw.githubusercontent.com/My-Stacks/claude-code-skills/refs/heads/main/versions.yaml`
Compare against this file's version in frontmatter.

# Copilot Scoring

Analyze the current project and score how effectively GitHub Copilot code review will perform on its PRs. Produces a standardized suitability score with a routing recommendation.

## Commands

| Command | Action |
|---------|--------|
| `/copilot-scoring` | Score the current project |
| `/copilot-scoring <PR-number>` | Score a specific PR (uses `gh pr diff`) |

---

## Procedure

### Project-level scoring (no PR number)

1. **Sample the codebase.** Read the project structure, key source files, config files, and any knowledge/prompt files. Use `git log --oneline -20` to understand typical change patterns.
2. **Score each dimension** using the rubric below.
3. **Compute the composite score** and generate the output.

### PR-level scoring (PR number provided)

1. **Fetch the diff.** `gh pr diff <number> --stat` for summary, `gh pr diff <number>` for full diff.
2. **Classify changed files** by type (code, test, config, docs, prompts/knowledge).
3. **Score each dimension** against the actual diff.
4. **Compute the composite score** and generate the output.

---

## Scoring Rubric

### 1. Code Density (weight: 25%)

What percentage of the codebase (or diff) is reviewable executable code?

| Score | Criteria |
|-------|----------|
| 8-10 | 80%+ executable code (.py, .ts, .js, .go, .rs, etc.) |
| 5-7 | 50-80% code, rest is config/docs |
| 2-4 | 20-50% code, heavy config/YAML/markdown |
| 1 | Mostly prose, prompts, knowledge files, or config |

### 2. Pattern Familiarity (weight: 20%)

Does the code use well-known, widely-documented patterns?

| Score | Criteria |
|-------|----------|
| 8-10 | Standard CRUD, REST/GraphQL endpoints, common framework patterns, ORM usage |
| 5-7 | Mix of standard patterns and some custom logic |
| 2-4 | Custom DSLs, novel abstractions, complex state machines |
| 1 | Prompt engineering, custom scoring rubrics, domain-specific algorithms |

### 3. Change Locality (weight: 20%)

How self-contained are typical changes? Can files be reviewed independently?

| Score | Criteria |
|-------|----------|
| 8-10 | Changes typically isolated to 1-3 files, minimal cross-file coupling |
| 5-7 | Moderate coupling — shared models/types across a few files |
| 2-4 | High coupling — changes in file A only make sense given file B, shared state |
| 1 | Deeply interconnected — event chains, cross-file contracts, distributed state |

### 4. Defect Surface (weight: 20%)

Does the codebase have the *types* of bugs Copilot catches well?

| Score | Criteria |
|-------|----------|
| 8-10 | Error handling, null checks, type mismatches, SQL/injection risks, auth code |
| 5-7 | Mix of pattern-catchable bugs and business logic correctness |
| 2-4 | Mostly business logic, architectural decisions, data pipeline correctness |
| 1 | Correctness depends on domain knowledge, external system behavior, or UX |

### 5. Context Dependency (weight: 15%)

How much background knowledge is needed to review meaningfully?

| Score | Criteria |
|-------|----------|
| 8-10 | Self-explanatory code — "does this function handle edge cases?" |
| 5-7 | Some domain context needed but mostly readable |
| 2-4 | Requires understanding business rules, prior decisions, or system design |
| 1 | Requires CTO feedback context, design docs, or institutional knowledge |

**Note:** This dimension is inverted in the formula — high context dependency *reduces* the score.

---

## Formula

```
composite = (
    code_density       * 0.25 +
    pattern_familiar   * 0.20 +
    change_locality    * 0.20 +
    defect_surface     * 0.20 +
    (10 - context_dep) * 0.15
)
```

---

## Output Format

```markdown
## Copilot Review Suitability: X.X / 10

| Dimension | Score | Rationale |
|-----------|-------|-----------|
| Code Density | ?/10 | ... |
| Pattern Familiarity | ?/10 | ... |
| Change Locality | ?/10 | ... |
| Defect Surface | ?/10 | ... |
| Context Dependency | ?/10 | ... |

### Copilot Will Catch
- [Specific issue types Copilot's pattern-matching will flag in this project]

### Copilot Will Miss
- [Specific issue types requiring domain knowledge, cross-file reasoning, or semantic judgment]

### Verdict
**Route:** [One of the options below] — [reasoning]
```

---

## Routing

| Route | When | Example |
|-------|------|---------|
| **Copilot-only** | Composite >= 7.5 | Dependency bumps, standard CRUD endpoints, style refactors |
| **Copilot-first, human verifies** | Composite 5.0-7.4 | New features with some domain logic — Copilot catches code quality, human validates approach |
| **Human-only** | Composite < 5.0 | Architecture changes, knowledge files, system prompt updates, complex domain logic |
| **Claude-review** | High cross-file coupling + domain depth | Multi-file refactors where cross-file consistency is the primary concern |

---

## Calibration

After Copilot reviews a PR that was scored, record the result:

```yaml
# .copilot-eval/history.yaml
- pr: 4
  project: growy
  predicted_score: 4.5
  copilot_useful_findings: 3
  copilot_false_positives: 1
  human_caught_missed: 2
  routing_correct: true
```

Over time, compare predictions against actuals to tune dimension weights.
