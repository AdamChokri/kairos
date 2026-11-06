#!/usr/bin/env bash
# ci/tools/frontend-deps.sh - installs the frontend's dependencies into frontend/node_modules for the
# ESLint hook and for the editor (plan WP3.1, WP3.2), without a Node installation on the workstation:
# `npm ci` runs inside the Node image pinned by digest in ci/tools/node-image.txt (D-12), as your own
# user, from the lockfile, with install scripts switched off (`--ignore-scripts`: nothing a package
# ships is executed). Run it once, and again whenever frontend/package-lock.json changes.
#   bash ci/tools/frontend-deps.sh
# Needs Docker running in WSL2 (sudo service docker start) and the network.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMAGE="$(tr -d '[:space:]' < "$ROOT/ci/tools/node-image.txt")"
[[ $IMAGE =~ ^node:[0-9.]+-slim@sha256:[0-9a-f]{64}$ ]] || { echo "frontend-deps: ci/tools/node-image.txt does not hold a pinned node image" >&2; exit 2; }
command -v docker >/dev/null || { echo "frontend-deps: docker is not installed" >&2; exit 2; }
docker info >/dev/null 2>&1 || { echo "frontend-deps: Docker is not running - start it with: sudo service docker start" >&2; exit 2; }

docker run --rm --user "$(id -u):$(id -g)" \
  -e HOME=/tmp -e npm_config_cache=/tmp/npm-cache -e npm_config_update_notifier=false -e npm_config_fund=false \
  -v "$ROOT/frontend:/app" -w /app "$IMAGE" \
  npm ci --ignore-scripts
echo "frontend-deps: frontend/node_modules is ready ($IMAGE)"
