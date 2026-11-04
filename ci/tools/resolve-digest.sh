#!/usr/bin/env bash
# ci/tools/resolve-digest.sh IMAGE:TAG - prints IMAGE:TAG@sha256:<digest> for the tag as the registry
# serves it now (plan D-08, D-12). The digest is the one `docker pull IMAGE:TAG` would record: the
# multi-platform index when the image has one, so the pin works on any platform.
# Works with any registry that speaks the OCI distribution API (Docker Hub, ghcr.io, quay.io...):
# it asks anonymously, follows the registry's own token challenge, and only sends HEAD requests,
# which Docker Hub does not count against the pull rate limit. Needs curl.
set -euo pipefail

ref=${1:-}
[[ -n $ref && $ref != *@* ]] || { echo "usage: $0 IMAGE:TAG   (no digest in the argument)" >&2; exit 2; }

name=${ref%:*} tag=${ref##*:}
[[ $name != "$ref" && $tag != */* ]] || { name=$ref; tag=latest; }
first=${name%%/*}
if [[ $name == */* && ( $first == *.* || $first == *:* || $first == localhost ) ]]; then
  registry=$first repo=${name#*/}
else
  registry="registry-1.docker.io" repo=$name
  [[ $repo == */* ]] || repo="library/$repo"
fi
[[ $registry == docker.io ]] && registry="registry-1.docker.io"

accept='application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.v2+json'
url="https://$registry/v2/$repo/manifests/$tag"

head_request() {  # [TOKEN] -> headers on stdout
  if [[ -n ${1:-} ]]; then
    printf 'header = "Authorization: Bearer %s"\n' "$1" | curl -sS -I -m 20 -K - -H "Accept: $accept" "$url"
  else
    curl -sS -I -m 20 -H "Accept: $accept" "$url"
  fi
}

headers=$(head_request | tr -d '\r')
status=$(awk 'NR==1 {print $2}' <<<"$headers")
if [[ $status == 401 ]]; then
  challenge=$(grep -i '^www-authenticate:' <<<"$headers" | head -1 | sed -E 's/^[^:]+:[[:space:]]*//')
  [[ $challenge == Bearer* ]] || { echo "ERROR: $registry asks for an authentication scheme other than Bearer" >&2; exit 1; }
  realm=$(sed -nE 's/.*realm="([^"]+)".*/\1/p' <<<"$challenge")
  service=$(sed -nE 's/.*service="([^"]+)".*/\1/p' <<<"$challenge")
  scope=$(sed -nE 's/.*scope="([^"]+)".*/\1/p' <<<"$challenge")
  [[ -n $scope ]] || scope="repository:$repo:pull"
  token=$(curl -sSf -m 20 -G "$realm" ${service:+--data-urlencode "service=$service"} --data-urlencode "scope=$scope" \
    | python3 -I -c 'import json, sys
try:
    d = json.load(sys.stdin)
except ValueError:
    d = {}
print(d.get("token") or d.get("access_token") or "")') || token=""
  [[ -n $token ]] || { echo "ERROR: $registry gave no anonymous token for $repo" >&2; exit 1; }
  headers=$(head_request "$token" | tr -d '\r')
  status=$(awk 'NR==1 {print $2}' <<<"$headers")
fi
[[ $status == 200 ]] || { echo "ERROR: $registry answered HTTP $status for $repo:$tag" >&2; exit 1; }
digest=$(grep -i '^docker-content-digest:' <<<"$headers" | awk '{print $2}')
[[ $digest =~ ^sha256:[0-9a-f]{64}$ ]] || { echo "ERROR: no digest in $registry's answer for $repo:$tag" >&2; exit 1; }
echo "$name:$tag@$digest"
