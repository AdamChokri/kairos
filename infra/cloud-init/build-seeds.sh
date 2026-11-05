#!/usr/bin/env bash
# infra/cloud-init/build-seeds.sh [VM...] - builds one NoCloud seed ISO per lab VM (plan WP1.1).
# Reads infra/lab/vms.csv (all VMs, or only those named), fills the three templates of this folder,
# validates them with cloud-init's own schema check when cloud-init is installed, and writes
# <Legion project folder>/seeds/<vm>.iso - D:\Projects\Kairos\seeds, from infra/lab/provision.conf
# (volume label "cidata", which cloud-init's NoCloud source looks for).
# The instance ID is fixed per VM, so rebuilding a seed never makes an existing VM re-run first boot.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VMS_CSV="$DIR/../lab/vms.csv"
# shellcheck source-path=SCRIPTDIR source=../lab/provision.conf
source "$DIR/../lab/provision.conf"
OUT="${SEED_DIR:-$LAB_HOME_WSL/seeds}"
ADMIN_USER="${LAB_ADMIN_USER:-adam}"
ADMIN_PUB="${LAB_ADMIN_KEY:-$HOME/.ssh/kairos_admin}.pub"
SEED_REV=1

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
command -v cloud-localds >/dev/null 2>&1 || fail "missing cloud-localds - sudo apt install cloud-image-utils"
[[ $OUT != /seeds ]] || fail "cannot map $LAB_ROOT_LEGION to a WSL2 path (run this in WSL2, or set SEED_DIR)"
[[ -r $ADMIN_PUB ]] || fail "missing $ADMIN_PUB - create the admin key first (ssh-keygen -t ed25519 -f ${ADMIN_PUB%.pub})"
key=$(tr -d '\r\n' < "$ADMIN_PUB")
# The key goes through sed (delimiter |, where & means the match): its comment may hold letters, digits,
# spaces and @ . _ : , - only, so nothing in it can change the substitution (E-16).
key_re='^ssh-ed25519 [A-Za-z0-9+/=]+( [A-Za-z0-9@._:, -]+)?$'
[[ $key =~ $key_re ]] || fail "$ADMIN_PUB is not a plain ed25519 public key (comment: letters, digits, spaces, @ . _ : , - only)"
[[ $ADMIN_USER =~ ^[a-z][a-z0-9-]*$ ]] || fail "bad admin user name '$ADMIN_USER'"

want=("$@")
mkdir -p "$OUT"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fill() {  # TEMPLATE VM MAC -> stdout
  local mac=$3
  mac="${mac:0:2}:${mac:2:2}:${mac:4:2}:${mac:6:2}:${mac:8:2}:${mac:10:2}"
  sed -e "s|@HOSTNAME@|$2|g" -e "s|@ADMIN_USER@|$ADMIN_USER|g" -e "s|@ADMIN_KEY@|$key|g" \
      -e "s|@MAC@|${mac,,}|g" -e "s|@INSTANCE_ID@|$2-$SEED_REV|g" "$DIR/$1"
}

built=0
while IFS=, read -r name _ _ mac _; do
  [[ -z $name || $name == name ]] && continue
  if (( ${#want[@]} > 0 )); then
    found=0
    for w in "${want[@]}"; do [[ $w == "$name" ]] && found=1; done
    (( found )) || continue
  fi
  [[ $mac =~ ^[0-9A-Fa-f]{12}$ ]] || fail "vms.csv: bad MAC '$mac' for $name"
  d="$work/$name"; mkdir -p "$d"
  fill user-data.tpl "$name" "$mac" > "$d/user-data"
  fill network-config.tpl "$name" "$mac" > "$d/network-config"
  fill meta-data.tpl "$name" "$mac" > "$d/meta-data"
  if command -v cloud-init >/dev/null 2>&1; then
    cloud-init schema -c "$d/user-data" >/dev/null || fail "user-data of $name does not pass cloud-init's schema check"
    cloud-init schema -t network-config -c "$d/network-config" >/dev/null \
      || fail "network-config of $name does not pass cloud-init's schema check"
  fi
  cloud-localds -N "$d/network-config" "$OUT/$name.iso" "$d/user-data" "$d/meta-data"
  printf '%-12s %s\n' "$name" "$OUT/$name.iso"
  built=$((built + 1))
done < <(tr -d '\r' < "$VMS_CSV")

(( built > 0 )) || fail "no VM matched: ${want[*]:-(vms.csv is empty)}"
echo "$built seed ISO(s) in $OUT"
