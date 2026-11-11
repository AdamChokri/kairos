#!/usr/bin/env bash
# ci/tools/hooks-install.sh - installs pre-commit and this clone's Git hooks, with the 7-day rule applied to the hooks'
# own Python dependencies too (plan WP4.6, HOOK-01, decision D-34).
#   bash ci/tools/hooks-install.sh        (also: make hooks-install; run again after a hook revision changed)
# Why: pre-commit builds one environment per hook repository (Ruff, Bandit, Semgrep, ...) and resolves their
# dependencies from PyPI when it first needs them, with whatever is newest. Here pre-commit runs with the `uv`
# installer (pre-commit-uv), and `UV_EXCLUDE_NEWER` tells uv to ignore every release younger than 7 days: the same
# limit as the tools of P3 (D-12) and the CI (ci/tools/lock-age.py). The environments are rebuilt now, under that
# limit (`pre-commit clean`), and a later `git commit` only reuses them. The versions below must agree with the
# other pins: ci/tools/check-tools-lock.sh (run by preflight) compares them.
# Needs uv, git and the network. GNU `date` (Ubuntu, WSL2).
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PRE_COMMIT_VERSION="4.7.0"
PRE_COMMIT_UV_VERSION="4.4.1"
UV_VERSION="0.13.6"
AGE_DAYS=7

command -v uv >/dev/null || { echo "hooks-install: uv is not installed" >&2; exit 2; }
git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || { echo "hooks-install: $ROOT is not a Git clone" >&2; exit 2; }

cutoff="$(date -u -d "$AGE_DAYS days ago" +%Y-%m-%dT%H:%M:%SZ)"
export UV_EXCLUDE_NEWER="$cutoff"
printf 'hooks-install: no release after %s (%s days ago) enters pre-commit or a hook environment\n' "$cutoff" "$AGE_DAYS"

uv tool install --force --python 3.12 "pre-commit==$PRE_COMMIT_VERSION" \
  --with "pre-commit-uv==$PRE_COMMIT_UV_VERSION" --with "uv==$UV_VERSION"

cd "$ROOT"
pre-commit clean
pre-commit install --hook-type pre-commit --hook-type pre-push
pre-commit install-hooks
printf 'hooks-install: hooks installed for the commit and the push stage (%s)\n' "$(pre-commit --version)"
