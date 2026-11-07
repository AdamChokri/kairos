#!/usr/bin/env bash
# ci/tools/hook-eslint.sh FILE... - the ESLint hook (plan WP3.2). Lints the staged frontend files with
# the repository's flat config (frontend/eslint.config.js, whose rules include react/no-danger) in the
# Node image pinned by digest in ci/tools/node-image.txt: read-only source, no network, your own user.
# The frontend's own script is `npm --prefix frontend run lint` (the same eslint, run on every file);
# a hook lints only what is committed. Exit code 0: clean; 1: findings; 2: the tool cannot run.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
IMAGE="$(tr -d '[:space:]' < "$ROOT/ci/tools/node-image.txt")"
(( $# > 0 )) || exit 0

fail() { echo "hook-eslint: $1" >&2; exit 2; }
command -v docker >/dev/null || fail "docker is not installed"
docker info >/dev/null 2>&1 || fail "Docker is not running - start it with: sudo service docker start"
[[ -x $ROOT/frontend/node_modules/.bin/eslint ]] || fail "frontend/node_modules is missing - run: bash ci/tools/frontend-deps.sh"

files=()
for file in "$@"; do files+=("${file#frontend/}"); done

exec docker run --rm --network none --read-only --tmpfs /tmp --cap-drop ALL \
  --security-opt no-new-privileges --user "$(id -u):$(id -g)" -e HOME=/tmp \
  -v "$ROOT/frontend:/app:ro" -w /app "$IMAGE" \
  node node_modules/.bin/eslint --no-cache "${files[@]}"
