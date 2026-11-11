#!/usr/bin/env bash
# ci/scripts/build_test.sh - installs the dependencies from the lockfiles, runs both test suites with coverage
# and writes JUnit and coverage reports (plan WP4.2). The only control that mounts the workspace read-write:
# it creates backend/.venv and frontend/node_modules, which the sast stage then uses without a network.
# Tests always enforce: a failing test is exit 1, never a yellow stage.
#   Backend:  uv from ci/tools/uv-requirements.txt (installed with its hashes), then `uv sync --frozen`
#   Frontend: npm ci --ignore-scripts (nothing a package ships is executed), vitest with coverage
set -Eeuo pipefail
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
CONTROL=build_test

backend() {
  run_tool --network --rw --workdir /src/backend python sh -ec '
    python -m pip install --quiet --disable-pip-version-check --no-cache-dir --require-hashes \
      --target /src/.ci/uv -r /src/ci/tools/uv-requirements.txt
    export UV_CACHE_DIR=/tmp/uv-cache UV_PYTHON_DOWNLOADS=never UV_PYTHON=/usr/local/bin/python3
    /src/.ci/uv/bin/uv sync --frozen --quiet
    .venv/bin/python -m pytest -q --cov=app --cov-report=xml:/reports/coverage-backend.xml \
      --cov-report=term --junitxml=/reports/junit-backend.xml
  '
}

frontend() {
  run_tool --network --rw --workdir /src/frontend --env npm_config_cache --env npm_config_update_notifier \
    --env npm_config_fund node sh -ec '
    npm ci --ignore-scripts
    npx vitest run --reporter=default --reporter=junit --outputFile.junit=/reports/junit-frontend.xml \
      --coverage.enabled --coverage.provider=v8 --coverage.reporter=lcov --coverage.reporter=text-summary \
      --coverage.reportsDirectory=/reports/coverage-frontend
  '
}

export npm_config_cache=/tmp/npm-cache npm_config_update_notifier=false npm_config_fund=false
failed=0
backend || failed=$((failed + 1))
frontend || failed=$((failed + 1))
if (( failed > 0 )); then
  printf 'build_test: BLOCKED, %s test suite(s) failed or could not run (tests always enforce)\n' "$failed"
  exit 1
fi
echo "build_test: passed (reports/junit-*.xml, reports/coverage-*)"
