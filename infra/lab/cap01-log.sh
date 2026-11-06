#!/usr/bin/env bash
# infra/lab/cap01-log.sh PHASE [--dry-run] - CAP-01 (docs/lab/capacity.md): runs
# infra/lab/host-report.sh optiplex, prints its report, and adds one row to the CAP-01 log table:
#   | date | PHASE | C: free (GB) | existing growth room (GB) | action |
# It changes only docs/lab/capacity.md, and only by that one row. A second run on the same day for
# the same phase adds nothing. Exit codes: 0 logged (or already logged), 3 logged but C: is below
# the 25 GB of CAP-01 (the action there is decided again), 1 anything else went wrong.
# Run it from WSL2 on the Legion, in the repository. VHDX volume of the OptiPlex: C (plan section 3.1).
# CAP01_REPORT_FILE=<file> reads a saved report instead of running host-report.sh (used by the tests).
set -Eeuo pipefail

repo=$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)
doc="${CAP01_DOC:-$repo/docs/lab/capacity.md}"
volume=C
threshold=25

phase=${1:-}
dry=no
[[ ${2:-} == --dry-run ]] && dry=yes
[[ -n $phase ]] || { echo "usage: bash infra/lab/cap01-log.sh \"P2 (WP2.1)\" [--dry-run]" >&2; exit 1; }
[[ $phase =~ ^[A-Za-z0-9\ ().,-]{1,40}$ ]] || { echo "ERROR: the phase label may hold letters, digits, spaces and ().,- only" >&2; exit 1; }
[[ -f $doc ]] || { echo "ERROR: $doc not found - run this inside the repository" >&2; exit 1; }
grep -q '^\*\*CAP-01 log\*\*$' "$doc" || { echo "ERROR: the '**CAP-01 log**' heading is missing from $doc" >&2; exit 1; }

report=$(mktemp)
trap 'rm -f "$report"' EXIT
if [[ -n ${CAP01_REPORT_FILE:-} ]]; then
  tr -d '\r' < "$CAP01_REPORT_FILE" > "$report"
else
  bash "$repo/infra/lab/host-report.sh" optiplex | tr -d '\r' > "$report"
fi
cat "$report"
echo

# Numbers: "  C:  size   237.4   free    94.4" and, under the "Room ..." heading, "  C:     51.1".
num='[0-9]+([.,][0-9]+)?'
free=$(sed -nE "s/^ *${volume}: +size +${num} +free +(${num})\$/\\2/p" "$report" | head -n 1)
room=$(awk -v v="${volume}:" '/^Room the existing dynamic disks/ {on=1; next} on && $1 == v {print $2; exit}' "$report")
free=${free/,/.}
room=${room/,/.}
[[ $free =~ ^[0-9]+(\.[0-9]+)?$ ]] || { echo "ERROR: could not read the free space of ${volume}: from the report above" >&2; exit 1; }
[[ -n $room ]] || room=0
[[ $room =~ ^[0-9]+(\.[0-9]+)?$ ]] || { echo "ERROR: could not read the growth room of ${volume}: from the report above" >&2; exit 1; }

below=no
awk -v f="$free" -v t="$threshold" 'BEGIN { exit !(f < t) }' && below=yes
if [[ $below == yes ]]; then
  action="BELOW ${threshold} GB: decide again (CAP-01, CAP-03)"
else
  action="none"
fi
row="| $(date +%F) | ${phase} | ${free} | ${room} | ${action} |"
echo "CAP-01 row: $row"

if [[ $dry == yes ]]; then
  echo "(--dry-run: nothing written)"
else
  python3 - "$doc" "$row" <<'PY'
import os, sys, tempfile

path, row = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8", newline="") as handle:
    text = handle.read()
newline = "\r\n" if "\r\n" in text else "\n"
lines = text.split(newline)
try:
    start = lines.index("**CAP-01 log**")
except ValueError:
    sys.exit("ERROR: the CAP-01 log heading is missing")
index = start + 1
while index < len(lines) and not lines[index].startswith("|"):
    index += 1            # blank line between the heading and the table
first = index
while index < len(lines) and lines[index].startswith("|"):
    index += 1
if first == index:
    sys.exit("ERROR: no table follows the CAP-01 log heading")
key = row.split("|")[1:3]
for line in lines[first:index]:
    if line.split("|")[1:3] == key:
        print("CAP-01: this phase is already logged today - nothing added")
        sys.exit(0)
lines.insert(index, row)
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".cap01-")
with os.fdopen(fd, "w", encoding="utf-8", newline="") as out:
    out.write(newline.join(lines))
os.chmod(tmp, os.stat(path).st_mode & 0o777)
os.replace(tmp, path)
print("CAP-01: row added to docs/lab/capacity.md")
PY
fi

if [[ $below == yes ]]; then
  echo "CAP-01: ${volume}: has ${free} GB free, below ${threshold} GB - stop and decide before going on."
  exit 3
fi
echo "CAP-01: ${volume}: has ${free} GB free (threshold ${threshold} GB) - go on."
