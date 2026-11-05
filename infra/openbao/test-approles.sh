#!/usr/bin/env bash
# infra/openbao/test-approles.sh - proves the AppRole bindings of approles.tsv (plan WP1.3, EV-27).
# For every role it issues one test secret ID, then:
#   - logs in from the role's own VM        -> 200, a read inside the policy works (200, or 404 while
#                                              the secret is still empty), a read outside it is denied (403);
#   - logs in from the Legion (WSL2)        -> refused by the CIDR binding (400);
#   - logs in from another VM               -> refused by the CIDR binding (400);
#   - tries from dso-agent                  -> unreachable: UFW on dso-bao drops it.
# Each test token revokes itself and every test secret ID is destroyed at the end, so nothing usable
# is left behind. Credentials reach each VM through SSH's stdin, never a command line or a file.
# Needs: bao, jq, curl; BAO_ADDR; an admin token (bao login -method=userpass username=adam);
# SSH to the VMs as the admin user (WP1.1).
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VMS_CSV="$DIR/../lab/vms.csv"
: "${LAB_ADMIN_USER:=adam}"
: "${LAB_ADMIN_KEY:=$HOME/.ssh/kairos_admin}"
: "${OPENBAO_URL:=https://openbao.kairos.lab:8200}"
UNREACHABLE_FROM=dso-agent

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
for tool in bao jq curl ssh; do command -v "$tool" >/dev/null 2>&1 || fail "missing tool: $tool"; done
bao token lookup >/dev/null 2>&1 || fail "no valid OpenBao token - run: bao login -method=userpass username=adam"

declare -A VM_IP=()
while IFS=, read -r name _ ip _; do
  [[ -z $name || $name == name ]] && continue
  VM_IP[$name]=$ip
done < <(tr -d '\r' < "$VMS_CSV")

# What each role may read (inside its policy) and one path it must not read.
declare -A ALLOWED=(
  [jenkins-build]=kv/data/ci/sonarqube   [jenkins-deploy]=kv/data/ci/deploy-staging
  [jenkins-signer]=transit/keys/kairos-images
  [kairos-staging]=kv/data/kairos/staging [kairos-prod]=kv/data/kairos/prod
)
DENIED=kv/data/infra/dockerhub-ro

# The probe runs on the far end: credentials JSON on stdin, results on stdout. It needs bash, curl, jq.
probe() {  # ALLOWED_PATH
  cat <<PROBE
url='$OPENBAO_URL'
creds=\$(cat)
resp=\$(printf '%s' "\$creds" | curl -sS -m 8 -w '\n%{http_code}' -X POST --data @- "\$url/v1/auth/approle/login" 2>/dev/null) \
  || { echo 'login=unreachable'; exit 0; }
code=\${resp##*\$'\n'}; body=\${resp%\$'\n'*}
echo "login=\$code"
if [ "\$code" = 200 ]; then
  tok=\$(printf '%s' "\$body" | jq -r .auth.client_token)
  for p in '$1' '$DENIED'; do
    printf 'header = "X-Vault-Token: %s"\n' "\$tok" | curl -sS -m 8 -K - -o /dev/null -w "read \$p=%{http_code}\n" "\$url/v1/\$p"
  done
  printf 'header = "X-Vault-Token: %s"\n' "\$tok" | curl -sS -m 8 -K - -o /dev/null -X POST "\$url/v1/auth/token/revoke-self"
fi
PROBE
}

run_from() {  # FROM(vm name or "legion") ALLOWED_PATH CREDS_JSON
  if [[ $1 == legion ]]; then
    bash -c "$(probe "$2")" <<<"$3"
  else
    ssh -i "$LAB_ADMIN_KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=5 \
      "$LAB_ADMIN_USER@${VM_IP[$1]}" "$(probe "$2")" <<<"$3"
  fi
}

pass=0 failed=0 accessors=()
check() {  # LABEL EXPECTED_REGEX ACTUAL
  if [[ $3 =~ $2 ]]; then
    printf '  PASS  %-64s %s\n' "$1" "${BASH_REMATCH[0]}"; pass=$((pass + 1))
  else
    printf '  FAIL  %-64s got: %s (expected %s)\n' "$1" "$(tr '\n' ' ' <<<"$3")" "$2"; failed=$((failed + 1))
  fi
}

cleanup() {
  local role acc
  for entry in "${accessors[@]}"; do
    role=${entry%%:*}; acc=${entry#*:}
    bao write -f "auth/approle/role/$role/secret-id-accessor/destroy" secret_id_accessor="$acc" >/dev/null 2>&1 \
      || echo "WARNING: could not destroy the test secret ID of $role (accessor $acc) - destroy it by hand" >&2
  done
}
trap cleanup EXIT

while IFS=$'\t' read -r role vm _; do
  [[ -z $role || $role == \#* ]] && continue
  echo "$role (bound to $vm, ${VM_IP[$vm]})"
  role_id=$(bao read -field=role_id "auth/approle/role/$role/role-id")
  sid_json=$(bao write -f -format=json "auth/approle/role/$role/secret-id")
  accessors+=("$role:$(jq -r .data.secret_id_accessor <<<"$sid_json")")
  creds=$(jq -c --arg r "$role_id" '{role_id: $r, secret_id: .data.secret_id}' <<<"$sid_json")
  unset sid_json

  out=$(run_from "$vm" "${ALLOWED[$role]}" "$creds")
  check "login from its own VM ($vm)" "login=200" "$out"
  check "read inside the policy (${ALLOWED[$role]})" "read ${ALLOWED[$role]}=(200|404)" "$out"
  check "read outside the policy is denied ($DENIED)" "read $DENIED=403" "$out"

  out=$(run_from legion "${ALLOWED[$role]}" "$creds")
  check "login from the Legion is refused" "login=400" "$out"

  other=dso-staging; [[ $vm == dso-staging ]] && other=dso-prod
  out=$(run_from "$other" "${ALLOWED[$role]}" "$creds")
  check "login from $other is refused" "login=400" "$out"

  out=$(run_from "$UNREACHABLE_FROM" "${ALLOWED[$role]}" "$creds")
  check "OpenBao is unreachable from $UNREACHABLE_FROM" "login=unreachable" "$out"
  unset creds
done < "$DIR/approles.tsv"

echo "result: $pass passed, $failed failed"
(( failed == 0 ))
