#!/usr/bin/env bash
# infra/wazuh/gen-secrets.sh - creates every Wazuh secret once and stores it in OpenBao at
# kv/infra/wazuh (plan WP1.6): no Wazuh default password survives the first start.
#   indexer_admin_password / _hash   indexer "admin" (bcrypt hash for internal_users.yml)
#   dashboard_password / _hash       indexer "kibanaserver", used by the dashboard
#   api_password                     manager API user "wazuh-wui" (8-64 chars, upper, lower, digit, symbol)
#   enrollment_password              agents' enrollment password (authd)
#   slack_webhook                    incoming webhook to #kairos-secops (asked for, hidden)
# Passwords are random (32 characters); hashes are made locally with htpasswd, reading stdin.
# Nothing is printed, written to disk or passed on a command line. Refuses to overwrite an existing
# secret unless --rotate is given (then re-run the Wazuh plays: they apply the new values).
set -euo pipefail

path=kv/infra/wazuh
rotate=no
[[ ${1:-} == --rotate ]] && rotate=yes
for tool in bao htpasswd python3; do
  command -v "$tool" >/dev/null 2>&1 || { echo "ERROR: missing tool: $tool (htpasswd: sudo apt install apache2-utils)" >&2; exit 1; }
done
bao token lookup >/dev/null 2>&1 || { echo "ERROR: no valid OpenBao token - run: bao login -method=userpass username=adam" >&2; exit 1; }
if bao kv get "$path" >/dev/null 2>&1 && [[ $rotate == no ]]; then
  echo "ERROR: $path already exists - use --rotate to replace every value" >&2
  exit 1
fi

genpw() {  # 32 characters: letters and digits, with at least one of each class and two symbols
  python3 -I -c 'import secrets, string
alnum = string.ascii_letters + string.digits
chars = [secrets.choice(alnum) for _ in range(28)]
chars += [secrets.choice(string.ascii_lowercase), secrets.choice(string.ascii_uppercase),
          secrets.choice(string.digits), secrets.choice("-@*")]
secrets.SystemRandom().shuffle(chars)
print("".join(chars))'
}
bcrypt() {  # PASSWORD (from a variable, through stdin) -> bcrypt hash, cost 12
  printf '%s' "$1" | htpasswd -niBC 12 user | cut -d: -f2-
}

admin_pw=$(genpw); dash_pw=$(genpw); api_pw=$(genpw); enroll_pw=$(genpw)
admin_hash=$(bcrypt "$admin_pw"); dash_hash=$(bcrypt "$dash_pw")
read -rsp "Slack incoming webhook URL for #kairos-secops: " webhook </dev/tty; echo >&2
[[ $webhook =~ ^https://hooks\.slack\.com/services/[A-Za-z0-9/]+$ ]] || { echo "ERROR: that is not a Slack incoming webhook URL" >&2; exit 1; }

sep=$'\x1f' end=$'\x1e'
printf '%s' "indexer_admin_password$sep$admin_pw${end}indexer_admin_hash$sep$admin_hash${end}dashboard_password$sep$dash_pw${end}dashboard_hash$sep$dash_hash${end}api_password$sep$api_pw${end}enrollment_password$sep$enroll_pw${end}slack_webhook$sep$webhook$end" \
  | python3 -I -c 'import sys, json
pairs = [p.split("\x1f", 1) for p in sys.stdin.read().split("\x1e") if p]
print(json.dumps(dict(pairs)))' \
  | bao kv put "$path" - >/dev/null
unset admin_pw dash_pw api_pw enroll_pw admin_hash dash_hash webhook
echo "written: $path (indexer_admin_password, indexer_admin_hash, dashboard_password, dashboard_hash, api_password, enrollment_password, slack_webhook)"
echo "The indexer admin password is the dashboard login: read it when needed with"
echo "  bao kv get -field=indexer_admin_password $path | clip.exe"
