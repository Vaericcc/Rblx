#!/usr/bin/env bash
# Pull the latest Dubble Take from GitHub and serve it to Roblox Studio with Rojo.
# Usage: ./scripts/sync.sh            (pull + rojo serve)
#        ./scripts/sync.sh build      (pull + build DubbleTake.rbxl)
set -euo pipefail
cd "$(dirname "$0")/.."

BRANCH="${BRANCH:-$(git rev-parse --abbrev-ref HEAD)}"
echo "Pulling origin/$BRANCH ..."
git pull --ff-only origin "$BRANCH"

if ! command -v rojo >/dev/null 2>&1; then
  echo "rojo not found on PATH. Install it with: rokit install   (or see https://rojo.space)"
  exit 1
fi

if [[ "${1:-serve}" == "build" ]]; then
  rojo build -o DubbleTake.rbxl
  echo "Built DubbleTake.rbxl - open it in Studio."
else
  echo "Serving. In Studio: Plugins -> Rojo -> Connect (localhost:34872)."
  rojo serve
fi
