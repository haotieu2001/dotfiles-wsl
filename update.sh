#!/usr/bin/env bash
# Upgrade everything bootstrap.sh installed. Pinned downloads (packages/pinned.sh)
# only move when you change their version there; this script leaves them alone.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> apt (Ubuntu, GitHub CLI, HashiCorp, NodeSource)"
sudo apt-get update -qq
sudo apt-get upgrade -y

echo "==> Databricks CLI"
# The official installer refuses to overwrite, so remove the old binary first.
sudo rm -f /usr/local/bin/databricks
curl -fsSL https://raw.githubusercontent.com/databricks/setup-cli/main/install.sh | sudo sh

echo "==> uv and uv tools"
"$HOME/.local/bin/uv" self update
"$HOME/.local/bin/uv" tool upgrade --all

echo "==> npm globals"
npm update -g

echo "==> pinned downloads and links (installs anything new in packages/)"
"$DIR/bootstrap.sh" >/dev/null
echo "    done; run ./scripts/check-drift.sh to confirm"
