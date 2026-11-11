#!/usr/bin/env bash
# ci/scripts/lib.sh - sourced by every control script in ci/scripts/ (never run by itself).
#
# The exit-code protocol (decision D-11), the same for every control:
#   0  the control passed
#   1  blocked: findings above the threshold and the control is in `enforce` mode
#   2  would block: findings above the threshold and the control is in `report` mode (the stage turns yellow)
#   3  the tool or the script failed (anything unexpected also ends as 3): the build fails, closed
# A script never lets a crashed tool look like a verdict: the ERR trap below turns any failing command
# into exit 3, and only `verdict` produces 0, 1 or 2.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPORTS="$ROOT/reports"
mkdir -p "$REPORTS"

die() { printf '%s: %s\n' "${CONTROL:-lib}" "$1" >&2; exit 3; }
on_error() {
  printf '%s: a command failed (exit %s) at line %s\n' "${CONTROL:-script}" "$1" "$2" >&2
  exit 3
}
trap 'on_error $? $LINENO' ERR

# Thresholds and modes (security/policy/gates.env). Every variable it sets becomes available here.
set -a
# shellcheck source=/dev/null
source "$ROOT/security/policy/gates.env"
set +a

# tool_ref NAME - prints image:tag@sha256:digest for a tool of ci/tools/tools.lock (the Node image comes from
# ci/tools/node-image.txt). A placeholder digest is refused: run ci/tools/pin-tools.sh first.
tool_ref() {
  local name=$1 image digest
  if [[ $name == node ]]; then
    tr -d '[:space:]' < "$ROOT/ci/tools/node-image.txt"
    echo
    return
  fi
  read -r image digest < <(awk -v n="$name" '$1 == n { print $2, $3 }' "$ROOT/ci/tools/tools.lock")
  [[ -n ${image:-} ]] || die "no tool named $name in ci/tools/tools.lock"
  [[ ${digest:-} =~ ^sha256:[0-9a-f]{64}$ && ! $digest =~ ^sha256:0{64}$ ]] ||
    die "the digest of $name in ci/tools/tools.lock is a placeholder: run ci/tools/pin-tools.sh"
  printf '%s@%s\n' "$image" "$digest"
}

# mode_of CONTROL - report or enforce, from MODE_<CONTROL> in gates.env.
mode_of() {
  local var="MODE_$1"
  local value="${!var:-}"
  [[ $value == report || $value == enforce ]] || die "$var in security/policy/gates.env must be report or enforce"
  printf '%s\n' "$value"
}

# verdict CONTROL BLOCKED_COUNT - ends the script with 0, 1 or 2 and says why in one line.
verdict() {
  local control=$1 blocked=$2 mode
  mode="$(mode_of "$3")"
  if (( blocked == 0 )); then
    printf '%s: passed (mode %s)\n' "$control" "$mode"
    exit 0
  fi
  if [[ $mode == enforce ]]; then
    printf '%s: BLOCKED, %s finding(s) above the threshold (mode enforce)\n' "$control" "$blocked"
    exit 1
  fi
  printf '%s: %s finding(s) above the threshold; the control is in report mode, so the build is only marked unstable\n' "$control" "$blocked"
  exit 2
}

# run_tool [run-tool.sh options] TOOL ARGS... - one sandboxed container (ci/scripts/run-tool.sh).
run_tool() { "$ROOT/ci/scripts/run-tool.sh" "$@"; }
