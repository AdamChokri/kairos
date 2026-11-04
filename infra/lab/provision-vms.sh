#!/usr/bin/env bash
# infra/lab/provision-vms.sh - creates the lab VMs on both Hyper-V hosts (plan WP1.1), from WSL2.
# For each host in hosts.csv:
#   1. makes its lab folder (provision.conf) and copies vms.csv, New-LabVM.ps1 and the seed ISOs
#      of its own VMs there (build-seeds.sh writes them into the Legion's folder, seeds\);
#   2. makes sure it holds the golden VHDX: the Legion's copy is the reference; a missing copy on
#      the OptiPlex is sent with scp, and both copies must have the same SHA-256 - read-only on both;
#   3. runs New-LabVM.ps1 there, which creates missing VMs and corrects drifted ones (left Off).
# Idempotent. Start the VMs afterwards with `make lab-up`.
set -Eeuo pipefail
# shellcheck source=lablib.sh
source "$(dirname "$(readlink -f "$0")")/lablib.sh"
# shellcheck source=provision.conf
source "$LAB_DIR/provision.conf"

lab_init
command -v wslpath >/dev/null 2>&1 || lab_fail "run this from WSL2 on the Legion"
[[ -n $LAB_HOME_WSL ]] || lab_fail "cannot map $LAB_ROOT_LEGION to a WSL2 path"
SEEDS="${SEED_DIR:-$LAB_HOME_WSL/seeds}"

declare -A ROOT=([legion]=$LAB_ROOT_LEGION [optiplex]=$LAB_ROOT_OPTIPLEX)
for host in "${HOST_NAMES[@]}"; do
  [[ -n ${ROOT[$host]:-} ]] || lab_fail "provision.conf has no lab folder for host '$host'"
  [[ ${ROOT[$host]} =~ ^[A-Za-z]:\\[A-Za-z0-9_\\-]+$ ]] || lab_fail "bad lab folder '${ROOT[$host]}' for $host"
  [[ ${HOST_SWITCH[$host]} != *" "* ]] || lab_fail "switch name '${HOST_SWITCH[$host]}' of $host contains a space - rename it or quote it here"
done

hash_of() {  # HOST WINDOWS_PATH -> SHA-256, or "missing"
  lab_ps "$1" 600 "if (Test-Path -LiteralPath '$2') { (Get-FileHash -Algorithm SHA256 -LiteralPath '$2').Hash } else { 'missing' }"
}
scp_to() {  # HOST LOCAL_FILE... (last argument: WINDOWS_DIR)
  local host=$1 dir=${*: -1} files=("${@:2:$#-2}")
  dir=${dir//\\//}
  scp -q -i "$LAB_SSH_KEY" -o IdentitiesOnly=yes -o BatchMode=yes "${files[@]}" "${HOST_TARGET[$host]}:${LAB_SCP_PREFIX}$dir/"
}

legion_golden="$LAB_ROOT_LEGION\\golden\\$GOLDEN_NAME"
echo "Reading the reference golden image on the Legion ($legion_golden)..."
ref=$(hash_of legion "$legion_golden") || lab_fail "$(lab_host_hint legion)"
[[ $ref =~ ^[0-9A-F]{64}$ ]] || lab_fail "golden image not found on the Legion: $legion_golden (WP1.1, golden image)"
echo "  SHA-256 $ref"

for host in "${HOST_NAMES[@]}"; do
  root=${ROOT[$host]}
  echo "== $host: $root =="
  lab_ps "$host" "$PS_TIMEOUT_SECONDS" "foreach (\$d in 'golden','seeds','Hyper-V') { New-Item -ItemType Directory -Force -Path (Join-Path '$root' \$d) | Out-Null }" >/dev/null \
    || lab_fail "$(lab_host_hint "$host")"

  # Seeds only for VMs that do not exist yet: an existing VM holds its seed ISO open in its DVD drive.
  lab_query_host "$host" || lab_fail "$(lab_host_hint "$host")"
  seeds=()
  for vm in "${VM_NAMES[@]}"; do
    [[ ${VM_HOST[$vm]} == "$host" && ${VM_STATE[$vm]} == missing ]] && seeds+=("$SEEDS/$vm.iso")
  done
  for seed in "${seeds[@]}"; do
    [[ -s $seed ]] || lab_fail "missing seed $seed - run infra/cloud-init/build-seeds.sh"
  done
  if [[ ${HOST_TARGET[$host]} == local ]]; then
    dest=$(wslpath -u "$root")
    install -m 0644 "$LAB_DIR/vms.csv" "$LAB_DIR/New-LabVM.ps1" "$dest/"
    # The seeds are built in this folder already, unless SEED_DIR points elsewhere.
    if (( ${#seeds[@]} > 0 )) && [[ $(realpath "$SEEDS") != $(realpath "$dest/seeds") ]]; then
      install -m 0644 "${seeds[@]}" "$dest/seeds/"
    fi
  else
    scp_to "$host" "$LAB_DIR/vms.csv" "$LAB_DIR/New-LabVM.ps1" "$root" || lab_fail "scp to $host failed (LAB_SCP_PREFIX in provision.conf?)"
    (( ${#seeds[@]} == 0 )) || scp_to "$host" "${seeds[@]}" "$root\\seeds" || lab_fail "scp of the seeds to $host failed"
  fi
  echo "  vms.csv and New-LabVM.ps1 in place; ${#seeds[@]} seed ISO(s) in place for the VMs still to create"

  golden="$root\\golden\\$GOLDEN_NAME"
  if [[ $host != legion ]]; then
    have=$(hash_of "$host" "$golden") || lab_fail "$(lab_host_hint "$host")"
    if [[ $have == missing ]]; then
      echo "  sending the golden image (a few minutes)..."
      scp_to "$host" "$(wslpath -u "$legion_golden")" "$root\\golden" || lab_fail "scp of the golden image to $host failed"
      have=$(hash_of "$host" "$golden")
    fi
    [[ $have == "$ref" ]] || lab_fail "golden image on $host differs from the Legion's (SHA-256 $have) - delete it there and run again"
    echo "  golden image present, SHA-256 matches"
  fi
  lab_ps "$host" "$PS_TIMEOUT_SECONDS" "Set-ItemProperty -LiteralPath '$golden' -Name IsReadOnly -Value \$true" >/dev/null \
    || lab_fail "cannot mark $golden read-only on $host"

  ps_args="-NoProfile -NonInteractive -ExecutionPolicy Bypass -File $root\\New-LabVM.ps1 -HostName $host -Root $root -SwitchName ${HOST_SWITCH[$host]} -GoldenName $GOLDEN_NAME"
  if [[ ${HOST_TARGET[$host]} == local ]]; then
    # shellcheck disable=SC2086  # the arguments are validated above and contain no spaces
    "$LAB_WINPS" $ps_args </dev/null | tr -d '\r' | sed 's/^/  /' || lab_fail "New-LabVM.ps1 reported drift or failed on $host"
  else
    "$LAB_SSH" -n -i "$LAB_SSH_KEY" -o IdentitiesOnly=yes -o BatchMode=yes "${HOST_TARGET[$host]}" "powershell $ps_args" \
      | tr -d '\r' | sed 's/^/  /' || lab_fail "New-LabVM.ps1 reported drift or failed on $host"
  fi
done
echo "Done. Start the lab with: make lab-up"
