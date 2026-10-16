---
name: angles
description: Graph-of-thoughts planning. Attack a problem from 4 deliberately different angles in parallel, score them against explicit criteria, merge the best two into one plan, then stress-test it. Use for plans, architecture choices, scoping, GTM/positioning questions, anything with more than one sane answer.
disable-model-invocation: true
argument-hint: "[--quick] <problem> [criteria: a, b, c]"
---

# Angles: plan a problem from four directions, then merge

## Input

```
$ARGUMENTS
```

If the problem is unclear or under one sentence, ask ONE clarifying question and stop. Otherwise go.

## Step 0: Frame (in chat, short)

- **Problem**: one sentence.
- **Criteria**: use the ones given after `criteria:`. If none, pick 3-5 that fit (default for engineering: simplicity, time to ship, risk, reversibility, fit with existing code). Show them.
- **Known constraints**: from CLAUDE.md, memory, and the repo. These are hard filters, not criteria.

## Step 1: Generate 4 independent angles

The value comes from the angles actually being different. Each one gets a fixed lens:

- **A: Smallest change.** The least code and fewest moving parts that solve the stated problem. No new tables, services or abstractions.
- **B: Do it properly.** What would we build if we expected to live with this for 2 years.
- **C: Reuse.** Solve it mostly with what already exists (code, services, tools, vendors, a skill, a config toggle).
- **D: Contrarian.** Reframe the problem: don't build it, solve a different bottleneck, change the process instead of the code, or flip an assumption the other three share.

**Default mode (code or repo-grounded problems):** launch 4 subagents in ONE message (Agent tool, `subagent_type: Explore` for read-only grounding, or `general-purpose` if web research is needed). Each gets: the problem, constraints, criteria, its single lens, and the instruction to NOT read the other angles. Each returns ≤250 words: approach, the files/systems it touches, strengths, weaknesses, and dependencies or conflicts with the other lenses (by name). Read-only: no edits, no writes, no builds.

**`--quick` mode (or no repo involved):** do the 4 angles yourself in one pass, without subagents. Write each angle fully before starting the next.

## Step 2: Map the graph

A short table: angle → strengths, weaknesses, depends on / conflicts with. Call out pieces that appear in more than one angle (that's signal) and assumptions shared by A-C that D broke.

## Step 3: Score

Table: angles × criteria, 1-10 each, total. One line of justification per score that is not obvious. Be harsh; a 10 needs evidence.

## Step 4: Merge into E

Take the top 2 by score. Build E from their strongest parts, plus any single piece from the other two that clearly wins. E must be internally consistent: check each piece's dependencies from Step 2.

## Step 5: Stress-test, refine once

Run E against every weakness listed in Step 2 and against the hard constraints. For each hit: fix it in E, or accept it and say why. One refinement pass only; don't loop.

## Output

Show Steps 0, 2 and 3 compactly (tables). Then:

```
## Plan E
<the plan: concrete steps, files/systems touched, order>

### Why each piece is here
- <piece>: from <angle>, because <one line>

### Accepted risks
- <risk>: <why acceptable>

### What would change the answer
- <signal that would make us pick a different angle>
```

Stop there. This skill produces a plan; it does not implement it. Wait for approval before any edits.
