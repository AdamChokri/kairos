#!/usr/bin/env bash
# infra/openbao/kv-put.sh PATH FIELD... - writes one KV v2 secret in OpenBao without the values
# ever reaching the screen, the shell history, a file or a command line (plan section 3.3).
#   FIELD        the value is asked for, hidden, and asked for again to confirm it
#   FIELD=value  a value that is not secret (a user name, a URL path), given inline
#   FIELD=@file  the value is the content of a file (a key you are about to shred)
# The whole secret is replaced: give every field the secret should keep.
# Example: infra/openbao/kv-put.sh kv/infra/dockerhub-ro username=adamchokri token
set -euo pipefail

[[ $# -ge 2 ]] || { echo "usage: $0 PATH FIELD [FIELD=value] [FIELD=@file]..." >&2; exit 2; }
path=$1; shift
[[ $path == kv/* ]] || { echo "ERROR: the path must start with kv/ (got '$path')" >&2; exit 2; }
command -v bao >/dev/null 2>&1 || { echo "ERROR: missing tool: bao" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "ERROR: missing tool: python3" >&2; exit 1; }
bao token lookup >/dev/null 2>&1 || { echo "ERROR: no valid OpenBao token - run: bao login -method=userpass username=adam" >&2; exit 1; }

# Fields and values travel to python3 on stdin, separated by the ASCII unit and record separators;
# printf is a bash builtin, so no value appears in any process's argument list.
payload=''
add() { payload+="$1"$'\x1f'"$2"$'\x1e'; }
for arg in "$@"; do
  case $arg in
    *=@*)
      field=${arg%%=@*}; file=${arg#*=@}
      [[ -r $file ]] || { echo "ERROR: cannot read $file" >&2; exit 1; }
      add "$field" "$(cat "$file")" ;;
    *=*)
      add "${arg%%=*}" "${arg#*=}" ;;
    *)
      read -rsp "$arg for $path: " v1 </dev/tty; echo >&2
      read -rsp "$arg again: " v2 </dev/tty; echo >&2
      [[ -n $v1 ]] || { echo "ERROR: empty value for $arg" >&2; exit 1; }
      [[ $v1 == "$v2" ]] || { echo "ERROR: the two values for $arg differ" >&2; exit 1; }
      add "$arg" "$v1"
      unset v1 v2 ;;
  esac
done

printf '%s' "$payload" \
  | python3 -I -c 'import sys, json
raw = sys.stdin.read()
pairs = [p.split("\x1f", 1) for p in raw.split("\x1e") if p]
print(json.dumps({k: v for k, v in pairs}))' \
  | bao kv put -format=json "$path" - \
  | python3 -I -c 'import sys, json; d = json.load(sys.stdin)["data"]; print("written: version %s" % d["version"])'
echo "fields: $(printf '%s\n' "$@" | sed -E 's/=.*//' | paste -sd, -)"
