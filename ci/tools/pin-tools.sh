#!/usr/bin/env bash
# ci/tools/pin-tools.sh [--check] [NAME...] - resolves the digest of every tag of ci/tools/tools.lock again,
# as the registry serves it now (plan WP4.2, D-08, D-12), and refuses a tag that is younger than 7 days.
#   --check   changes nothing: prints OK or DIFFERENT for each tool and exits 1 if any differs
#   (none)    rewrites the digest and the pushed date of the rows that differ; review with git diff
# The pushed date comes from Docker Hub's tag API (docker.io images only); a row of "-" keeps its "-".
# The Trivy image is also verified with Sigstore: the signature must come from the release workflows of
# aquasecurity/trivy (cosign, keyless). Needs curl, python3, and cosign for the Trivy row (P1).
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOCK="$ROOT/ci/tools/tools.lock"
RESOLVE="$ROOT/ci/tools/resolve-digest.sh"
check=0
[[ ${1:-} == --check ]] && { check=1; shift; }
want=("$@")
selected() { (( ${#want[@]} == 0 )) && return 0; local w; for w in "${want[@]}"; do [[ $w == "$1" ]] && return 0; done; return 1; }

today="$(date -u +%F)"
differs=0
mapfile -t rows < "$LOCK"
for row in "${rows[@]}"; do
  [[ $row =~ ^([a-z][a-z0-9-]*)[[:space:]]+([^[:space:]]+)[[:space:]]+(sha256:[0-9a-f]{64})[[:space:]]+([0-9-]+)[[:space:]]+([^[:space:]]+)$ ]] || continue
  name=${BASH_REMATCH[1]} image=${BASH_REMATCH[2]} digest=${BASH_REMATCH[3]} pushed=${BASH_REMATCH[4]} how=${BASH_REMATCH[5]}
  selected "$name" || continue
  now="$("$RESOLVE" "$image")"; now="${now##*@}"

  newpushed="-"
  repo="${image%%:*}" tag="${image##*:}"
  if [[ $repo != */*/* ]]; then   # Docker Hub: namespace/name or an official image
    [[ $repo == */* ]] || repo="library/$repo"
    newpushed="$(curl -fsS -m 20 "https://hub.docker.com/v2/repositories/$repo/tags/$tag" |
      python3 -I -c 'import json, sys; print((json.load(sys.stdin).get("tag_last_pushed") or "-")[:10])')" || newpushed="-"
  fi
  if [[ $newpushed != - ]]; then
    age=$(( ( $(date -u -d "$today" +%s) - $(date -u -d "$newpushed" +%s) ) / 86400 ))
    (( age >= 7 )) || { printf 'REFUSED    %-14s %s was pushed %s, %s day(s) ago: the 7-day rule (D-12) says wait\n' "$name" "$image" "$newpushed" "$age" >&2; exit 1; }
  fi

  if [[ $how == cosign ]]; then
    command -v cosign >/dev/null || { echo "pin-tools: cosign is needed for the $name row" >&2; exit 2; }
    cosign verify "${image%%:*}@$now" \
      --certificate-identity-regexp 'https://github\.com/aquasecurity/trivy/\.github/workflows/.+' \
      --certificate-oidc-issuer https://token.actions.githubusercontent.com >/dev/null 2>&1 ||
      { printf 'NOT SIGNED %-14s %s@%s has no valid signature of the aquasecurity release workflows\n' "$name" "$repo" "$now" >&2; exit 1; }
    sig="signature verified"
  else
    sig=""
  fi

  if [[ $now == "$digest" ]]; then
    printf 'OK         %-14s %s %s %s\n' "$name" "$image" "${now:0:19}…" "$sig"
    continue
  fi
  differs=$((differs + 1))
  if (( check )); then
    printf 'DIFFERENT  %-14s %s\n             lock     %s\n             registry %s\n' "$name" "$image" "$digest" "$now"
  else
    python3 -I - "$LOCK" "$name" "$digest" "$now" "$pushed" "$newpushed" <<'PY'
import re, sys
path, name, old, new, old_date, new_date = sys.argv[1:]
lines = open(path).read().split("\n")
hits = 0
for i, line in enumerate(lines):
    if re.match(rf"{re.escape(name)}\s", line) and old in line:
        line = line.replace(old, new)
        if new_date != "-":
            line = line.replace(f"  {old_date}  ", f"  {new_date}  ")
        lines[i] = line
        hits += 1
if hits != 1:
    sys.exit(f"pin-tools: expected one row for {name}, found {hits}")
open(path, "w").write("\n".join(lines))
PY
    printf 'PINNED     %-14s %s\n             was %s\n             now %s\n' "$name" "$image" "$digest" "$now"
  fi
done
if (( check && differs > 0 )); then echo "pin-tools: $differs tool(s) differ from the registry"; exit 1; fi
echo "pin-tools: done"
