#!/usr/bin/env bash
# ci/tools/hook-hadolint.sh FILE... - the Hadolint hook (plan WP3.2): fails at level `error`, which is
# the gate of plan section 4.2; warnings and style findings are printed and do not stop the commit.
# Needs the pinned Hadolint (ci/tools/install-scan-tools.sh).
set -Eeuo pipefail

HADOLINT_PINNED="2.15.1"
command -v hadolint >/dev/null || { echo "hook-hadolint: hadolint is not installed - run: bash ci/tools/install-scan-tools.sh" >&2; exit 2; }
found="$(hadolint --version | awk '{print $NF}')"
[[ "$found" == "$HADOLINT_PINNED" ]] || { echo "hook-hadolint: hadolint $found is installed, $HADOLINT_PINNED is pinned (plan D-12)" >&2; exit 2; }
exec hadolint --failure-threshold error "$@"
