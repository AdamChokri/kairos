#!/usr/bin/env bash
# infra/openbao/apply.sh - applies the OpenBao configuration kept in this folder (plan WP1.3).
# Idempotent: run it after any change to policies/*.hcl or approles.tsv; a second run changes nothing.
#
# Creates, when missing: KV v2 at kv/, Transit at transit/, the auth methods approle and userpass,
# and the non-exportable ECDSA P-256 Transit key kairos-images. Tunes approle/ so that the audit log
# keeps its error messages readable (E-23). Writes every policy in policies/
# and every AppRole in approles.tsv, bound to its VM's address from infra/lab/vms.csv.
# Never creates or reads a secret value.
#
# Needs: bao, jq; BAO_ADDR set; an admin token (the root token during setup, then
# `bao login -no-print -method=userpass username=adam`).
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VMS_CSV="$DIR/../lab/vms.csv"
TRANSIT_KEY=kairos-images

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
say()  { printf '%s\n' "$*"; }

for tool in bao jq; do
  command -v "$tool" >/dev/null 2>&1 || fail "missing tool: $tool"
done
[[ -n ${BAO_ADDR:-} ]] || fail "BAO_ADDR is not set (expected https://openbao.kairos.lab:8200)"
bao token lookup >/dev/null 2>&1 || fail "no valid OpenBao token - log in first (bao login -no-print -method=userpass username=adam)"

# --- Secrets engines and auth methods -------------------------------------------------

mounts=$(bao secrets list -format=json)
ensure_secrets() {  # PATH TYPE [VERSION]
  local path=$1 type=$2 version=${3:-} have
  have=$(jq -r --arg p "$path/" '.[$p].type // empty' <<<"$mounts")
  if [[ -z $have ]]; then
    if [[ -n $version ]]; then
      bao secrets enable -path="$path" -version="$version" "$type" >/dev/null
    else
      bao secrets enable -path="$path" "$type" >/dev/null
    fi
    say "created   secrets engine $path/ ($type${version:+ v$version})"
    return
  fi
  [[ $have == "$type" ]] || fail "$path/ is a '$have' engine, expected '$type'"
  if [[ -n $version ]]; then
    [[ $(jq -r --arg p "$path/" '.[$p].options.version // "1"' <<<"$mounts") == "$version" ]] \
      || fail "$path/ is not version $version of $type"
  fi
  say "unchanged secrets engine $path/"
}
ensure_secrets kv kv 2
ensure_secrets transit transit

auths=$(bao auth list -format=json)
ensure_auth() {  # TYPE (mounted at its own name)
  local type=$1 have
  have=$(jq -r --arg p "$type/" '.[$p].type // empty' <<<"$auths")
  if [[ -z $have ]]; then
    bao auth enable "$type" >/dev/null
    say "created   auth method $type/"
  else
    [[ $have == "$type" ]] || fail "auth/$type/ is a '$have' method, expected '$type'"
    say "unchanged auth method $type/"
  fi
}
ensure_auth approle
ensure_auth userpass

# AppRole errors in clear in the audit log (E-23): by default every string of a response's data is
# HMAC'd, so a refused login (for example an address outside the role's CIDR binding) could not be
# read or matched - by the WP1.3 check or by Wazuh in WP6.2. An error message never holds a secret;
# tokens and secret IDs stay HMAC'd.
tune=$(bao read -format=json sys/auth/approle/tune)
if jq -e '(.data.audit_non_hmac_response_keys // []) == ["error"]' <<<"$tune" >/dev/null; then
  say "unchanged auth method approle/ (audit: error messages in clear)"
else
  bao auth tune -audit-non-hmac-response-keys=error approle/ >/dev/null
  say "tuned     auth method approle/ (audit: error messages in clear)"
fi

# --- Policies ---------------------------------------------------------------------------

shopt -s nullglob
policy_files=("$DIR"/policies/*.hcl)
(( ${#policy_files[@]} > 0 )) || fail "no policy in $DIR/policies"
for file in "${policy_files[@]}"; do
  name=$(basename "$file" .hcl)
  current=$(bao policy read "$name" 2>/dev/null || true)
  if [[ $current == "$(cat "$file")" ]]; then
    say "unchanged policy $name"
  else
    bao policy write "$name" "$file" >/dev/null
    say "written   policy $name"
  fi
done

# --- Transit signing key ----------------------------------------------------------------

if key=$(bao read -format=json "transit/keys/$TRANSIT_KEY" 2>/dev/null); then
  [[ $(jq -r .data.type <<<"$key") == ecdsa-p256 ]] || fail "transit key $TRANSIT_KEY is not ecdsa-p256"
  [[ $(jq -r .data.exportable <<<"$key") == false ]] || fail "transit key $TRANSIT_KEY is exportable"
  say "unchanged transit key $TRANSIT_KEY"
else
  bao write -f "transit/keys/$TRANSIT_KEY" type=ecdsa-p256 exportable=false allow_plaintext_backup=false >/dev/null
  say "created   transit key $TRANSIT_KEY (ecdsa-p256, not exportable)"
fi

# --- AppRoles ---------------------------------------------------------------------------

declare -A VM_IP=()
while IFS=, read -r name _ ip _; do
  [[ -z $name || $name == name ]] && continue
  VM_IP[$name]=$ip
done < <(tr -d '\r' < "$VMS_CSV")

seconds() {  # 15m / 1h / 2160h / 90s -> seconds (OpenBao reports durations in seconds)
  local v=$1
  case $v in
    *h) echo $(( ${v%h} * 3600 )) ;;
    *m) echo $(( ${v%m} * 60 )) ;;
    *s) echo "${v%s}" ;;
    *)  echo "$v" ;;
  esac
}

while IFS=$'\t' read -r role vm policy ttl max_ttl sid_ttl; do
  [[ -z $role || $role == \#* ]] && continue
  [[ -n ${VM_IP[$vm]:-} ]] || fail "approles.tsv: $role is bound to '$vm', which is not in vms.csv"
  [[ -f $DIR/policies/$policy.hcl ]] || fail "approles.tsv: $role uses policy '$policy', which has no file"
  cidr="${VM_IP[$vm]}/32"
  # OpenBao stores a single-address token_bound_cidrs entry as the bare address, so ask for that.
  want=$(jq -cn --arg p "$policy" --arg c "$cidr" --arg ip "${VM_IP[$vm]}" \
    --argjson t "$(seconds "$ttl")" --argjson m "$(seconds "$max_ttl")" --argjson s "$(seconds "$sid_ttl")" \
    '{token_policies: [$p], secret_id_bound_cidrs: [$c], token_bound_cidrs: [$ip],
      token_ttl: $t, token_max_ttl: $m, secret_id_ttl: $s, secret_id_num_uses: 0, bind_secret_id: true}')
  if have=$(bao read -format=json "auth/approle/role/$role" 2>/dev/null) \
     && jq -e --argjson w "$want" '.data as $d | all($w | to_entries[]; $d[.key] == .value)' <<<"$have" >/dev/null; then
    say "unchanged approle $role"
  else
    bao write "auth/approle/role/$role" - <<<"$want" >/dev/null
    say "written   approle $role (policy $policy, bound to $cidr)"
  fi
done < "$DIR/approles.tsv"

say "OpenBao configuration applied."
