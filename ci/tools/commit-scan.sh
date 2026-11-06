#!/usr/bin/env bash
# ci/tools/commit-scan.sh - the commit-time secret scan (plan WP3.2, E-11, D-23).
#
# Scans what is staged with the pinned Gitleaks and the repository's .gitleaks.toml, then compares
# the findings with security/seeded-secrets.tsv, the list of fake secrets that the seeded
# weakness SV-01 puts in the repository on purpose:
#   - a finding that is not in the list        -> blocked;
#   - a listed file that is staged without its finding (or with more) -> blocked: the seeded
#     weakness was changed without updating the list.
# The JSON report lives in /dev/shm for the length of the run, findings are redacted, and no
# secret is ever printed. Nothing is ignored by fingerprint: the list is the only exception.
#
#   bash ci/tools/commit-scan.sh          (also what the pre-commit hook "gitleaks" runs)
# Needs bash, git, python3 and Gitleaks 8.30.1 on the PATH. Exit code 0: nothing unexpected.
set -Eeuo pipefail

GITLEAKS_PINNED="8.30.1"
ROOT="$(git rev-parse --show-toplevel)"
TABLE="${SEEDED_SECRETS_TABLE:-$ROOT/security/seeded-secrets.tsv}"
GUIDE="docs/secure-coding.md#hard-coded-secrets"

die() { printf 'commit-scan: %s\n' "$1" >&2; exit 2; }

command -v gitleaks >/dev/null || die "gitleaks is not installed (version $GITLEAKS_PINNED is pinned: plan D-12)"
found="$(gitleaks version | tr -d '[:space:]')"
found="${found#v}"
[[ "$found" == "$GITLEAKS_PINNED" ]] || die "gitleaks $found is installed, $GITLEAKS_PINNED is pinned (change the pin through a pull request)"
[[ -f "$TABLE" ]] || die "$TABLE is missing"
[[ -d /dev/shm ]] || die "/dev/shm is not available for the report"

REPORT="$(mktemp /dev/shm/commit-scan.XXXXXX)"
trap 'rm -f "$REPORT"' EXIT

cd "$ROOT"
set +e
gitleaks git --pre-commit --staged --redact --no-banner --exit-code 2 \
  --report-format json --report-path "$REPORT" . >/dev/null 2>&1
status=$?
set -e
[[ "$status" -eq 0 || "$status" -eq 2 ]] || die "gitleaks failed (exit $status): run it by hand to see why"

STAGED="$(git diff --cached --name-only --diff-filter=ACMR)"

STAGED="$STAGED" python3 - "$REPORT" "$TABLE" "$GUIDE" <<'PY'
import collections
import json
import os
import sys

report_path, table_path, guide = sys.argv[1:4]
staged = {line for line in os.environ["STAGED"].splitlines() if line}

expected = {}
with open(table_path, encoding="utf-8") as table:
    for number, raw in enumerate(table, 1):
        line = raw.rstrip("\n")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        fields = line.split("\t")
        if len(fields) != 3 or not fields[2].isdigit():
            sys.exit(f"commit-scan: {table_path} line {number}: expected file<TAB>rule<TAB>count")
        expected[(fields[0], fields[1])] = int(fields[2])

with open(report_path, encoding="utf-8") as report:
    content = report.read().strip()
findings = json.loads(content) if content else []

seen = collections.Counter((f["File"], f["RuleID"]) for f in findings)
problems = []

for (path, rule), count in sorted(seen.items()):
    allowed = expected.get((path, rule), 0)
    if count > allowed:
        lines = sorted(f["StartLine"] for f in findings if f["File"] == path and f["RuleID"] == rule)
        where = ", ".join(f"{path}:{n}" for n in lines)
        problems.append(
            f"BLOCKED  {rule} at {where}\n"
            f"         A secret in a commit stays in the public history even after a revert.\n"
            f"         Read it from the environment or a secret file instead: {guide}"
        )

for (path, rule), count in sorted(expected.items()):
    if path in staged and seen.get((path, rule), 0) != count:
        problems.append(
            f"CHANGED  {path} is staged but its seeded {rule} finding is "
            f"{seen.get((path, rule), 0)}, not {count}.\n"
            f"         If the weakness SV-01 was fixed, remove the row from {table_path.split('/')[-1]}"
            f" in the same commit; otherwise the seeded secret must stay as it was."
        )

if problems:
    print("\n".join(problems))
    sys.exit(1)

accepted = sum(count for key, count in expected.items() if key[0] in staged)
if accepted:
    print(f"commit-scan: {accepted} seeded secret(s) of SV-01 accepted (security/seeded-secrets.tsv)")
print("commit-scan: OK")
PY
