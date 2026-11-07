#!/usr/bin/env bash
# ci/tools/verify-hook-revs.sh - checks that every frozen `rev` of .pre-commit-config.yaml is the commit
# its `# frozen: <tag>` comment names, by asking each hook repository for the tag (plan D-12). A tag
# that was moved after pinning shows as MISMATCH. Needs git and the network; changes nothing.
#   bash ci/tools/verify-hook-revs.sh
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG="${HOOK_CONFIG:-$ROOT/.pre-commit-config.yaml}"
bad=0 checked=0 repo=""

while IFS= read -r line; do
  if [[ $line =~ ^[[:space:]]*-[[:space:]]repo:[[:space:]]+(https://[^[:space:]]+) ]]; then
    repo="${BASH_REMATCH[1]}"
  elif [[ $line =~ ^[[:space:]]+rev:[[:space:]]+([0-9a-f]{40})[[:space:]]+\#[[:space:]]frozen:[[:space:]]+([^[:space:]]+) ]]; then
    sha="${BASH_REMATCH[1]}" tag="${BASH_REMATCH[2]}"
    refs="$(git ls-remote "$repo" "refs/tags/$tag" "refs/tags/$tag^{}")" || { echo "ERROR     cannot reach $repo" >&2; exit 2; }
    # An annotated tag lists the tag object and, with ^{}, the commit it points to: the commit counts.
    actual="$(awk '/\^\{\}$/ {print $1; exit} {first = (first == "" ? $1 : first)} END {if (first != "") print first}' <<<"$refs" | head -n 1)"
    checked=$((checked + 1))
    if [[ -n $actual && $actual == "$sha" ]]; then
      printf 'OK        %-48s %-10s %s\n' "${repo#https://github.com/}" "$tag" "${sha:0:12}"
    else
      printf 'MISMATCH  %-48s %-10s pinned %s, the tag is %s\n' "${repo#https://github.com/}" "$tag" "${sha:0:12}" "${actual:-missing}"
      bad=$((bad + 1))
    fi
  elif [[ $line =~ ^[[:space:]]+rev:[[:space:]] ]]; then
    printf 'NOT FROZEN %s: %s\n' "$repo" "$line"
    bad=$((bad + 1))
  fi
done < "$CONFIG"

(( checked > 0 )) || { echo "verify-hook-revs: no frozen rev found in $CONFIG" >&2; exit 2; }
if (( bad > 0 )); then echo "verify-hook-revs: $bad problem(s)" >&2; exit 1; fi
echo "verify-hook-revs: all $checked revs are the commits of their tags"
