#!/usr/bin/env bash
# install.sh — one-time per-machine setup for design-qa
# Installs Playwright Chromium, axe, lighthouse, pa11y, and (optionally) agent-browser + Argos CLI.

set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
BROWSER_DRIVER="${DESIGN_QA_BROWSER_DRIVER:-playwright-mcp}"

# Resolve the agent-browser version. The default is `latest` so the install
# stays usable out-of-the-box, but production-leaning users should pin to a
# specific release by exporting DESIGN_QA_AGENT_BROWSER_VERSION before running
# install.sh — that closes the supply-chain risk that comes with `latest` on a
# low-popularity package. The install also runs with --ignore-scripts to limit
# blast radius regardless of which version resolves.
AGENT_BROWSER_VERSION="${DESIGN_QA_AGENT_BROWSER_VERSION:-latest}"

echo "design-qa setup starting..."
echo "  plugin root: $PLUGIN_ROOT"
echo "  browser driver: $BROWSER_DRIVER"

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

# 1. Playwright + Chromium
echo ""
echo "[1/5] Installing Playwright + Chromium..."
install_dev "@playwright/test"
npx playwright install --with-deps chromium

# 2. axe-core
echo ""
echo "[2/5] Installing axe-core..."
install_dev "@axe-core/playwright"
install_dev "axe-core"

# 3. Lighthouse
echo ""
echo "[3/5] Installing Lighthouse..."
install_dev "playwright-lighthouse"
install_dev "lighthouse"
install_dev "chrome-launcher"

# 4. Pa11y
echo ""
echo "[4/5] Installing Pa11y..."
install_dev "pa11y"

# 5. Optional drivers
echo ""
echo "[5/5] Optional installs..."
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
echo "design-qa setup complete."
echo "Verify with: node $PLUGIN_ROOT/bin/verify.js"
