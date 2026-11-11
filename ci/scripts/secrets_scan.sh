#!/usr/bin/env bash
# ci/scripts/secrets_scan.sh - Gitleaks twice (plan WP4.2): the files of this checkout, and the whole Git history.
# The files must hold no secret at all. The history is compared with security/gitleaks-baseline.json when that
# file exists: it lists the two FAKE values that Kairos v0 committed on purpose (SV-01), which a public history
# keeps for good (rewriting it would not take back the copies that already exist). Exit code 2 of Gitleaks means
# "leaks found", which is why it runs with --exit-code 2: a crash (any other code) can never look like a verdict.
set -Eeuo pipefail
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
CONTROL=secrets_scan

# gitleaks_run NAME ARGS... - runs one scan; 0 and 2 are verdicts, anything else is a failure of the tool.
gitleaks_run() {
  local name=$1 rc=0
  shift
  run_tool gitleaks gitleaks "$@" --config /src/.gitleaks.toml --redact --no-banner --exit-code 2 \
    --report-format sarif --report-path "/reports/gitleaks-$name.sarif" || rc=$?
  [[ $rc == 0 || $rc == 2 ]] || die "gitleaks ($name) failed with exit $rc"
}

# The files scan names its folder `.` (run-tool.sh starts in /src), so that Gitleaks reports paths relative to the
# checkout: the allowlist of .gitleaks.toml (D-23) matches `ci/jenkins/plugins.txt`, and `dir /src` reported
# `/src/ci/jenkins/plugins.txt`, which it never matched (31 findings instead of the two seeded fakes).
gitleaks_run files dir .
history=(git /src)
[[ -f $ROOT/security/gitleaks-baseline.json ]] && history+=(--baseline-path /src/security/gitleaks-baseline.json)
gitleaks_run history "${history[@]}"

blocked="$(python3 -I "$ROOT/ci/scripts/sarif_gate.py" --level note "$REPORTS/gitleaks-files.sarif" "$REPORTS/gitleaks-history.sarif" | tee /dev/stderr | sed -n 's/^blocking: //p')"
verdict secrets_scan "$blocked" SECRETS
