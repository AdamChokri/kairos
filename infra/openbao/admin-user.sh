#!/usr/bin/env bash
# infra/openbao/admin-user.sh - creates (or resets the password of) the OpenBao administrator
# "adam" on the userpass method, with the admin policy (plan WP1.3, D-07). Run it once with the
# root token, before the root token is revoked; later, to change the password, as adam.
# The password is asked for twice, hidden, and reaches OpenBao through stdin only.
set -euo pipefail

USER_NAME=${1:-adam}
command -v bao >/dev/null 2>&1 || { echo "ERROR: missing tool: bao" >&2; exit 1; }
bao token lookup >/dev/null 2>&1 || { echo "ERROR: no valid OpenBao token" >&2; exit 1; }
bao policy read admin >/dev/null 2>&1 || { echo "ERROR: policy 'admin' is missing - run infra/openbao/apply.sh first" >&2; exit 1; }

read -rsp "New OpenBao password for $USER_NAME (at least 16 characters): " p1 </dev/tty; echo >&2
read -rsp "Again: " p2 </dev/tty; echo >&2
[[ ${#p1} -ge 16 ]] || { echo "ERROR: the password is shorter than 16 characters" >&2; exit 1; }
[[ $p1 == "$p2" ]] || { echo "ERROR: the two passwords differ" >&2; exit 1; }

printf '%s' "$p1" | bao write "auth/userpass/users/$USER_NAME" \
  token_policies=admin token_ttl=1h token_max_ttl=8h password=- >/dev/null
unset p1 p2
echo "userpass account '$USER_NAME' written (policy admin, tokens valid 1 h, renewable up to 8 h)"
