#!/usr/bin/env bash
# ci/tools/test-ci-scripts.sh - proves the pipeline's own scripts without Docker, the network or Jenkins (plan WP4.2):
#   - the exit-code protocol of ci/scripts/lib.sh (0 pass, 1 blocked, 2 would block, 3 failure);
#   - run-tool.sh builds exactly the sandboxed `docker run` of the plan, with a stub `docker` that records its arguments;
#   - the secrets scan turns Gitleaks' exit codes into verdicts, and a crash into exit 3;
#   - ci/tools/check-tools-lock.sh refuses a denylisted release, a placeholder, a version that disagrees with another pin;
#   - kev_check.py, sarif_gate.py and bandit_to_sarif.py decide as section 4.2 says, on small fixtures;
#   - check_exceptions.py accepts a valid register and refuses an expired, too long or unmarked one.
#   bash ci/tools/test-ci-scripts.sh        (also run by `make hooks-selftest`). Needs bash, python3; PyYAML for the last part.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
passed=0
ok() { printf '  PASS  %s\n' "$1"; passed=$((passed + 1)); }
bad() { printf '  FAIL  %s\n' "$1" >&2; exit 1; }
# expect_exit WANTED LABEL COMMAND... - runs the command and compares its exit code.
expect_exit() {
  local want=$1 label=$2 rc=0
  shift 2
  "$@" >"$work/out.txt" 2>&1 || rc=$?
  if [[ $rc == "$want" ]]; then ok "$label"; else sed 's/^/        /' "$work/out.txt" >&2; bad "$label (exit $rc, wanted $want)"; fi
}

