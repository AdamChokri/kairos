#!/usr/bin/env bash
# ci/scripts/preflight.sh - the first stage (plan WP4.2): is everything the other stages rely on in order?
# The toolkit is consistent (ci/tools/check-tools-lock.sh), the containers are hardened
# (ci/tools/check-container-hardening.py), the exception register is valid and nothing in force
# has expired (ci/scripts/check_exceptions.py), the policy file is well formed, Docker answers, and the agent has
# room to build. Always enforced (MODE_PREFLIGHT): a broken toolkit must not produce a green build.
set -Eeuo pipefail
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
CONTROL=preflight
problems=0
report="$REPORTS/preflight.txt"
: > "$report"
step() { printf '%s\n' "$*" | tee -a "$report"; }
fail() { step "FAIL  $*"; problems=$((problems + 1)); }

step "preflight on $(hostname), $(date -u +%FT%TZ)"

for control in PREFLIGHT SECRETS SAST SCA IAC IMAGE; do
  value="$(mode_of "$control")"
  step "ok    MODE_$control=$value"
done

if bash "$ROOT/ci/tools/check-tools-lock.sh" >> "$report" 2>&1; then step "ok    ci/tools/tools.lock and the pins it must agree with"; else fail "ci/tools/check-tools-lock.sh (see $report)"; fi
if python3 -I "$ROOT/ci/tools/check-container-hardening.py" 2>&1 | tee -a "$report"; then step "ok    Dockerfiles and Compose file hardened (SV-09)"; else fail "ci/tools/check-container-hardening.py"; fi
if python3 -I "$ROOT/ci/scripts/check_exceptions.py" 2>&1 | tee -a "$report"; then step "ok    security/exceptions.yaml"; else fail "security/exceptions.yaml"; fi

if docker info >/dev/null 2>&1; then step "ok    Docker answers"; else fail "Docker does not answer on this agent"; fi
free_gb=$(( $(df --output=avail -B1G "$ROOT" | tail -1 | tr -d ' ') ))
if (( free_gb >= 8 )); then step "ok    ${free_gb} GB free next to the workspace"; else fail "only ${free_gb} GB free next to the workspace: images need 8 GB"; fi
for file in Jenkinsfile security/policy/gates.env backend/uv.lock frontend/package-lock.json .gitleaks.toml; do
  if [[ -f $ROOT/$file ]]; then step "ok    $file"; else fail "$file is missing"; fi
done

verdict preflight "$problems" PREFLIGHT
