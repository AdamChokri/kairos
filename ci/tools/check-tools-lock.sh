#!/usr/bin/env bash
# ci/tools/check-tools-lock.sh - the toolkit is consistent (plan WP4.2). Checks, offline:
#   1. ci/tools/tools.lock is well formed: unique names, an explicit tag (never latest), a real digest;
#   2. nothing in it, and no install script, names a release of ci/tools/denylist.txt;
#   3. the tool versions agree everywhere they are pinned: the lock, the install scripts and hooks of P3,
#      .pre-commit-config.yaml and backend/pyproject.toml. One version of each tool, wherever it runs.
# `--allow-placeholder` accepts digests of zeros (right after a tag changed, before pin-tools.sh ran).
# Run by preflight and by `make hooks-selftest`. Needs bash, awk, grep and sed. Exit code 1 on any problem.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOCK="$ROOT/ci/tools/tools.lock"
DENY="$ROOT/ci/tools/denylist.txt"
allow_placeholder=0
[[ ${1:-} == --allow-placeholder ]] && allow_placeholder=1

problems=0
bad() { printf 'FAIL  %s\n' "$1"; problems=$((problems + 1)); }

declare -A image_of version_of
while read -r name image digest pushed verified extra; do
  [[ -z $name || $name == \#* ]] && continue
  if [[ -z ${verified:-} || -n ${extra:-} ]]; then bad "tools.lock: $name: expected 5 columns (name image digest pushed verified-by)"; continue; fi
  [[ -z ${image_of[$name]:-} ]] || bad "tools.lock: $name appears twice"
  image_of[$name]=$image
  [[ $image == *:* && $image != *:latest && $image != *@* ]] || bad "tools.lock: $name: $image needs an explicit tag, not latest, and no digest in this column"
  version_of[$name]="${image##*:}"
  if [[ ! $digest =~ ^sha256:[0-9a-f]{64}$ ]]; then
    bad "tools.lock: $name: the digest is not sha256:<64 hex>"
  elif [[ $digest =~ ^sha256:0{64}$ ]] && (( ! allow_placeholder )); then
    bad "tools.lock: $name: the digest is a placeholder: run ci/tools/pin-tools.sh"
  fi
  [[ $pushed == - || $pushed =~ ^20[0-9]{2}-[0-9]{2}-[0-9]{2}$ ]] || bad "tools.lock: $name: the pushed date is not YYYY-MM-DD or -"
  # The denylist (kind name version reason): a "tool" line matches the end of the repository name and the version.
  while read -r kind dname dversion _; do
    [[ -z $kind || $kind == \#* ]] && continue
    repo="${image%%:*}"
    if [[ $kind == tool && ${repo##*/} == "$dname" && ${image##*:} == "$dversion" ]]; then bad "denylist: $name pins $dname $dversion"; fi
    if [[ $kind == image && $repo == "$dname" ]]; then bad "denylist: $name uses the refused image $dname"; fi
  done < "$DENY"
done < "$LOCK"
(( ${#image_of[@]} >= 5 )) || bad "tools.lock: fewer than 5 tools: is it the right file?"

# first_match FILE REGEX - the first capture group of the first line that matches.
first_match() { sed -nE "s/$2/\\1/p" "$1" | head -1; }
same() { # LABEL A B
  if [[ -z $2 || -z $3 ]]; then bad "$1: a pin could not be read (A='$2', B='$3')"
  elif [[ $2 != "$3" ]]; then bad "$1: $2 is not $3"
  else printf 'ok    %s %s\n' "$1" "$2"; fi
}

same "trivy: lock and install-scan-tools.sh" "${version_of[trivy]:-}" "$(first_match "$ROOT/ci/tools/install-scan-tools.sh" '^TRIVY_VERSION="([^"]+)".*')"
same "trivy: lock and hook-trivy.sh" "${version_of[trivy]:-}" "$(first_match "$ROOT/ci/tools/hook-trivy.sh" '^TRIVY_PINNED="([^"]+)".*')"
same "gitleaks: lock and commit-scan.sh" "${version_of[gitleaks]#v}" "$(first_match "$ROOT/ci/tools/commit-scan.sh" '^GITLEAKS_PINNED="([^"]+)".*')"
same "gitleaks: lock and .gitleaks.toml" "${version_of[gitleaks]:-}" "$(first_match "$ROOT/.gitleaks.toml" '^minVersion = "([^"]+)".*')"
same "hadolint: lock and install-scan-tools.sh" "${version_of[hadolint]#v}" "$(first_match "$ROOT/ci/tools/install-scan-tools.sh" '^HADOLINT_VERSION="([^"]+)".*')"
same "semgrep: lock and .pre-commit-config.yaml" "${version_of[semgrep]:-}" "$(awk '/repo: https:\/\/github.com\/semgrep\/pre-commit/ {f=1} f && /frozen:/ {print $NF; exit}' "$ROOT/.pre-commit-config.yaml" | sed 's/^v//')"
same "bandit: pyproject.toml and .pre-commit-config.yaml" "$(first_match "$ROOT/backend/pyproject.toml" '^ *"bandit==([^"]+)",.*')" "$(awk '/repo: https:\/\/github.com\/PyCQA\/bandit/ {f=1} f && /frozen:/ {print $NF; exit}' "$ROOT/.pre-commit-config.yaml")"
same "ruff: pyproject.toml and .pre-commit-config.yaml" "$(first_match "$ROOT/backend/pyproject.toml" '^ *"ruff==([^"]+)",.*')" "$(awk '/repo: https:\/\/github.com\/astral-sh\/ruff-pre-commit/ {f=1} f && /frozen:/ {print $NF; exit}' "$ROOT/.pre-commit-config.yaml" | sed 's/^v//')"
same "python: lock and pyproject.toml (major.minor)" "$(sed -E 's/^([0-9]+\.[0-9]+).*/\1/' <<<"${version_of[python]:-}")" "$(first_match "$ROOT/backend/pyproject.toml" '^requires-python = ">=([0-9]+\.[0-9]+)".*')"

node="$(tr -d '[:space:]' < "$ROOT/ci/tools/node-image.txt")"
if [[ $node =~ ^node:[0-9.]+-slim@sha256:[0-9a-f]{64}$ ]]; then
  printf 'ok    node image %s\n' "${node%%@*}"
else
  bad "ci/tools/node-image.txt does not hold a pinned node image"
fi

# The scan-tool installers must not install a denylisted release either.
while read -r kind dname dversion _; do
  [[ $kind == tool ]] || continue
  if grep -qE "^(${dname^^}_VERSION|${dname^^}_PINNED)=\"${dversion//./\\.}\"" "$ROOT/ci/tools/install-scan-tools.sh" "$ROOT/ci/tools/hook-trivy.sh"; then
    bad "denylist: an install script pins $dname $dversion"
  fi
done < <(grep -vE '^[[:space:]]*(#|$)' "$DENY")

if (( problems > 0 )); then printf 'check-tools-lock: %s problem(s)\n' "$problems"; exit 1; fi
printf 'check-tools-lock: %s tools, one version of each everywhere, none on the denylist\n' "${#image_of[@]}"
