---
name: copilot-scoring
version: "1.0"
description: "Predict and evaluate GitHub Copilot code review effectiveness. Pre-review suitability/sufficiency scoring and post-review quality grading."
trigger: "When the user runs /copilot-scoring or asks to evaluate a project or PR for Copilot code review."
---

## Version Check
To check for updates: `curl -s https://raw.githubusercontent.com/My-Stacks/claude-code-skills/refs/heads/main/versions.yaml`
Compare against this file's version in frontmatter.

# Copilot Scoring

Two-phase evaluation of GitHub Copilot code review effectiveness.

- **Phase 1 — Predict:** Score a project or PR *before* Copilot reviews it. Should Copilot review this? Can it replace a human?
- **Phase 2 — Grade:** Score Copilot's *actual review* after it runs. Was it useful?

## Commands

| Command | Action |
|---------|--------|
| `/copilot-scoring` | Score the current project (Phase 1) |
| `/copilot-scoring <PR-number>` | Score a specific PR (Phase 1) |
| `/copilot-scoring grade <PR-number>` | Grade Copilot's actual review (Phase 2) |

---

# Phase 1: Pre-Review Prediction

Two scores, not one. A PR can score 8/10 suitability (Copilot will find useful things) but 3/10 sufficiency (Copilot can't replace a human).

## Procedure

### Project-level (no PR number)

1. Read project structure, key source files, config, and any knowledge/prompt files.
2. `git log --oneline -20` to understand typical change patterns.
3. Score each dimension below, compute both scores, generate output.

### PR-level (PR number provided)

1. `gh pr diff <number> --stat` for file summary, `gh pr diff <number>` for full diff.
2. Classify each changed file:

| Category | Extensions / Patterns | Copilot Strength |
|----------|----------------------|-----------------|
| Code | `.py`, `.ts`, `.js`, `.go`, `.rs` | Strong |
| Test | `test_*.py`, `*.test.ts`, `*_test.go` | Moderate |
| Config | `.yaml`, `.toml`, `.json`, `.env` | Weak (syntax only) |
| Docs/Prose | `.md`, `README` | Very weak |
| Prompts/Knowledge | `system-prompt/`, `knowledge/`, `CLAUDE.md` | None |

3. Score each dimension, compute both scores, generate output.

---

## Suitability Score (will Copilot find useful things?)

| Dimension | Weight | What to measure |
|-----------|--------|----------------|
| Code Density | 20% | `code_lines / total_lines`. ≥0.8 → 9-10, 0.5-0.8 → 5-8, <0.5 → 1-4 |
| Pattern Familiarity | 20% | Standard CRUD/REST/ORM/framework patterns → high. Custom DSLs, prompt engineering, novel abstractions → low |
| Self-containment | 15% | Files reviewable independently → high. Cross-file shared state, event chains → low |
| Defect & Security Surface | 20% | Null checks, error handling, SQL injection, auth, type mismatches → high. Business logic, UX, architectural correctness → low |
| Change Profile | 15% | Bug fix/refactor/new endpoint in one language → high. Architecture/design/knowledge changes scattered across types → low |
| Test Presence | 10% | Tests present that Copilot can validate against → high. Tests *are* the novel contribution, or absent → low |

```
suitability = Σ (dimension_score × weight)
```

## Sufficiency Score (can Copilot replace a human?)

Measures the gap between what Copilot catches and what a competent reviewer would catch. Score each dimension 1-10 (high = Copilot *cannot* handle this), then invert.

| Dimension | Weight | What to measure |
|-----------|--------|----------------|
| Domain Knowledge Depth | 25% | Reviewing requires understanding *why*, not just *how*. Changes to business rules without tests → high |
| Cross-file Coherence | 20% | Changes in file A only make sense given file B. Shared constants, model names, schema fields across files → high |
| Architectural Decisions | 20% | PR is *making* a decision (high) vs *implementing* one (low) |
| Prose/Schema Review | 15% | Correctness is semantic, not syntactic. Markdown, prompts, configs → high |
| Novel Abstraction | 20% | New patterns/frameworks (high) vs instances of existing patterns (low) |

```
sufficiency_gap = Σ (dimension_score × weight)
sufficiency = 10 - sufficiency_gap
```

## Detection Difficulty Prediction

Categorize expected findings by how hard they are to spot. This tells you more than either score alone.

| Level | Definition | Copilot Expected Catch Rate |
|-------|-----------|----------------------------|
| Surface | Visible in the diff alone — typo, missing null check, unused import | ~90% |
| Contextual | Requires reading surrounding code not in the diff | ~50% |
| Cross-file | Requires understanding how multiple changed files interact | ~20% |
| Domain | Requires understanding business logic or system design | ~5% |
| Temporal | Requires knowing project history or prior decisions | ~0% |

In the output, estimate how many findings fall into each level for this project/PR.

## Phase 1 Output Format

```markdown
## Copilot Review Prediction

**Suitability: X.X / 10** — will Copilot find useful things?
**Sufficiency: X.X / 10** — can Copilot replace a human?

### Suitability Breakdown
| Dimension | Score | Rationale |
|-----------|-------|-----------|
| Code Density | ?/10 | ... |
| Pattern Familiarity | ?/10 | ... |
| Self-containment | ?/10 | ... |
| Defect & Security Surface | ?/10 | ... |
| Change Profile | ?/10 | ... |
| Test Presence | ?/10 | ... |

### Sufficiency Gap
| Dimension | Score | Rationale |
|-----------|-------|-----------|
| Domain Knowledge Depth | ?/10 | ... |
| Cross-file Coherence | ?/10 | ... |
| Architectural Decisions | ?/10 | ... |
| Prose/Schema Review | ?/10 | ... |
| Novel Abstraction | ?/10 | ... |

### Detection Difficulty Estimate
| Level | Expected Findings | Copilot Catch Rate |
|-------|-------------------|-------------------|
| Surface | N | ~90% |
| Contextual | N | ~50% |
| Cross-file | N | ~20% |
| Domain | N | ~5% |

### Copilot Will Catch
- [Specific items: unguarded JSON parsing, missing error handling, type gaps, security patterns, lint issues]

### Copilot Will Miss
- [Specific items: cross-file consistency, prose quality, approach correctness, domain-specific rules]

### Verdict
**Route:** [routing option] — [reasoning]
```

## Routing

| Route | When | Example |
|-------|------|---------|
| **Copilot-only** | Suitability ≥ 7, Sufficiency ≥ 7 | Dependency bump, style refactor, standard CRUD endpoint |
| **Copilot-first → human** | Suitability ≥ 5, Sufficiency < 7 | New feature with domain logic — Copilot catches code quality, human validates approach |
| **Human-only** | Suitability < 4 | Architecture RFC, knowledge file updates, system prompt changes |
| **Claude-review** | High cross-file coherence + domain depth | Multi-file refactors where consistency across files is the primary concern |

---

# Phase 2: Post-Review Grading

Run after Copilot has reviewed a PR. Fetches Copilot's comments and scores how well it actually did.

## Procedure

1. `gh api repos/{owner}/{repo}/pulls/{number}/comments` to fetch Copilot's review comments.
2. Independently analyze the diff — build a gold-standard finding list.
3. Classify each Copilot comment and score each dimension.

## Grading Dimensions

### Signal Quality (40% weight)

Classify every Copilot comment:

| Classification | Points | Definition |
|---------------|--------|------------|
| True positive | +10 | Caught a real bug, vulnerability, or logic error |
| Useful suggestion | +5 | Style/pattern improvement that actually matters |
| False positive | -3 | Flagged something that's correct or intentional |
| Noise | -1 | Trivial/obvious comment that wastes reviewer time |

**Signal-to-noise ratio** = `(true positives + useful suggestions) / total comments`

| Ratio | Verdict |
|-------|---------|
| > 0.8 | Excellent — almost every comment adds value |
| 0.6-0.8 | Good — worth having on, minor noise |
| 0.4-0.6 | Mediocre — roughly even split of signal and noise |
| < 0.4 | Poor — creates more work than it saves |

### Context Awareness (25% weight)

| Score | Level |
|-------|-------|
| 0 | Generic linting — comments could apply to any repo |
| 1-3 | Language-aware — understands the language but not the project |
| 4-6 | Project-aware — references repo patterns, conventions, existing code |
| 7-9 | Architecture-aware — understands *why* a change was made |
| 10 | Full context — references code outside the diff, understands cross-file impact |

### Severity Calibration (20% weight)

| Score | Level |
|-------|-------|
| 0 | Inverted — critical issues flagged as nits, nits as critical |
| 1-3 | Flat — everything at the same severity |
| 4-6 | Roughly correct — major issues flagged higher than minor |
| 7-9 | Well calibrated — severity labels match actual impact |
| 10 | Perfect — every comment's severity matches real-world impact |

### Actionability (15% weight)

| Score | Level |
|-------|-------|
| 0 | Vague — "This could be improved" with no direction |
| 1-3 | Problem identified — points at issue but no fix |
| 4-6 | Clear problem — explains what's wrong and why |
| 7-9 | Problem + suggestion — proposes a solution |
| 10 | Problem + solution + context — full explanation with code fix and rationale |

## Detection Difficulty Breakdown

Score Copilot's actual catch rate by difficulty level. Compare against Phase 1 predictions.

```
Surface findings:    X/Y caught (Z%)
Contextual findings: X/Y caught (Z%)
Cross-file findings: X/Y caught (Z%)
Domain findings:     X/Y caught (Z%)
```

## Phase 2 Output Format

```markdown
## Copilot Review Grade: PR #123

**Overall: X.X / 10 — Grade: [A-F]**

| Dimension | Score | Weight | Weighted |
|-----------|-------|--------|----------|
| Signal Quality | ?/10 | 40% | ? |
| Context Awareness | ?/10 | 25% | ? |
| Severity Calibration | ?/10 | 20% | ? |
| Actionability | ?/10 | 15% | ? |

**Signal-to-Noise Ratio:** X.XX (N useful / M total comments)

### Detection Difficulty Breakdown
| Level | Found | Total | Catch Rate | Predicted |
|-------|-------|-------|-----------|-----------|
| Surface | ? | ? | ?% | ~90% |
| Contextual | ? | ? | ?% | ~50% |
| Cross-file | ? | ? | ?% | ~20% |
| Domain | ? | ? | ?% | ~5% |

### Comment Breakdown
| # | File | Classification | Severity Accurate | Actionable | Note |
|---|------|---------------|-------------------|------------|------|
| 1 | file:line | True positive | Yes | Yes | ... |
| 2 | file:line | Noise | N/A | N/A | ... |

### What Copilot Missed
- [Findings from gold-standard review not caught by Copilot]
```

## Grading Scale

| Score | Grade | Recommendation |
|-------|-------|---------------|
| 9.0-10.0 | A | Trust as primary reviewer, human spot-checks |
| 7.5-8.9 | B | Good supplement to human review |
| 6.0-7.4 | C | Useful but requires filtering noise |
| 4.0-5.9 | D | Marginal value, consider disabling |
| < 4.0 | F | Net negative — turn it off |

---

# Calibration

Track predictions vs. actuals over time in `.copilot-eval/history.yaml`:

```yaml
- pr: 4
  project: growy
  date: 2026-03-20
  # Phase 1 predictions
  predicted_suitability: 7
  predicted_sufficiency: 4
  predicted_route: copilot-first-human
  # Phase 2 actuals
  actual_grade: 5.2
  signal_to_noise: 0.55
  true_positives: 3
  false_positives: 1
  missed_critical: 2
  routing_correct: true
  # Detection difficulty accuracy
  surface_predicted: 90
  surface_actual: 100
  contextual_predicted: 50
  contextual_actual: 40
  crossfile_predicted: 20
  crossfile_actual: 0
```

Over time, adjust dimension weights and detection difficulty estimates based on accumulated data. Surface confidence: "Based on N evaluations, predictions accurate to ±X."

## Benchmarking

For a meaningful project-level assessment, score across PR types:

| PR Type | Expected Suitability | Expected Sufficiency |
|---------|---------------------|---------------------|
| Docs/config only | 1-3 | 8-10 |
| Dependency update | 3-5 | 8-10 |
| Standard bug fix | 8-10 | 7-9 |
| New feature | 6-8 | 4-6 |
| Complex refactor | 5-7 | 2-4 |
| Architecture/design | 2-4 | 1-3 |

Minimum benchmark: 1 docs/config PR, 2 feature PRs, 1 complex refactor. Compare actual grades across types to identify where Copilot adds value vs. where it falls short.
