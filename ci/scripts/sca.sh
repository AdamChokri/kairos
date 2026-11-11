#!/usr/bin/env bash
# ci/scripts/sca.sh - dependency scan (plan WP4.2): Trivy on the two lockfiles (one target per run), then the
# gate of ci/scripts/kev_check.py: Critical always, High when a fix exists, and any CVE of CISA's KEV catalog.
# Approved exceptions are in .trivyignore.yaml, which Trivy applies itself (and enforces its expiry).
# Trivy's databases and the KEV catalog live in named Docker volumes, so a build downloads them once a day.
set -Eeuo pipefail
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
CONTROL=sca

scan() { # NAME LOCKFILE
  local rc=0
  run_tool --network --volume kairos-trivy-cache:/cache trivy trivy fs --cache-dir /cache --scanners vuln \
    --ignorefile /src/.trivyignore.yaml --format json --output "/reports/trivy-fs-$1.json" "/src/$2" || rc=$?
  [[ $rc == 0 ]] || die "trivy fs $2 failed with exit $rc"
  run_tool --volume kairos-trivy-cache:/cache trivy trivy convert --format sarif --output "/reports/trivy-fs-$1.sarif" "/reports/trivy-fs-$1.json"
}
scan backend backend/uv.lock
scan frontend frontend/package-lock.json

rc=0
run_tool --network --volume kairos-kev-cache:/kev python python /src/ci/scripts/kev_check.py --name sca \
  --trivy /reports/trivy-fs-backend.json /reports/trivy-fs-frontend.json --cache /kev/kev.json \
  --out /reports/gate-sca.json | tee /dev/stderr > "$REPORTS/gate-sca.txt" || rc=$?
case $rc in 0 | 1) ;; *) die "kev_check.py failed with exit $rc" ;; esac
verdict sca "$(sed -n 's/^blocking: //p' "$REPORTS/gate-sca.txt")" SCA
