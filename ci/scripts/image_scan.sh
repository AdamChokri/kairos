#!/usr/bin/env bash
# ci/scripts/image_scan.sh - Trivy on the saved image files (plan WP4.2): vulnerabilities and secrets in the
# layers, then the gate of ci/scripts/kev_check.py (Critical always, High with a fix, KEV, any secret).
# Writes JSON, SARIF and an HTML report per image; the HTML is what Jenkins shows through publishHTML.
set -Eeuo pipefail
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
CONTROL=image_scan

for name in api web; do
  tar="images/kairos-$name.tar"
  [[ -f $ROOT/$tar ]] || die "$tar is missing: build_images.sh did not run"
  rc=0
  run_tool --network --volume kairos-trivy-cache:/cache trivy trivy image --cache-dir /cache --input "/src/$tar" \
    --scanners vuln,secret --ignorefile /src/.trivyignore.yaml --format json --output "/reports/trivy-image-$name.json" || rc=$?
  [[ $rc == 0 ]] || die "trivy image $tar failed with exit $rc"
  run_tool --volume kairos-trivy-cache:/cache trivy trivy convert --format sarif --output "/reports/trivy-image-$name.sarif" "/reports/trivy-image-$name.json"
  run_tool --volume kairos-trivy-cache:/cache trivy trivy convert --format template --template "@/contrib/html.tpl" \
    --output "/reports/trivy-image-$name.html" "/reports/trivy-image-$name.json"
done

rc=0
run_tool --network --volume kairos-kev-cache:/kev python python /src/ci/scripts/kev_check.py --name image \
  --trivy /reports/trivy-image-api.json /reports/trivy-image-web.json --cache /kev/kev.json \
  --out /reports/gate-image.json | tee /dev/stderr > "$REPORTS/gate-image.txt" || rc=$?
case $rc in 0 | 1) ;; *) die "kev_check.py failed with exit $rc" ;; esac
verdict image_scan "$(sed -n 's/^blocking: //p' "$REPORTS/gate-image.txt")" IMAGE
