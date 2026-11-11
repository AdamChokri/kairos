#!/usr/bin/env bash
# ci/tools/dev-secrets.sh [--rotate] - makes the throwaway secrets of the Compose stack on this machine (SV-01):
# .dev-secrets/jwt_secret_key (64 random characters) and .dev-secrets/db_password (32). The folder is ignored by
# Git. Existing files are kept, so the database volume keeps matching its password; --rotate makes new values,
# and then `docker compose -f deploy/compose.yaml down -v` must run, because the old volume holds the old password.
#
# The files are world-readable (0444) on purpose: Docker Compose outside Swarm mounts a secret file with the
# owner and mode it has on the host, and the containers run as other users (the database as `postgres`, the API
# as UID 10001 after SV-09). They are random values of a development machine, used by nothing else. Staging and
# production never use this script: their files are rendered by the OpenBao Agent (WP5.3) with 0400 and the
# container's UID.
#   bash ci/tools/dev-secrets.sh
# Needs bash and python3. Exit code 0: both files exist.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIR="${DEV_SECRETS_DIR:-$ROOT/.dev-secrets}"
rotate=0
[[ ${1:-} == --rotate ]] && rotate=1

make_secret() { # make_secret FILE LENGTH
  local file=$DIR/$1 length=$2
  if [[ -s $file && $rotate == 0 ]]; then
    printf 'kept     %s\n' "$file"
    return
  fi
  rm -f "$file"   # a read-only (0444) file cannot be overwritten, even by its owner
  python3 -c 'import secrets, string, sys
alphabet = string.ascii_letters + string.digits
print("".join(secrets.choice(alphabet) for _ in range(int(sys.argv[1]))), end="")' "$length" >"$file"
  chmod 0444 "$file"
  printf 'created  %s (%s characters)\n' "$file" "$length"
}

umask 022
mkdir -p "$DIR"
make_secret jwt_secret_key 64
make_secret db_password 32
