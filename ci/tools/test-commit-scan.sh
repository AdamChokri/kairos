#!/usr/bin/env bash
# ci/tools/test-commit-scan.sh - proves ci/tools/commit-scan.sh in a throwaway repository:
# the seeded secrets are accepted, anything else is blocked, and a changed seeded file is caught.
#   bash ci/tools/test-commit-scan.sh        Needs bash, git, python3 and the pinned Gitleaks.
set -Eeuo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/commit-scan.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0

# A fresh fake secret every run, so no secret-shaped value is ever written in this file.
fake() { python3 -c 'import secrets; print(secrets.token_hex(24))'; }

setup() {
  cd "$WORK"
  rm -rf repo && mkdir repo && cd repo
  git init -q -b main
  git config user.email test@example.invalid
  git config user.name test
  printf 'title = "test"\n[extend]\nuseDefault = true\n' >.gitleaks.toml
  mkdir -p security app
  printf '# file\trule\tcount\napp/seeded.py\tgeneric-api-key\t1\n' >security/seeded-secrets.tsv
  git add -A && git commit -q -m baseline
}

# expect NAME WANTED_EXIT -- runs the scan and compares the exit code.
expect() {
  local name="$1" wanted="$2" status=0 output
  output="$(bash "$SCRIPT" 2>&1)" || status=$?
  if [[ "$status" -eq "$wanted" ]]; then
    printf '  PASS  %s\n' "$name"
  else
    printf '  FAIL  %s (exit %s, wanted %s)\n%s\n' "$name" "$status" "$wanted" "$output"
    failures=$((failures + 1))
  fi
  LAST_OUTPUT="$output"
}

setup
echo 'x = 1' >app/plain.py
git add -A
expect "a commit without secrets passes" 0

setup
printf 'JWT_SECRET_KEY = "%s"\n' "$(fake)" >app/seeded.py
git add -A
expect "the listed seeded secret is accepted" 0
[[ "$LAST_OUTPUT" == *"1 seeded secret(s)"* ]] || { echo "  FAIL  the accepted secret is reported"; failures=$((failures + 1)); }

setup
printf 'JWT_SECRET_KEY = "%s"\n' "$(fake)" >app/seeded.py
printf 'API_KEY = "%s"\n' "$(fake)" >app/other.py
git add -A
expect "a secret outside the list is blocked" 1
[[ "$LAST_OUTPUT" =~ [0-9a-f]{40} ]] && { echo "  FAIL  the output shows a secret"; failures=$((failures + 1)); }
[[ "$LAST_OUTPUT" == *"BLOCKED  generic-api-key at app/other.py"* ]] || { echo "  FAIL  the blocked file is named"; failures=$((failures + 1)); }

setup
printf 'JWT_SECRET_KEY = "%s"\n' "$(fake)" >app/seeded.py
printf 'JWT_SECRET_KEY = "%s"\n' "$(fake)" >>app/seeded.py
git add -A
expect "a second secret in a listed file is blocked" 1

setup
printf 'JWT_SECRET_KEY = "read from a secret file"\n' >app/seeded.py
git add -A
expect "a listed file staged without its secret is caught" 1
[[ "$LAST_OUTPUT" == *"CHANGED  app/seeded.py"* ]] || { echo "  FAIL  the changed file is named"; failures=$((failures + 1)); }

setup
git add -A
expect "a listed file that is not staged is not checked" 0

if [[ "$failures" -eq 0 ]]; then
  echo "All commit-scan checks passed."
else
  echo "$failures check(s) failed."
  exit 1
fi
