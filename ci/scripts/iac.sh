#!/usr/bin/env bash
# ci/scripts/iac.sh - Dockerfiles (plan WP4.2): Hadolint at the level of gates.env, and Trivy's misconfiguration
# checks at HIGH and CRITICAL, for the two images of Kairos. (Compose is reviewed by hand and checked on the
# running containers at deploy time; Trivy has no Compose checks.) A Trivy suppression follows .trivyignore.yaml.
set -Eeuo pipefail
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
CONTROL=iac
blocked=0
dockerfiles=(backend/Dockerfile frontend/Dockerfile)

for file in "${dockerfiles[@]}"; do
  name="${file%%/*}"
  rc=0
  run_tool hadolint hadolint --failure-threshold "$HADOLINT_BLOCK_LEVEL" --format sarif "/src/$file" > "$REPORTS/hadolint-$name.sarif" || rc=$?
  [[ $rc == 0 || $rc == 1 ]] || die "hadolint $file failed with exit $rc"

  rc=0
  run_tool --network --volume kairos-trivy-cache:/cache trivy trivy config --cache-dir /cache \
    --severity "$TRIVY_CONFIG_BLOCK" --ignorefile /src/.trivyignore.yaml --format json \
    --output "/reports/trivy-config-$name.json" "/src/$file" || rc=$?
  [[ $rc == 0 ]] || die "trivy config $file failed with exit $rc"
  run_tool --volume kairos-trivy-cache:/cache trivy trivy convert --format sarif \
    --output "/reports/trivy-config-$name.sarif" "/reports/trivy-config-$name.json"
done

n="$(python3 -I "$ROOT/ci/scripts/sarif_gate.py" --level "$(case $HADOLINT_BLOCK_LEVEL in error) echo error ;; warning) echo warning ;; *) echo note ;; esac)" \
  "$REPORTS"/hadolint-*.sarif | tee /dev/stderr | sed -n 's/^blocking: //p')"
blocked=$((blocked + n))

# Trivy: every misconfiguration that is still FAIL at HIGH or CRITICAL blocks (--severity already filtered the report).
m="$(python3 -I - "$REPORTS"/trivy-config-*.json <<'PY'
import json, sys
count = 0
for path in sys.argv[1:]:
    for result in json.load(open(path)).get("Results") or []:
        for miss in result.get("Misconfigurations") or []:
            if miss.get("Status", "FAIL") == "FAIL":
                count += 1
                print(f"BLOCKS  {miss['ID']} {miss.get('Severity')}  {result.get('Target')}  {miss.get('Title', '')}", file=sys.stderr)
print(count)
PY
)"
blocked=$((blocked + m))
verdict iac "$blocked" IAC