# A copy of what the scripts need, so that a test can change gates.env or tools.lock freely.
fake="$work/repo"
mkdir -p "$fake/ci/scripts" "$fake/ci/tools" "$fake/security/policy" "$fake/backend" "$fake/frontend" "$fake/reports"
cp "$ROOT"/ci/scripts/* "$fake/ci/scripts/"
cp "$ROOT"/ci/tools/{tools.lock,denylist.txt,check-tools-lock.sh,node-image.txt,install-scan-tools.sh,hook-trivy.sh,commit-scan.sh} "$fake/ci/tools/"
cp "$ROOT/security/policy/gates.env" "$fake/security/policy/"
cp "$ROOT/.gitleaks.toml" "$ROOT/.pre-commit-config.yaml" "$fake/"
cp "$ROOT/backend/pyproject.toml" "$fake/backend/"

echo "1. The exit-code protocol (ci/scripts/lib.sh)"
cat > "$fake/protocol.sh" <<'SH'
#!/usr/bin/env bash
source "$(dirname "$0")/ci/scripts/lib.sh"
CONTROL=protocol
case "$1" in
  verdict) verdict protocol "$2" SECRETS ;;
  crash) false ;;
  mode) mode_of NOPE ;;
esac
SH
printf 'MODE_SECRETS=report\n' > "$fake/security/policy/gates.env"
expect_exit 0 "no finding passes, in report mode" bash "$fake/protocol.sh" verdict 0
expect_exit 2 "findings in report mode would block (exit 2)" bash "$fake/protocol.sh" verdict 3
printf 'MODE_SECRETS=enforce\n' > "$fake/security/policy/gates.env"
expect_exit 1 "findings in enforce mode block (exit 1)" bash "$fake/protocol.sh" verdict 3
expect_exit 3 "a failing command is exit 3, never a verdict" bash "$fake/protocol.sh" crash
expect_exit 3 "an unknown mode variable is exit 3" bash "$fake/protocol.sh" mode
cp "$ROOT/security/policy/gates.env" "$fake/security/policy/"

echo "2. run-tool.sh builds the sandboxed docker run"
mkdir -p "$work/bin"
cat > "$work/bin/docker" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${STUB_ARGS:?}"
exit "${STUB_RC:-0}"
SH
chmod +x "$work/bin/docker"
export STUB_ARGS="$work/args.txt"
PATH="$work/bin:$PATH" bash "$fake/ci/scripts/run-tool.sh" --env SONAR_TOKEN semgrep semgrep scan . || bad "run-tool.sh failed with the stub"
args="$(tr '\n' ' ' < "$STUB_ARGS")"
for want in "run --rm --read-only --tmpfs /tmp --cap-drop ALL --security-opt no-new-privileges" "--user $(id -u):$(id -g)" \
  "--memory 2g" "--network none" ":/src:ro" "/reports -w /src" "-e SONAR_TOKEN " "semgrep/semgrep:1.182.1@sha256:"; do
  [[ $args == *"$want"* ]] || bad "docker run lacks: $want"
done
ok "read-only root, tmpfs, no capability, no new privilege, own user, memory limit, no network, source read-only"
[[ $args != *docker.sock* ]] || bad "the Docker socket must never be mounted"
ok "the Docker socket is never mounted"
SONAR_TOKEN=hunter2-not-a-secret PATH="$work/bin:$PATH" bash "$fake/ci/scripts/run-tool.sh" --env SONAR_TOKEN semgrep semgrep
[[ $(tr '\n' ' ' < "$STUB_ARGS") != *hunter2-not-a-secret* ]] || bad "a secret value reached the command line"
ok "--env passes a variable by name: its value is not on the command line"
PATH="$work/bin:$PATH" bash "$fake/ci/scripts/run-tool.sh" --network --rw python python -V
args="$(tr '\n' ' ' < "$STUB_ARGS")"
[[ $args == *"--network bridge"* && $args == *":/src:rw"* ]] || bad "--network and --rw were not applied"
ok "--network and --rw change exactly the network and the source mount"
# The image entrypoints (trivy, gitleaks and syft define one) must not receive the tool name as an argument.
PATH="$work/bin:$PATH" bash "$fake/ci/scripts/run-tool.sh" trivy trivy image --input x.tar
mapfile -t stub < "$STUB_ARGS"
[[ " ${stub[*]} " == *" --entrypoint= "* ]] || bad "the entrypoint of the image was not cleared"
[[ "${stub[*]}" == *"-w /src aquasec/trivy:0.76.1@sha256:"*" trivy image --input x.tar" ]] || bad "the command is not what the script gave: ${stub[*]}"
ok "the entrypoint of the image is cleared: the command a script gives is the command that runs (no 'trivy trivy')"
PATH="$work/bin:$PATH" bash "$fake/ci/scripts/run-tool.sh" sonar-scanner sonar-scanner -Dsonar.projectKey=kairos
[[ "$(tr '\n' ' ' < "$STUB_ARGS")" != *"--entrypoint"* ]] || bad "the Sonar scanner must keep the entrypoint script of its image"
ok "the Sonar scanner keeps the entrypoint script of its image (it turns SONAR_TOKEN into -Dsonar.token)"
PATH="$work/bin:$PATH" bash "$fake/ci/scripts/run-tool.sh" --entrypoint /bin/sh python -c true
[[ "$(tr '\n' ' ' < "$STUB_ARGS")" == *"--entrypoint /bin/sh "* ]] || bad "--entrypoint was not applied"
ok "--entrypoint still replaces the entrypoint when a script asks for it"
sed -i 's/sha256:76baad[0-9a-f]*/sha256:0000000000000000000000000000000000000000000000000000000000000000/' "$fake/ci/tools/tools.lock"
expect_exit 3 "a placeholder digest is refused (exit 3)" env PATH="$work/bin:$PATH" bash "$fake/ci/scripts/run-tool.sh" python python -V
cp "$ROOT/ci/tools/tools.lock" "$fake/ci/tools/"

