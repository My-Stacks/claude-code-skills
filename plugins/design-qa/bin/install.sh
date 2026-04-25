#!/usr/bin/env bash
# install.sh — one-time per-machine setup for design-qa
#
# Two install tiers, controlled by DESIGN_QA_INSTALL_TIER:
#   - minimum: Playwright + axe only. Skips Lighthouse + Pa11y. Use this for
#     responsive sweeps and accessibility passes when you don't need perf
#     measurement (and want to avoid the ~180-package transitive footprint
#     that Lighthouse pulls in).
#   - full (default): minimum + Lighthouse + chrome-launcher + Pa11y. The
#     full audit pipeline.
#
# Note on `npm audit`: the full tier surfaces ~50 transitive advisories
# coming from Lighthouse's deep dependency chain. None affect runtime since
# these are dev-time tools, but the noise is real — see TROUBLESHOOTING.md.

set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
BROWSER_DRIVER="${DESIGN_QA_BROWSER_DRIVER:-playwright-mcp}"
INSTALL_TIER="${DESIGN_QA_INSTALL_TIER:-full}"

case "$INSTALL_TIER" in
  minimum|full) ;;
  *) echo "DESIGN_QA_INSTALL_TIER must be 'minimum' or 'full'; got '$INSTALL_TIER'" >&2; exit 1 ;;
esac

# Resolve the agent-browser version. The default is `latest` so the install
# stays usable out-of-the-box, but production-leaning users should pin to a
# specific release by exporting DESIGN_QA_AGENT_BROWSER_VERSION before running
# install.sh — that closes the supply-chain risk that comes with `latest` on a
# low-popularity package. The install also runs with --ignore-scripts to limit
# blast radius regardless of which version resolves.
AGENT_BROWSER_VERSION="${DESIGN_QA_AGENT_BROWSER_VERSION:-latest}"

echo "design-qa setup starting..."
echo "  plugin root:    $PLUGIN_ROOT"
echo "  browser driver: $BROWSER_DRIVER"
echo "  install tier:   $INSTALL_TIER"

# Detect package manager. Prefer the Corepack-style `packageManager` field —
# it's authoritative when present and beats lockfile sniffing on fresh repos.
PM="npm"
HAS_PROJECT=0
if [ -f "package.json" ]; then
  HAS_PROJECT=1
  PKG_MGR_FIELD="$(node -e 'try{const p=require("./package.json");process.stdout.write((p.packageManager||"").split("@")[0])}catch{process.stdout.write("")}' 2>/dev/null || echo "")"
  if [ -n "$PKG_MGR_FIELD" ]; then
    PM="$PKG_MGR_FIELD"
  elif [ -f "pnpm-lock.yaml" ]; then PM="pnpm"
  elif [ -f "yarn.lock" ]; then PM="yarn"
  elif [ -f "bun.lockb" ] || [ -f "bun.lock" ]; then PM="bun"
  fi
else
  echo "  no package.json found in cwd; will install globally"
fi

echo "  package manager: $PM"

install_dev() {
  local pkg="$1"
  if [ "$HAS_PROJECT" -eq 1 ]; then
    case "$PM" in
      pnpm) pnpm add -D "$pkg" ;;
      yarn) yarn add -D "$pkg" ;;
      bun)  bun add -d "$pkg" ;;
      npm)  npm install --save-dev "$pkg" ;;
      *)    echo "  unknown package manager '$PM'; falling back to npm"; npm install --save-dev "$pkg" ;;
    esac
  else
    npm install -g "$pkg"
  fi
}

# Tier: minimum + full (Playwright Chromium + axe-core)
echo ""
echo "[1] Installing Playwright + Chromium..."
install_dev "@playwright/test"
npx playwright install --with-deps chromium

echo ""
echo "[2] Installing axe-core..."
install_dev "@axe-core/playwright"
install_dev "axe-core"

if [ "$INSTALL_TIER" = "full" ]; then
  # Lighthouse — chrome-launcher only (no playwright-lighthouse: the plugin
  # drives Lighthouse via chrome-launcher directly to avoid the wsEndpoint
  # foot-gun in current Playwright).
  echo ""
  echo "[3] Installing Lighthouse..."
  install_dev "lighthouse"
  install_dev "chrome-launcher"

  echo ""
  echo "[4] Installing Pa11y..."
  install_dev "pa11y"
else
  echo ""
  echo "[skipping Lighthouse + Pa11y — minimum tier]"
  echo "  Re-run with DESIGN_QA_INSTALL_TIER=full to add them."
fi

# Optional drivers (independent of tier)
echo ""
echo "[optional installs]"
if [ "$BROWSER_DRIVER" = "agent-browser" ]; then
  echo "  installing agent-browser@${AGENT_BROWSER_VERSION} with --ignore-scripts..."
  # --ignore-scripts blocks postinstall hooks, which limits the blast radius if
  # the package or one of its deps gets compromised. The follow-up
  # `agent-browser install` runs the legit setup explicitly.
  npm install -g --ignore-scripts "agent-browser@${AGENT_BROWSER_VERSION}"
  agent-browser install || echo "  WARN: agent-browser install step failed; run manually"
fi

if [ -n "${DESIGN_QA_ARGOS_TOKEN:-}" ]; then
  echo "  installing @argos-ci/playwright + @argos-ci/cli..."
  install_dev "@argos-ci/playwright"
  install_dev "@argos-ci/cli"
fi

echo ""
echo "design-qa setup complete (tier: $INSTALL_TIER)."
# Pass the tier through so verify.js doesn't fall back to "full" and flag the
# minimum-tier install as broken on a perfectly valid setup.
echo "Verify with: DESIGN_QA_INSTALL_TIER=$INSTALL_TIER node $PLUGIN_ROOT/bin/verify.js"
if [ "$INSTALL_TIER" = "full" ]; then
  echo ""
  echo "Note: \`npm audit\` will report ~50 advisories from Lighthouse's transitive"
  echo "deps. These are dev-time tools and don't ship to your runtime. See"
  echo "TROUBLESHOOTING.md for context."
fi
