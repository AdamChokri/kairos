#!/usr/bin/env bash
# infra/lab/lab-up.sh - powers the Kairos lab up (make lab-up, from WSL2 on the Legion).
#
# 1. Preflight - nothing starts unless the whole lab can start: every host answers with
#    Hyper-V rights, its External switch sits on a connected wired adapter, every VM
#    exists in a settled state, and each host has the memory for its stopped lab VMs.
# 2. Starts the VMs one at a time in vms.csv order, waiting for each one's SSH port.
# 3. As soon as OpenBao's VM answers, offers to unseal OpenBao. Key shares are typed,
#    never stored; pressing Enter leaves it sealed.
# 4. Prints the lab status. Exit code 0: every VM runs and answers on SSH.
set -Eeuo pipefail
# shellcheck source=lablib.sh
source "$(dirname "$(readlink -f "$0")")/lablib.sh"

lab_init

# --- 1. Preflight ------------------------------------------------------------------
for host in "${HOST_NAMES[@]}"; do
  deadline=$((SECONDS + SETTLE_SECONDS))
  while :; do
    if ! lab_query_host "$host"; then
      lab_fail "$(lab_host_hint "$host")"
    fi
    unsettled=''
    for vm in "${VM_NAMES[@]}"; do
      [[ ${VM_HOST[$vm]} == "$host" ]] || continue
      state=${VM_STATE[$vm]}
      if [[ $state == missing ]]; then
        lab_fail "$vm not found on $host - build the lab first (New-LabVM.ps1, WP1.1)"
      fi
      if [[ $state == *Critical ]]; then
        lab_fail "$vm is in state $state on $host - its storage may be unavailable; fix it in Hyper-V Manager"
      fi
      lab_is_settled "$state" || unsettled+=" $vm($state)"
    done
    [[ -z $unsettled ]] && break
    if (( SECONDS >= deadline )); then
      lab_fail "still changing state on $host after ${SETTLE_SECONDS}s:$unsettled - resolve it in Hyper-V Manager"
    fi
    sleep 3
  done

  link=${HOST_LINK[$host]:-unknown}
  if [[ $link != Up,802.3 ]]; then
    lab_fail "$host: switch '${HOST_SWITCH[$host]}' is not on a connected wired Ethernet adapter ($link) - the lab needs it (plan section 3.1)"
  fi

  avail=${HOST_AVAIL[$host]:-}
  [[ $avail =~ ^[0-9]+$ ]] || lab_fail "$host: could not read its available memory"
  need=0
  for vm in "${VM_NAMES[@]}"; do
    [[ ${VM_HOST[$vm]} == "$host" ]] || continue
    case ${VM_STATE[$vm]} in
      Off|Saved) need=$((need + ${VM_MEM[$vm]})) ;;
    esac
  done
  if (( need > 0 && avail < need + HOST_RESERVE_MB )); then
    lab_fail "$host: not enough memory - its stopped lab VMs need ${need} MB plus ${HOST_RESERVE_MB} MB for the host, and ${avail} MB are available. Nothing was started."
  fi
  if (( need > 0 && avail - need < COMFORT_FREE_MB )); then
    lab_warn "$host: about $((avail - need)) MB will stay free while the lab runs (the plan asks for ${COMFORT_FREE_MB})"
  fi
  echo "$host: ready (${avail} MB available, ${need} MB needed)"
done

# --- 2-3. Start in order, then unseal OpenBao -----------------------------------
for vm in "${VM_NAMES[@]}"; do
  verb=''
  if ! state=$(lab_vm_settle "$vm"); then
    lab_problem "$vm: $(lab_host_hint "${VM_HOST[$vm]}")"
    continue
  fi
  case $state in
    Running) echo "$vm: already running" ;;
    Paused)  echo "$vm: paused, resuming"; verb=Resume-VM ;;
    Saved)   lab_warn "$vm: restoring a saved state - shut the lab down with 'make lab-down' so that VMs are never saved"; verb=Start-VM ;;
    Off)     echo "$vm: starting"; verb=Start-VM ;;
    *)       lab_problem "$vm: unexpected state $state"; continue ;;
  esac
  if [[ -n $verb ]] && ! lab_vm_action "$vm" "$verb"; then
    lab_problem "$vm: could not be started on ${VM_HOST[$vm]}"
    continue
  fi

  printf '%s: waiting for SSH on %s ' "$vm" "${VM_IP[$vm]}"
  if lab_wait_port "${VM_IP[$vm]}" 22 "$SSH_WAIT_SECONDS"; then
    echo ' up'
  else
    echo ' no answer'
    lab_problem "$vm: SSH did not answer on ${VM_IP[$vm]} within ${SSH_WAIT_SECONDS}s - open its console in Hyper-V Manager on ${VM_HOST[$vm]}"
    continue
  fi

  if [[ $vm == "$OPENBAO_VM" ]]; then
    printf '%s: waiting for the OpenBao API ' "$vm"
    if lab_wait_port "${VM_IP[$vm]}" 8200 "$OPENBAO_WAIT_SECONDS"; then
      echo ' up'
      lab_bao_unseal || true
    else
      echo ' no answer'
      lab_warn "OpenBao does not listen on ${VM_IP[$vm]}:8200 - expected until WP1.3 installs it, a fault afterwards"
    fi
  fi
done

lab_print_status
lab_report_and_exit "Lab is up. Services inside the VMs may need another minute or two."
