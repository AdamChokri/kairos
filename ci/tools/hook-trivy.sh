#!/usr/bin/env bash
# ci/tools/hook-trivy.sh FILE... - the push-stage Trivy check (plan WP3.2). It scans only the files it
# is given (the lockfiles and Dockerfiles of the push) with the pinned Trivy, and applies the gate of
# plan section 4.2: Critical always blocks, High blocks when a fixed version exists, and for a
# Dockerfile any High or Critical misconfiguration blocks.
#
# The weaknesses seeded on purpose (SV-07: two vulnerable packages; SV-09: two naive Dockerfiles) pass
# through ONE exact list, security/seeded-trivy.tsv, for this hook only (CI reports them all): a row is
# "file<TAB>package<TAB>installed version" or "file<TAB>check id<TAB>-". A different package, another
# version or another check is blocked. WP4.5 removed the rows as it fixed the weaknesses and deleted the
# file: with no file, nothing is accepted.
#
#   bash ci/tools/hook-trivy.sh backend/uv.lock frontend/Dockerfile
# Needs bash, python3 and Trivy 0.76.1 (ci/tools/install-scan-tools.sh). The first run downloads
# Trivy's databases (about a minute); later runs use the cache. Exit code 0: nothing unexpected.
set -Eeuo pipefail

TRIVY_PINNED="0.76.1"
ROOT="$(git rev-parse --show-toplevel)"
TABLE="${SEEDED_TRIVY_TABLE:-$ROOT/security/seeded-trivy.tsv}"

die() { printf 'hook-trivy: %s\n' "$1" >&2; exit 2; }
command -v trivy >/dev/null || die "trivy is not installed - run: bash ci/tools/install-scan-tools.sh"
found="$(trivy --version | awk 'NR==1 {print $2}')"
[[ "$found" == "$TRIVY_PINNED" ]] || die "trivy $found is installed, $TRIVY_PINNED is pinned (plan D-12)"
(( $# > 0 )) || exit 0

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cd "$ROOT"

n=0
: > "$work/index.tsv"
for file in "$@"; do
  n=$((n + 1))
  case "$(basename "$file")" in
    Dockerfile*)
      trivy config --quiet --severity HIGH,CRITICAL --format json --output "$work/$n.json" "$file" ||
        die "trivy could not scan $file (exit $?): run it by hand to see why" ;;
    uv.lock|package-lock.json)
      trivy fs --quiet --scanners vuln --severity HIGH,CRITICAL --format json --output "$work/$n.json" "$file" ||
        die "trivy could not scan $file (exit $?): run it by hand to see why" ;;
    *) continue ;;
  esac
  printf '%s\t%s\n' "$n" "$file" >> "$work/index.tsv"
done

python3 -I - "$work" "$TABLE" <<'PY'
import json
import sys
from pathlib import Path

work, table = Path(sys.argv[1]), Path(sys.argv[2])
guide = "docs/secure-coding.md and the plan, section 4.2 (a fix, or a time-boxed exception: WP4.4)"

allowed: set[tuple[str, str, str]] = set()
lines = table.read_text(encoding="utf-8").splitlines() if table.exists() else []
for number, raw in enumerate(lines, 1):
    if not raw.strip() or raw.lstrip().startswith("#"):
        continue
    fields = raw.split("\t")
    if len(fields) != 3:
        sys.exit(f"hook-trivy: {table.name} line {number}: expected file<TAB>name<TAB>version")
    allowed.add((fields[0], fields[1].lower(), fields[2]))

problems: list[str] = []
accepted = 0
for line in (work / "index.tsv").read_text(encoding="utf-8").splitlines():
    number, file = line.split("\t")
    content = (work / f"{number}.json").read_text(encoding="utf-8").strip()
    results = json.loads(content).get("Results") or [] if content else []
    for result in results:
        for vuln in result.get("Vulnerabilities") or []:
            severity, fixed = vuln.get("Severity"), vuln.get("FixedVersion") or ""
            if not (severity == "CRITICAL" or (severity == "HIGH" and fixed)):
                continue
            name, installed = vuln["PkgName"], vuln["InstalledVersion"]
            if (file, name.lower(), installed) in allowed:
                accepted += 1
                continue
            problems.append(
                f"BLOCKED  {vuln['VulnerabilityID']} ({severity}) in {name} {installed}, {file}\n"
                f"         {'Fixed in ' + fixed + '.' if fixed else 'No fixed version exists yet.'} "
                f"Upgrade the package, or see {guide}"
            )
        for miss in result.get("Misconfigurations") or []:
            if miss.get("Status", "FAIL") != "FAIL" or miss.get("Severity") not in ("HIGH", "CRITICAL"):
                continue
            if (file, miss["ID"].lower(), "-") in allowed:
                accepted += 1
                continue
            problems.append(
                f"BLOCKED  {miss['ID']} ({miss['Severity']}) {miss.get('Title', '')}, {file}\n"
                f"         {miss.get('Message', '').strip()}\n"
                f"         See {guide}"
            )

if problems:
    print("\n".join(problems))
    sys.exit(1)
if accepted:
    print(f"hook-trivy: {accepted} seeded finding(s) of SV-07 and SV-09 accepted ({table.name})")
print("hook-trivy: OK")
PY
