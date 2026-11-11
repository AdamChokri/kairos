#!/usr/bin/env bash
# ci/tools/make-gitleaks-baseline.sh - writes security/gitleaks-baseline.json (SV-01, WP4.5).
#
# Kairos v0 committed two FAKE secrets on purpose (SV-01: backend/app/config.py and deploy/.env). WP4.5 removes them
# from the files, but a public history keeps them for good: rewriting it would not take back the copies that already
# exist, and would break every signed commit and pull request that points at it (decision D-33). The history scan
# of ci/scripts/secrets_scan.sh therefore compares what it finds with this baseline, which lists exactly those two
# findings by fingerprint (commit, file, rule, line): any other secret in the history, or the same file at a new
# commit, is still reported. The baseline holds no secret (the scan runs with --redact).
#
# The script runs the pinned Gitleaks over the history of the current checkout, refuses to write anything unless
# the findings are exactly the two expected ones, and prints what it wrote. Run it once, on the branch of the SV-01
# fix, before the fix is committed or after: the history is the same.
#   bash ci/tools/make-gitleaks-baseline.sh
# Needs bash, git, python3 and Gitleaks 8.30.1 on the PATH (P0). Exit code 0: the baseline was written.
set -Eeuo pipefail

PINNED="8.30.1"
ROOT="$(git rev-parse --show-toplevel)"
OUT="$ROOT/security/gitleaks-baseline.json"

die() { printf 'make-gitleaks-baseline: %s\n' "$1" >&2; exit 2; }
command -v gitleaks >/dev/null || die "gitleaks is not installed (version $PINNED is pinned)"
found="$(gitleaks version | tr -d '[:space:]')"
[[ "${found#v}" == "$PINNED" ]] || die "gitleaks $found is installed, $PINNED is pinned"

TMP="$(mktemp /dev/shm/gitleaks-baseline.XXXXXX)"
trap 'rm -f "$TMP"' EXIT

cd "$ROOT"
status=0
gitleaks git --config .gitleaks.toml --redact --no-banner --exit-code 2 \
  --report-format json --report-path "$TMP" . >/dev/null 2>&1 || status=$?
[[ $status -eq 0 || $status -eq 2 ]] || die "gitleaks failed (exit $status): run it by hand to see why"

python3 -I - "$TMP" "$OUT" <<'PY'
import json
import sys

report, out = sys.argv[1:3]
with open(report, encoding="utf-8") as handle:
    text = handle.read().strip()
findings = json.loads(text) if text else []
seen = sorted((f["File"], f["RuleID"]) for f in findings)
expected = [("backend/app/config.py", "generic-api-key"), ("deploy/.env", "generic-api-key")]
if seen != expected:
    shown = "\n".join(f"  {rule}  {path}" for path, rule in seen) or "  (nothing)"
    sys.exit(
        "make-gitleaks-baseline: the history holds these findings, not the two seeded ones of SV-01:\n"
        + shown
        + "\nNothing was written. A finding that is not seeded is an incident: rotate it (plan 4.3), do not baseline it."
    )
findings.sort(key=lambda f: (f["File"], f["StartLine"]))
with open(out, "w", encoding="utf-8") as handle:
    json.dump(findings, handle, indent=2)
    handle.write("\n")
for finding in findings:
    print(f"baseline  {finding['RuleID']}  {finding['File']}:{finding['StartLine']}  commit {finding['Commit'][:12]}")
print(f"make-gitleaks-baseline: wrote {out.split('/')[-2]}/{out.split('/')[-1]} with {len(findings)} findings")
PY
