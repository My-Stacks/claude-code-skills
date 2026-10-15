# stacklist-dev

The shared Claude Code kit for Stacklist (My-Stacks) repos. One setup for Martina, Dusan, CI and cloud routines.

| Part | What it does |
|---|---|
| `registry/repos.yaml` | Per repo: PR base and umbrellas, the **safe** verify command, `loop_ready` (may bots open PRs), deploy map, hazards. The source of truth agents read. |
| `/verify` | Runs the repo's verify command from the registry; for UI changes, desktop + phone screenshots next to the reference. Nothing is "done" without `VERIFY: pass`. |
| `/ship-pr <n> [comment\|fix]` | Review + triage + architecture pass + Sonar, then post verified findings as one review, or fix, `/verify`, push. Stops at "Merge?". |
| `/angles <problem>` | Plan from four forced angles (smallest, proper, reuse, contrarian) in parallel, score, merge. For real decisions only; it is token-heavy. |
| `fe-architecture-review`, `be-architecture-review` | Read-only (Read/Glob/Grep) architecture pass for platform-v2 and cloud-functions. Builders run them as a self-check. |
| `hooks/rule-enforcer.mjs` | Blocks: person-named branches, `gh pr create --base main` in dev-flow repos, jest without a worker cap, bare jest in cloud-functions. Fails open. |

## Install

For yourself, everywhere:

```
/plugin install stacklist-dev --marketplace My-Stacks/claude-code-skills
```

Each Stacklist repo turns it on in its checked-in `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "stacks-inc-skills": { "source": { "source": "github", "repo": "My-Stacks/claude-code-skills" } }
  },
  "enabledPlugins": { "stacklist-dev@stacks-inc-skills": true }
}
```

You need read access to this repo (your normal git credentials are used). Accept the folder-trust prompt once per repo.

Cloud routines and the GitHub Action don't read repo-declared plugins. Routines add `My-Stacks/claude-code-skills` as a second repo and follow the files directly; the Action uses its `plugin_marketplaces` / `plugins` inputs with a token that can read this repo.

## Tests

```bash
node --test plugins/stacklist-dev/hooks/rule-enforcer.test.mjs
```
