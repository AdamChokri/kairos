#!/usr/bin/env bash
# infra/lab/lab-down.sh - shuts the Kairos lab down cleanly (make lab-down, from WSL2).
#
# The VMs stop one at a time in reverse vms.csv order, each through its guest operating
# system with up to SHUTDOWN_SECONDS to reach Off. Nothing is ever saved or powered off
# hard: a VM that does not stop, a saved VM or an unreachable host is reported, the other
# VMs still shut down, and the exit code is 1. Let running Jenkins builds finish first.
set -Eeuo pipefail
# shellcheck source=lablib.sh
source "$(dirname "$(readlink -f "$0")")/lablib.sh"

lab_init

for host in "${HOST_NAMES[@]}"; do
  lab_query_host "$host" || lab_warn "$(lab_host_hint "$host")"
done

for (( i = ${#VM_NAMES[@]} - 1; i >= 0; i-- )); do
  vm=${VM_NAMES[$i]}
  host=${VM_HOST[$vm]}
  if [[ ${HOST_OK[$host]:-no} != yes ]]; then
    lab_problem "$vm: not stopped - $host cannot be reached"
    continue
  fi
  if ! state=$(lab_vm_settle "$vm"); then
    lab_problem "$vm: state unknown - $(lab_host_hint "$host")"
    continue
  fi
  case $state in
    Off)
      echo "$vm: already off"
      continue ;;
    Saved)
      lab_problem "$vm: is in a saved state - run 'make lab-up' then 'make lab-down' to shut it down cleanly; a saved state is never discarded here"
      continue ;;
    Paused)
      echo "$vm: paused, resuming so that it can shut down"
      if ! lab_vm_action "$vm" Resume-VM; then
        lab_problem "$vm: could not be resumed"
        continue
      fi ;;
    Running) ;;
    *)
      lab_problem "$vm: is in state $state - resolve it in Hyper-V Manager"
      continue ;;
  esac

  printf '%s: shutting down ' "$vm"
  # Stop-VM without -Save or -TurnOff shuts the guest down through its own operating
  # system. With -Force, as documented, a guest with unsaved work gets five minutes to
  # save it and a locked guest is not waited for. Stop-VM returns once the VM is Off;
  # timeout(1) bounds the call, then the state is checked once more.
  rc=0
  err=$(lab_ps "$host" "$SHUTDOWN_SECONDS" "Stop-VM -Name '$vm' -Force" 2>&1 >/dev/null) || rc=$?
  if lab_wait_off "$vm" 15; then
    echo ' off'
  else
    echo ' still running'
    if (( rc == 124 )); then
      reason="did not reach Off within ${SHUTDOWN_SECONDS}s"
    else
      reason="the shutdown request failed (${err:-no details})"
    fi
    lab_problem "$vm: $reason - open its console in Hyper-V Manager on $host; turn it off there only if the guest is hung, and never save its state"
  fi
done

lab_print_status
lab_report_and_exit "Lab is off."