echo "3. secrets_scan.sh turns Gitleaks' exit codes into verdicts"
cat > "$work/bin/docker" <<'SH'
#!/usr/bin/env bash
# Stub gitleaks: writes a SARIF with $STUB_LEAKS results where --report-path says, and exits $STUB_RC.
path=""
for ((i = 1; i <= $#; i++)); do [[ ${!i} == --report-path ]] && { j=$((i + 1)); path="${!j}"; }; done
[[ -n $path ]] && python3 - "$path" "${STUB_LEAKS:-0}" "${STUB_REPORTS:?}" <<'PY'
import json, sys
path, leaks, reports = sys.argv[1], int(sys.argv[2]), sys.argv[3]
results = [{"ruleId": "generic-api-key", "level": "error", "locations": [{"physicalLocation": {"artifactLocation": {"uri": "a.py"}, "region": {"startLine": 1}}}]}] * leaks
json.dump({"version": "2.1.0", "runs": [{"tool": {"driver": {"name": "gitleaks"}}, "results": results}]}, open(reports + "/" + path.rsplit("/", 1)[1], "w"))
PY
exit "${STUB_RC:-0}"
SH
export STUB_REPORTS="$fake/reports"
run_secrets() { PATH="$work/bin:$PATH" STUB_RC="$1" STUB_LEAKS="$2" bash "$fake/ci/scripts/secrets_scan.sh"; }
sed -i 's/^MODE_SECRETS=.*/MODE_SECRETS=report/' "$fake/security/policy/gates.env"
expect_exit 0 "no leak: exit 0" run_secrets 0 0
expect_exit 2 "a leak in report mode: exit 2" run_secrets 2 1
sed -i 's/^MODE_SECRETS=.*/MODE_SECRETS=enforce/' "$fake/security/policy/gates.env"
expect_exit 1 "a leak in enforce mode: exit 1" run_secrets 2 1
expect_exit 3 "gitleaks crashing (exit 1) is exit 3, not a verdict" run_secrets 1 0

echo "4. check-tools-lock.sh"
cd "$fake"
expect_exit 0 "the real lock is consistent with every other pin" bash ci/tools/check-tools-lock.sh
cp ci/tools/tools.lock "$work/lock.good"
sed -i 's#aquasec/trivy:0.76.1#aquasec/trivy:0.69.5#' ci/tools/tools.lock
expect_exit 1 "a denylisted Trivy release (0.69.5) is refused" bash ci/tools/check-tools-lock.sh
cp "$work/lock.good" ci/tools/tools.lock
sed -i 's#^semgrep  *semgrep/semgrep:1.182.1#semgrep        semgrep/semgrep:1.182.0#' ci/tools/tools.lock
expect_exit 1 "a version that differs from .pre-commit-config.yaml is refused" bash ci/tools/check-tools-lock.sh
cp "$work/lock.good" ci/tools/tools.lock
sed -i 's#python:3.13.18-slim-trixie#python:latest#' ci/tools/tools.lock
expect_exit 1 "the tag latest is refused" bash ci/tools/check-tools-lock.sh
cp "$work/lock.good" ci/tools/tools.lock
echo 'image  checkmarx/kics  *  test' >> ci/tools/denylist.txt
echo 'kics  checkmarx/kics:2.1.0  sha256:1111111111111111111111111111111111111111111111111111111111111111  2026-01-01  -' >> ci/tools/tools.lock
expect_exit 1 "a refused image (KICS) is refused" bash ci/tools/check-tools-lock.sh
cd "$ROOT"

echo "5. The gates"
trivy_json="$work/trivy.json"
python3 - "$trivy_json" <<'PY'
import json, sys
vulns = [
    {"VulnerabilityID": "CVE-2026-0001", "PkgName": "a", "InstalledVersion": "1", "FixedVersion": "2", "Severity": "CRITICAL"},
    {"VulnerabilityID": "CVE-2026-0002", "PkgName": "b", "InstalledVersion": "1", "FixedVersion": "2", "Severity": "HIGH"},
    {"VulnerabilityID": "CVE-2026-0003", "PkgName": "c", "InstalledVersion": "1", "FixedVersion": "", "Severity": "HIGH"},
    {"VulnerabilityID": "CVE-2026-0004", "PkgName": "d", "InstalledVersion": "1", "FixedVersion": "", "Severity": "LOW"},
    {"VulnerabilityID": "CVE-2026-0005", "PkgName": "e", "InstalledVersion": "1", "FixedVersion": "", "Severity": "MEDIUM"},
]
json.dump({"Results": [{"Target": "t", "Vulnerabilities": vulns}]}, open(sys.argv[1], "w"))
PY
kev_json="$work/kev.json"
echo '{"vulnerabilities":[{"cveID":"CVE-2026-0004"}]}' > "$kev_json"
gate() {
  (
    set -a
    # shellcheck source=/dev/null
    source "$ROOT/security/policy/gates.env"
    set +a
    python3 -I "$ROOT/ci/scripts/kev_check.py" --name test --trivy "$trivy_json" --kev-file "$kev_json"
  )
}
expect_exit 1 "kev_check blocks" gate
for id in "CVE-2026-0001 CRITICAL" "CVE-2026-0002 HIGH" "CVE-2026-0004 LOW"; do
  grep -q "$id" "$work/out.txt" || bad "kev_check must block $id"
done
if grep -q 'CVE-2026-0003' "$work/out.txt"; then bad "a High without a fix must not block"; fi
if grep -q 'CVE-2026-0005' "$work/out.txt"; then bad "a Medium not in KEV must not block"; fi
grep -q '^blocking: 3$' "$work/out.txt" || bad "kev_check must report exactly 3 blocking findings"
ok "Critical, High with a fix and a KEV-listed Low block (3); High without a fix and Medium do not"
echo '{"vulnerabilities":[]}' > "$kev_json"
echo '{"Results":[]}' > "$work/empty.json"
trivy_json="$work/empty.json"
expect_exit 0 "no finding: kev_check passes" gate
expect_exit 3 "a catalog that is not JSON is a tool error (exit 3)" env -u TRIVY_BLOCK_KEV bash -c "echo nope > $work/bad.json; python3 -I $ROOT/ci/scripts/kev_check.py --name t --trivy $work/empty.json --kev-file $work/bad.json"

sarif="$work/x.sarif"
python3 - "$sarif" <<'PY'
import json, sys
def r(rule, level): return {"ruleId": rule, "level": level, "locations": [{"physicalLocation": {"artifactLocation": {"uri": "f.py"}, "region": {"startLine": 3}}}]}
json.dump({"version": "2.1.0", "runs": [{"tool": {"driver": {"name": "t"}}, "results": [r("a", "error"), r("b", "warning"), r("c", "note")]}]}, open(sys.argv[1], "w"))
PY
for pair in error:1 warning:2 note:3; do
  python3 -I ci/scripts/sarif_gate.py --level "${pair%%:*}" "$sarif" | grep -q "^blocking: ${pair##*:}\$" || bad "sarif_gate --level ${pair%%:*} must count ${pair##*:}"
done
ok "sarif_gate counts by level (error 1, warning 2, note 3)"
expect_exit 3 "a missing SARIF file is exit 3: a tool that wrote nothing must not pass" python3 -I ci/scripts/sarif_gate.py "$work/none.sarif"

python3 - "$work/bandit.json" <<'PY'
import json, sys
def issue(test, sev, conf): return {"test_id": test, "test_name": test.lower(), "issue_severity": sev, "issue_confidence": conf, "issue_text": "x", "filename": "backend/app/a.py", "line_number": 7, "issue_cwe": {"id": 89}, "more_info": "https://bandit.readthedocs.io"}
json.dump({"results": [issue("B324", "HIGH", "HIGH"), issue("B506", "MEDIUM", "HIGH"), issue("B608", "MEDIUM", "LOW"), issue("B999", "HIGH", "LOW")]}, open(sys.argv[1], "w"))
PY
python3 -I ci/scripts/bandit_to_sarif.py "$work/bandit.json" --out "$work/bandit.sarif" --block-severity HIGH --min-confidence MEDIUM |
  grep -q '^blocking: 1$' || bad "Bandit: exactly 1 of 4 issues must block"
ok "Bandit: only HIGH severity with MEDIUM or better confidence blocks (1 of 4)"
python3 -I ci/scripts/sarif_gate.py --level note "$work/bandit.sarif" | grep -q '4 result(s)' || bad "the Bandit SARIF must hold all 4 issues"
ok "the Bandit SARIF holds every issue and is readable by the same gate"

echo "6. check_exceptions.py"
if python3 -c 'import yaml' 2>/dev/null; then
  ex="$work/ex"
  mkdir -p "$ex/security" "$ex/backend/app"
  cat > "$ex/security/exceptions.yaml" <<'YAML'
exceptions:
  - id: EXC-0001
    status: approved
    tool: trivy-image
    finding: CVE-2026-1111
    scope: "kairos-api image, package libfoo@1.0"
    classification: accepted_risk
    severity: high
    justification: No fixed version exists and the code path is not reachable.
    compensating_controls: ["read-only container filesystem", "non-root user"]
    requested_by: developer
    approved_by: "security-champion (Adam Chokri)"
    created: 2026-11-20
    expires: 2026-12-20
    issue: "https://github.com/AdamChokri/kairos/issues/10"
    pull_request: "https://github.com/AdamChokri/kairos/pull/11"
YAML
  cat > "$ex/.trivyignore.yaml" <<'YAML'
vulnerabilities:
  - id: CVE-2026-1111
    statement: "EXC-0001 - see security/exceptions.yaml"
    expired_at: 2026-12-20
YAML
  check() { python3 -I "$ROOT/ci/scripts/check_exceptions.py" --root "$ex" --today "$1"; }
  expect_exit 0 "a valid exception with its marker passes" check 2026-11-25
  if grep -q 'WARN' "$work/out.txt"; then bad "no warning expected 25 days before expiry"; fi
  expect_exit 0 "an exception ending within 7 days still passes" check 2026-12-15
  grep -q 'WARN' "$work/out.txt" || bad "an exception ending within 7 days must be listed as a warning"
  ok "... and is listed as a warning"
  expect_exit 1 "an expired exception fails the build" check 2026-12-21
  grep -q 'EXPIRED' "$work/out.txt" || bad "the failure must say the exception is expired"
  ok "the failure says it is expired"
  sed -i 's/expires: 2026-12-20/expires: 2027-01-30/; s/expired_at: 2026-12-20/expired_at: 2027-01-30/' "$ex/security/exceptions.yaml" "$ex/.trivyignore.yaml"
  expect_exit 1 "High for 71 days is refused (maximum 30)" check 2026-11-25
  sed -i 's/expires: 2027-01-30/expires: 2026-12-20/; s/expired_at: 2027-01-30/expired_at: 2026-12-20/' "$ex/security/exceptions.yaml" "$ex/.trivyignore.yaml"
  sed -i 's/expired_at: 2026-12-20/expired_at: 2026-12-19/' "$ex/.trivyignore.yaml"
  expect_exit 1 "Trivy's expired_at must equal the register's expires" check 2026-11-25
  sed -i 's/expired_at: 2026-12-19/expired_at: 2026-12-20/' "$ex/.trivyignore.yaml"
  printf 'vulnerabilities: []\n' > "$ex/.trivyignore.yaml"
  expect_exit 1 "an approved entry without its marker fails" check 2026-11-25
  printf '# EXC-0001: reason\nx = 1  # nosec B101\n# EXC-0002: not in the register\ny = 2\n' > "$ex/backend/app/a.py"
  expect_exit 1 "a marker whose entry is not in the register fails" check 2026-11-25
  rm "$ex/backend/app/a.py"
  sed -i 's/security-champion (Adam Chokri)/developer/' "$ex/security/exceptions.yaml"
  printf 'vulnerabilities:\n  - id: CVE-2026-1111\n    statement: "EXC-0001"\n    expired_at: 2026-12-20\n' > "$ex/.trivyignore.yaml"
  expect_exit 1 "approval by anyone but the security champion fails" check 2026-11-25
  sed -i 's/approved_by: "developer"/approved_by: "security-champion (Adam Chokri)"/' "$ex/security/exceptions.yaml"
  printf '# an example in a comment: statement "EXC-0042"\nvulnerabilities:\n  - id: CVE-2026-1111\n    statement: "EXC-0001 - see security/exceptions.yaml"\n    expired_at: 2026-12-20\n' > "$ex/.trivyignore.yaml"
  expect_exit 0 "an EXC id in a comment of .trivyignore.yaml is not a marker" check 2026-11-25
  expect_exit 0 "the repository's own register and suppression files agree" python3 -I "$ROOT/ci/scripts/check_exceptions.py"
else
  echo "  SKIP  check_exceptions.py: PyYAML is not installed (Ubuntu: sudo apt install python3-yaml)"
fi

printf 'test-ci-scripts: %s checks passed\n' "$passed"
