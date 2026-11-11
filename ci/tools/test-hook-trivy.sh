#!/usr/bin/env bash
# ci/tools/test-hook-trivy.sh - proves ci/tools/hook-trivy.sh without a network, with a stand-in for
# Trivy that prints canned reports in Trivy's JSON format: the seeded findings are accepted, anything
# else is blocked (another package, another version, a new Dockerfile check, a Critical without a fix),
# and a High without a fix is not a block (plan section 4.2).
#   bash ci/tools/test-hook-trivy.sh        Needs bash, git and python3.
set -Eeuo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hook-trivy.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0

mkdir -p "$WORK/bin" "$WORK/repo/backend" "$WORK/repo/frontend" "$WORK/repo/security"
cat > "$WORK/bin/trivy" <<'STUB'
#!/usr/bin/env bash
# Stand-in for Trivy 0.76.1: `trivy --version`, and `trivy fs|config ... --output FILE TARGET`.
if [[ ${1:-} == --version ]]; then echo "Version: 0.76.1"; exit 0; fi
out=""; target=""
while (( $# )); do
  case $1 in --output) out=$2; shift 2 ;; --*) shift ;; *) target=$1; shift ;; esac
done
vuln() { printf '{"Results":[{"Target":"x","Vulnerabilities":[{"VulnerabilityID":"%s","PkgName":"%s","InstalledVersion":"%s","FixedVersion":"%s","Severity":"%s"}]}]}' "$@"; }
miss() { printf '{"Results":[{"Target":"Dockerfile","Misconfigurations":[{"ID":"%s","Severity":"%s","Title":"t","Message":"m","Status":"FAIL"}]}]}' "$@"; }
case "$STUB_CASE:$target" in
  seeded:backend/uv.lock)            vuln CVE-2022-29217 pyjwt 2.3.0 2.4.0 HIGH ;;
  seeded:frontend/package-lock.json) vuln CVE-2019-10744 lodash 4.17.11 4.17.12 CRITICAL ;;
  seeded:backend/Dockerfile)         miss DS-0002 HIGH ;;
  seeded:frontend/Dockerfile)        miss DS-0002 HIGH ;;
  other-package:backend/uv.lock)     vuln CVE-2099-0001 requests 2.0.0 2.1.0 HIGH ;;
  other-version:backend/uv.lock)     vuln CVE-2022-29217 pyjwt 2.3.1 2.4.0 HIGH ;;
  high-no-fix:backend/uv.lock)       vuln CVE-2099-0002 somepkg 1.0.0 "" HIGH ;;
  critical-no-fix:backend/uv.lock)   vuln CVE-2099-0003 somepkg 1.0.0 "" CRITICAL ;;
  new-check:backend/Dockerfile)      miss DS-0099 CRITICAL ;;
  *)                                 echo '{"Results":[]}' ;;
esac > "$out"
STUB
chmod +x "$WORK/bin/trivy"

cd "$WORK/repo"
git init -q -b main
printf '# file\tname\tversion\nbackend/uv.lock\tpyjwt\t2.3.0\nfrontend/package-lock.json\tlodash\t4.17.11\nbackend/Dockerfile\tDS-0002\t-\nbackend/Dockerfile\tDS-0031\t-\nfrontend/Dockerfile\tDS-0002\t-\n' > security/seeded-trivy.tsv

# expect NAME CASE EXIT FILE...
expect() {
  local name=$1 case=$2 want=$3 got; shift 3
  set +e
  PATH="$WORK/bin:$PATH" STUB_CASE="$case" bash "$SCRIPT" "$@" > "$WORK/out.txt" 2>&1
  got=$?
  set -e
  if [[ $got -eq $want ]]; then
    printf '  PASS  %s\n' "$name"
  else
    printf '  FAIL  %s (exit %s, wanted %s)\n' "$name" "$got" "$want"; sed 's/^/        /' "$WORK/out.txt"; failures=$((failures + 1))
  fi
}

expect "the seeded findings of all four files are accepted" seeded 0 backend/uv.lock frontend/package-lock.json backend/Dockerfile frontend/Dockerfile
expect "another vulnerable package is blocked"              other-package 1 backend/uv.lock
expect "the seeded package at another version is blocked"   other-version 1 backend/uv.lock
expect "a High without a fixed version does not block"      high-no-fix 0 backend/uv.lock
expect "a Critical without a fixed version blocks"          critical-no-fix 1 backend/uv.lock
expect "a new Dockerfile check is blocked"                  new-check 1 backend/Dockerfile
expect "files that are not scanned are skipped"             seeded 0 backend/pyproject.toml
expect "no files, nothing to do"                            seeded 0

# WP4.5 deleted security/seeded-trivy.tsv: with no list, even the former seeded findings block.
mv security/seeded-trivy.tsv "$WORK/seeded-trivy.tsv.kept"
expect "with no list file, the former seeded finding blocks" seeded 1 backend/uv.lock
expect "with no list file, a clean lockfile passes"          none 0 backend/uv.lock
mv "$WORK/seeded-trivy.tsv.kept" security/seeded-trivy.tsv

# the message names the finding and where to read more
PATH="$WORK/bin:$PATH" STUB_CASE=other-package bash "$SCRIPT" backend/uv.lock > "$WORK/out.txt" 2>&1 || true
if grep -q 'BLOCKED  CVE-2099-0001 (HIGH) in requests 2.0.0, backend/uv.lock' "$WORK/out.txt" && grep -q 'Fixed in 2.1.0' "$WORK/out.txt"; then
  printf '  PASS  the message names the package, the version and the fix\n'
else
  printf '  FAIL  the message is not as expected\n'; sed 's/^/        /' "$WORK/out.txt"; failures=$((failures + 1))
fi

echo
if (( failures == 0 )); then echo "test-hook-trivy: all checks passed"; else echo "test-hook-trivy: $failures check(s) failed" >&2; exit 1; fi
