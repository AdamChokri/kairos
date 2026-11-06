#!/usr/bin/env bash
# infra/openbao/gen-secret.sh PATH FIELD [--length N] [--rotate] - generates a random secret and
# stores it in OpenBao, without it ever reaching the screen, the shell history, a file or a
# command line (plan section 3.3, D-24). Use it for a secret that nobody has to choose, such as
# the as-is deploy password; use kv-put.sh for a value that comes from elsewhere (a token).
#   PATH      where to store it: must start with kv/
#   FIELD     the field of the secret that receives the value
#   --length  characters, 16 to 128 (default 32); letters and digits only
#   --rotate  replace a secret that already exists; without it the script refuses, so a second
#             run cannot silently change a password that Jenkins and the hosts already use
# The whole secret is replaced (as kv-put.sh does): give it a path of its own.
# Example: infra/openbao/gen-secret.sh kv/infra/as-is-deploy password
set -euo pipefail

usage() { echo "usage: $0 PATH FIELD [--length N] [--rotate]" >&2; exit 2; }
[[ $# -ge 2 ]] || usage
path=$1; field=$2; shift 2
length=32; rotate=0
while [[ $# -gt 0 ]]; do
  case $1 in
    --length) [[ $# -ge 2 ]] || usage; length=$2; shift 2 ;;
    --rotate) rotate=1; shift ;;
    *) usage ;;
  esac
done
[[ $path == kv/* ]] || { echo "ERROR: the path must start with kv/ (got '$path')" >&2; exit 2; }
[[ $field =~ ^[a-z][a-z0-9_]*$ ]] || { echo "ERROR: the field must be lowercase letters, digits and _ (got '$field')" >&2; exit 2; }
[[ $length =~ ^[0-9]+$ && $length -ge 16 && $length -le 128 ]] || { echo "ERROR: --length must be 16 to 128" >&2; exit 2; }
for tool in bao python3; do
  command -v "$tool" >/dev/null 2>&1 || { echo "ERROR: missing tool: $tool" >&2; exit 1; }
done
bao token lookup >/dev/null 2>&1 || { echo "ERROR: no valid OpenBao token - run: bao login -no-print -method=userpass username=adam" >&2; exit 1; }

if [[ $rotate -eq 0 ]] && bao kv get -format=json "$path" >/dev/null 2>&1; then
  echo "ERROR: $path already holds a secret; add --rotate to replace it (then update every place that uses it)" >&2
  exit 1
fi

# The value is made inside python3 and goes to bao on stdin; nothing is printed but the version.
LENGTH=$length FIELD=$field python3 -I -c 'import json, os, secrets, string
alphabet = string.ascii_letters + string.digits
value = "".join(secrets.choice(alphabet) for _ in range(int(os.environ["LENGTH"])))
print(json.dumps({os.environ["FIELD"]: value}))' \
  | bao kv put -format=json "$path" - \
  | python3 -I -c 'import json, sys; print("written: version %s" % json.load(sys.stdin)["data"]["version"])'
echo "field: $field ($length characters), never shown"
