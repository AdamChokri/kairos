#!/usr/bin/env bash
# ci/tools/webhook-check.sh - proves that the webhook route lets in one thing and refuses the rest (WP4.8, D-45).
# It talks to the public address of the ngrok agent, which it reads from OpenBao (kv/infra/ngrok, field domain: an
# address is not a secret, but it is not written in this public repository either) and, as the second layer, to
# Jenkins directly: an unsigned event must be refused by Jenkins itself. Nothing it sends can start a build.
# Each run costs a few of the 500 webhook verifications a month that ngrok's free plan allows.
# Needs bao (logged in), curl and openssl; run it from WSL2 on the Legion:
#   bash ci/tools/webhook-check.sh
set -euo pipefail

domain=$(bao kv get -field=domain kv/infra/ngrok)
public="https://$domain"
jenkins="http://jenkins.kairos.lab:8080"
failed=0

# check NAME EXPECTED-REGEX URL [curl arguments...]: one PASS or FAIL line, with the status the route answered.
check() {
  local name=$1 want=$2 url=$3 got
  shift 3
  got=$(curl -sS -o /dev/null -m 20 -w '%{http_code}' "$@" "$url" 2>/dev/null) || got=000
  if [[ $got =~ $want ]]; then
    printf 'PASS  %-52s %s\n' "$name" "$got"
  else
    printf 'FAIL  %-52s %s (wanted %s)\n' "$name" "$got" "$want"
    failed=1
  fi
}

event=(-X POST -H 'Content-Type: application/json' -H 'X-GitHub-Event: push' -d '{}')
wrong_signature="sha256=$(printf '{}' | openssl dgst -sha256 -hmac 'not-the-secret' | sed 's/^.* //')"

check "GET  /login is not served"                    '^404$' "$public/login"
check "GET  /github-webhook/ is not served"          '^404$' "$public/github-webhook/"
check "POST /login is not served"                    '^404$' "$public/login" "${event[@]}"
check "POST /github-webhook/ without a signature"    '^403$' "$public/github-webhook/" "${event[@]}"
check "POST /github-webhook/ with a wrong signature" '^403$' "$public/github-webhook/" "${event[@]}" \
  -H "X-Hub-Signature-256: $wrong_signature"
check "Jenkins itself refuses an unsigned event"     '^4[0-9][0-9]$' "$jenkins/github-webhook/" "${event[@]}"

if ((failed)); then
  echo "webhook-check: FAILED"
  exit 1
fi
echo "webhook-check: all six checks passed"
