#!/usr/bin/env bash
# ci/scripts/sast.sh - static analysis (plan WP4.2): Semgrep, Bandit and ESLint on every build, SonarQube on main.
# Each tool writes SARIF under reports/ for Jenkins' Warnings plugin, and the number of findings at or above its
# threshold (security/policy/gates.env) decides the verdict. Needs backend/.venv and frontend/node_modules, which
# build_test created in this workspace. Semgrep's registry packs are fetched at run time (the same packs as the
# push-stage hook), so it is the one tool here with a network.
# SonarQube Community Build analyses one branch: the script runs it on main only, with SONAR_TOKEN in the
# environment (the Jenkinsfile binds it from OpenBao on that lane only), and waits for the quality gate.
set -Eeuo pipefail
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
CONTROL=sast
blocked=0
count() { sed -n 's/^blocking: //p'; }

# level_of SEVERITY - the SARIF level that a severity name of a tool stands for.
level_of() { case "$1" in ERROR | error | HIGH) echo error ;; WARNING | warning | MEDIUM) echo warning ;; *) echo note ;; esac; }

# --- Semgrep: the project's rules (security/semgrep/) and the registry packs of the hook ---
rc=0
run_tool --network semgrep semgrep scan --config p/python --config p/typescript --config p/react \
  --config security/semgrep/ --exclude security/semgrep/tests --exclude node_modules --exclude .venv --exclude .ci \
  --metrics off --quiet --sarif-output /reports/semgrep.sarif . || rc=$?
[[ $rc == 0 ]] || die "semgrep failed with exit $rc"
n="$(python3 -I "$ROOT/ci/scripts/sarif_gate.py" --level "$(level_of "$SEMGREP_BLOCK_SEVERITY")" "$REPORTS/semgrep.sarif" | tee_stderr | count)"
blocked=$((blocked + n))

# --- Bandit: JSON in full, then SARIF, then the verdict at severity and confidence ---
rc=0
run_tool python backend/.venv/bin/python -m bandit -c backend/pyproject.toml -r backend/app -f json -o /reports/bandit.json || rc=$?
[[ $rc == 0 || $rc == 1 ]] || die "bandit failed with exit $rc"
n="$(python3 -I "$ROOT/ci/scripts/bandit_to_sarif.py" "$REPORTS/bandit.json" --out "$REPORTS/bandit.sarif" \
  --block-severity "$BANDIT_BLOCK_SEVERITY" --min-confidence "$BANDIT_MIN_CONFIDENCE" | tee_stderr | count)"
blocked=$((blocked + n))

# --- ESLint: the repository's flat config, JSON converted to SARIF (eslint_to_sarif.py, erratum E-42) ---
rc=0
run_tool --workdir /src/frontend node node node_modules/.bin/eslint --no-cache -f json -o /reports/eslint.json . || rc=$?
[[ $rc == 0 || $rc == 1 ]] || die "eslint failed with exit $rc"
python3 -I "$ROOT/ci/scripts/eslint_to_sarif.py" "$REPORTS/eslint.json" --out "$REPORTS/eslint.sarif"
n="$(python3 -I "$ROOT/ci/scripts/sarif_gate.py" --level "$(level_of "$ESLINT_BLOCK_LEVEL")" "$REPORTS/eslint.sarif" | tee_stderr | count)"
blocked=$((blocked + n))

# --- SonarQube: main only ---
if [[ ${BRANCH_NAME:-} == main && -n ${SONAR_TOKEN:-} ]]; then
  export SONAR_USER_HOME=/tmp/.sonar GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.directory GIT_CONFIG_VALUE_0=/src
  # A SonarQube exception of the register must really be resolved in SonarQube (plan section 4.3).
  if ! SONAR_TOKEN="$SONAR_TOKEN" python3 -I "$ROOT/ci/scripts/check_exceptions.py" --sonar "$SONAR_HOST_URL"; then
    blocked=$((blocked + 1))
  fi
  rc=0
  # The scanner downloads its JRE into SONAR_USER_HOME (under /tmp) and runs it from there, but Docker mounts a tmpfs noexec:
  # this one container gets a /tmp that can execute (--exec-tmp, D-43). Its root stays read-only, no capability is added back,
  # and the tmpfs vanishes with the container.
  run_tool --network --hosts --exec-tmp --env SONAR_TOKEN --env SONAR_USER_HOME --env GIT_CONFIG_COUNT \
    --env GIT_CONFIG_KEY_0 --env GIT_CONFIG_VALUE_0 sonar-scanner \
    -Dsonar.host.url="$SONAR_HOST_URL" -Dsonar.projectKey="$SONAR_PROJECT_KEY" -Dsonar.projectName=Kairos \
    -Dsonar.projectVersion="$SONAR_PROJECT_VERSION" -Dsonar.projectBaseDir=/src \
    -Dsonar.sources=backend/app,frontend/src -Dsonar.tests=backend/tests,frontend/src \
    -Dsonar.test.inclusions='backend/tests/**/*.py,frontend/src/**/*.test.tsx' \
    -Dsonar.exclusions='frontend/src/**/*.test.tsx' -Dsonar.python.version=3.13 \
    -Dsonar.python.coverage.reportPaths=/reports/coverage-backend.xml \
    -Dsonar.javascript.lcov.reportPaths=/reports/coverage-frontend/lcov.info \
    -Dsonar.working.directory=/tmp/.scannerwork -Dsonar.qualitygate.wait=true -Dsonar.qualitygate.timeout=300 \
    2>&1 | tee "$REPORTS/sonar-scanner.log" || rc=$?
  # The scanner exits non-zero both when the gate fails and when it cannot run: the log tells them apart.
  if [[ $rc != 0 ]]; then
    if grep -q 'QUALITY GATE STATUS: FAILED' "$REPORTS/sonar-scanner.log"; then
      echo "sast: the SonarQube gate '$SONAR_GATE' failed"
      blocked=$((blocked + 1))
    else
      die "the SonarQube scanner failed with exit $rc and the gate was not reached (see reports/sonar-scanner.log)"
    fi
  fi
else
  echo "sast: SonarQube skipped (it analyses the main branch only: Community Build, D-09)"
fi

verdict sast "$blocked" SAST
