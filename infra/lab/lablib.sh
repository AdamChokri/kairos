# infra/lab/lablib.sh - shared functions of lab-up.sh, lab-down.sh and lab-status.sh.
# Sourced, never executed. Runs in WSL2 on the Legion: the Legion's Hyper-V is driven
# through Windows PowerShell (WSL interop), the OptiPlex's over SSH with a key.
# Needs bash 4+, coreutils, iconv, curl, python3 and an SSH client (all present on WSL2 Ubuntu).
# shellcheck shell=bash
# shellcheck disable=SC2034  # arrays filled here are read by the scripts that source this file

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lab.conf
source "$LAB_DIR/lab.conf"

# The arrays below are filled here and read by lab-up.sh, lab-down.sh and lab-status.sh.
declare -A HOST_TARGET=() HOST_SWITCH=() HOST_LINK=() HOST_AVAIL=() HOST_OK=()
declare -A VM_HOST=() VM_IP=() VM_STATE=() VM_MEM=()
HOST_NAMES=()
VM_NAMES=()
PROBLEMS=()

lab_warn()    { printf 'WARNING: %s\n' "$*" >&2; }
lab_fail()    { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
lab_problem() { PROBLEMS+=("$*"); }

# --- Configuration ---------------------------------------------------------------

lab_init() {
  local tool
  for tool in timeout iconv base64 curl python3 "$LAB_SSH"; do
    command -v "$tool" >/dev/null 2>&1 || lab_fail "missing tool: $tool"
  done
  [[ -x $LAB_WINPS ]] || lab_fail "Windows PowerShell not found at $LAB_WINPS - run this from WSL2 on the Legion"
  lab_load_csv
  [[ -n ${VM_HOST[$OPENBAO_VM]+set} ]] || lab_fail "lab.conf: OPENBAO_VM '$OPENBAO_VM' is not listed in vms.csv"
}

lab_load_csv() {
  local host target switch name ip
  while IFS=, read -r host _ target switch; do
    [[ -z $host || $host == host ]] && continue
    [[ $host =~ ^[a-z0-9-]+$ ]] || lab_fail "hosts.csv: bad host name '$host'"
    [[ $switch =~ ^[A-Za-z0-9\ ._-]+$ ]] || lab_fail "hosts.csv: bad switch name '$switch'"
    [[ $target == local || $target =~ ^[A-Za-z0-9._-]+@[A-Za-z0-9._-]+$ ]] || lab_fail "hosts.csv: bad ssh_target '$target'"
    HOST_NAMES+=("$host")
    HOST_TARGET[$host]=$target
    HOST_SWITCH[$host]=$switch
  done < <(tr -d '\r' < "$LAB_DIR/hosts.csv")
  while IFS=, read -r name host ip _; do
    [[ -z $name || $name == name ]] && continue
    [[ $name =~ ^[A-Za-z0-9-]+$ ]] || lab_fail "vms.csv: bad VM name '$name'"
    [[ -n ${HOST_TARGET[$host]+set} ]] || lab_fail "vms.csv: $name is on unknown host '$host'"
    [[ $ip =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || lab_fail "vms.csv: bad address '$ip' for $name"
    VM_NAMES+=("$name")
    VM_HOST[$name]=$host
    VM_IP[$name]=$ip
  done < <(tr -d '\r' < "$LAB_DIR/vms.csv")
  (( ${#VM_NAMES[@]} > 0 )) || lab_fail "vms.csv lists no VM"
}

# --- Running PowerShell on a Hyper-V host -----------------------------------------

# lab_ps HOST TIMEOUT SNIPPET - runs SNIPPET on HOST and prints its output.
# -EncodedCommand carries the snippet through every shell layer (bash, ssh, cmd.exe,
# PowerShell) untouched, so no quoting can break it. Exit status 0 = the snippet ran.
lab_ps() {
  local host=$1 timeout_s=$2 script encoded target
  script="\$ProgressPreference = 'SilentlyContinue'
\$ErrorActionPreference = 'Stop'
try {
$3
  exit 0
} catch {
  [Console]::Error.WriteLine(\$_.Exception.Message)
  exit 1
}"
  encoded=$(printf '%s' "$script" | iconv -f UTF-8 -t UTF-16LE | base64 -w0)
  target=${HOST_TARGET[$host]}
  if [[ $target == local ]]; then
    timeout "$timeout_s" "$LAB_WINPS" -NoProfile -NonInteractive -EncodedCommand "$encoded" </dev/null | tr -d '\r'
  else
    timeout "$timeout_s" "$LAB_SSH" -n -i "$LAB_SSH_KEY" -o IdentitiesOnly=yes -o BatchMode=yes \
      -o ConnectTimeout=5 -o ServerAliveInterval=5 -o ServerAliveCountMax=2 \
      "$target" "powershell -NoProfile -NonInteractive -EncodedCommand $encoded" | tr -d '\r'
  fi
}

lab_host_hint() {
  local host=$1
  if [[ ${HOST_TARGET[$host]} == local ]]; then
    printf 'cannot run Hyper-V commands on %s - are you in its Hyper-V Administrators group (plan section 14)?' "$host"
  else
    printf 'cannot run Hyper-V commands on %s over SSH (%s) - is it on, is key %s authorized there (WP0.2), and does that account have Hyper-V rights?' \
      "$host" "${HOST_TARGET[$host]}" "$LAB_SSH_KEY"
  fi
}

# lab_query_host HOST - one call per host: Hyper-V access, the switch's physical link,
# available memory, and the state and memory of this host's lab VMs.
lab_query_host() {
  local host=$1 names='' vm out kind a b c snippet
  for vm in "${VM_NAMES[@]}"; do
    if [[ ${VM_HOST[$vm]} == "$host" ]]; then
      names+="${names:+,}'$vm'"
      VM_STATE[$vm]=missing
      VM_MEM[$vm]=0
    fi
  done
  snippet=$(cat <<'PS'
$null = Get-VMHost
$link = 'noswitch'
$sw = Get-VMSwitch -Name '@SWITCH@' -ErrorAction SilentlyContinue
if ($sw) {
  $link = 'noadapter'
  if ($sw.NetAdapterInterfaceDescription) {
    $na = Get-NetAdapter -InterfaceDescription $sw.NetAdapterInterfaceDescription -ErrorAction SilentlyContinue
    if ($na) { $link = '{0},{1}' -f $na.Status, $na.PhysicalMediaType }
  }
}
try {
  $avail = [int64](Get-CimInstance -ClassName Win32_PerfFormattedData_PerfOS_Memory).AvailableMBytes
} catch {
  $avail = [int64][math]::Floor((Get-CimInstance -ClassName Win32_OperatingSystem).FreePhysicalMemory / 1024)
}
'host|{0}|{1}' -f $link, $avail
Get-VM -Name @NAMES@ -ErrorAction SilentlyContinue | ForEach-Object {
  'vm|{0}|{1}|{2}' -f $_.Name, $_.State, [int64]($_.MemoryStartup / 1048576)
}
PS
)
  [[ -n $names ]] || names="'no-lab-vm-on-this-host'"
  snippet=${snippet//@SWITCH@/${HOST_SWITCH[$host]}}
  snippet=${snippet//@NAMES@/$names}
  out=$(lab_ps "$host" "$PS_TIMEOUT_SECONDS" "$snippet") || { HOST_OK[$host]=no; return 1; }
  HOST_OK[$host]=yes
  while IFS='|' read -r kind a b c; do
    case $kind in
      host) HOST_LINK[$host]=$a; HOST_AVAIL[$host]=$b ;;
      vm)   if [[ -n ${VM_HOST[$a]+set} ]]; then VM_STATE[$a]=$b; VM_MEM[$a]=$c; fi ;;
    esac
  done <<<"$out"
  return 0
}

lab_is_settled() { [[ $1 == Running || $1 == Off || $1 == Saved || $1 == Paused ]]; }

lab_vm_state() {   # lab_vm_state VM -> prints the VM's current state
  local vm=$1
  lab_ps "${VM_HOST[$vm]}" "$PS_TIMEOUT_SECONDS" "[string](Get-VM -Name '$vm').State"
}

lab_vm_action() {  # lab_vm_action VM Start-VM|Resume-VM
  local vm=$1 verb=$2
  lab_ps "${VM_HOST[$vm]}" "$PS_TIMEOUT_SECONDS" "$verb -Name '$vm'" >/dev/null
}

# lab_vm_settle VM - waits while the VM is starting, stopping, saving or resuming.
lab_vm_settle() {
  local vm=$1 state deadline=$((SECONDS + SETTLE_SECONDS))
  while :; do
    state=$(lab_vm_state "$vm") || return 1
    if lab_is_settled "$state" || [[ $state == *Critical ]] || (( SECONDS >= deadline )); then
      printf '%s' "$state"
      return 0
    fi
    sleep 3
  done
}

# --- Network checks --------------------------------------------------------------

lab_port_open() {  # lab_port_open ADDRESS PORT
  # shellcheck disable=SC2016  # $1 and $2 belong to the inner bash
  timeout 3 bash -c 'exec 3<>"/dev/tcp/$1/$2"' _ "$1" "$2" 2>/dev/null
}

lab_wait_port() {  # lab_wait_port ADDRESS PORT SECONDS - prints a dot per attempt
  local deadline=$((SECONDS + $3))
  while (( SECONDS < deadline )); do
    lab_port_open "$1" "$2" && return 0
    printf '.'
    sleep 3
  done
  return 1
}

# --- OpenBao ---------------------------------------------------------------------

# lab_bao_curl ARGS... - curl to OpenBao at its VM's address from vms.csv. TLS is still
# checked against the lab CA for the name in OPENBAO_URL, so no DNS or hosts entry is needed.
lab_bao_curl() {
  local hostport=${OPENBAO_URL#*://}
  hostport=${hostport%%/*}
  [[ $hostport == *:* ]] || hostport+=':443'
  curl -sS --cacert "$LAB_CA_CERT" --resolve "$hostport:${VM_IP[$OPENBAO_VM]}" "$@"
}

# lab_bao_status - prints "sealed|threshold|progress", or "unreachable".
lab_bao_status() {
  local out
  out=$(lab_bao_curl --max-time 5 "$OPENBAO_URL/v1/sys/seal-status" 2>/dev/null) || { echo unreachable; return 0; }
  python3 -c 'import json, sys
d = json.load(sys.stdin)
print("%s|%s|%s" % (str(d.get("sealed")).lower(), d.get("t"), d.get("progress")))' <<<"$out" 2>/dev/null || echo unreachable
}

# lab_bao_unseal - asks for key shares until OpenBao is unsealed. A share is read
# silently, sent through stdin, and never written to disk, argv or the screen.
lab_bao_unseal() {
  local sealed threshold progress share code
  if [[ ! -r $LAB_CA_CERT ]]; then
    lab_warn "OpenBao check skipped: lab CA certificate not found at $LAB_CA_CERT"
    return 1
  fi
  while :; do
    IFS='|' read -r sealed threshold progress <<<"$(lab_bao_status)"
    case $sealed in
      false) echo "OpenBao: unsealed"; return 0 ;;
      true)  ;;
      *)     lab_warn "OpenBao does not answer on $OPENBAO_URL"; return 1 ;;
    esac
    if [[ ! -t 0 ]]; then
      lab_warn "OpenBao is sealed and this is not an interactive terminal - run 'make lab-up' again from a terminal to unseal it"
      return 1
    fi
    read -r -s -p "OpenBao is sealed: unseal key share $((progress + 1)) of $threshold (Enter to skip): " share
    echo
    if [[ -z $share ]]; then
      lab_warn "OpenBao left sealed - pipelines and the application hosts wait until it is unsealed"
      return 1
    fi
    if [[ ! $share =~ ^[A-Za-z0-9+/=]+$ ]]; then
      share=''
      echo "That is not a key share (base64 or hex expected) - try again."
      continue
    fi
    code=$(printf '{"key": "%s"}' "$share" | lab_bao_curl --max-time 10 \
      -o /dev/null -w '%{http_code}' --data @- "$OPENBAO_URL/v1/sys/unseal" 2>/dev/null) || code=000
    share=''
    [[ $code == 200 ]] || echo "OpenBao refused that share (HTTP $code) - try again."
  done
}

# --- Reporting -------------------------------------------------------------------

lab_refresh_all() {
  local host
  for host in "${HOST_NAMES[@]}"; do
    lab_query_host "$host" 2>/dev/null || lab_warn "$(lab_host_hint "$host")"
  done
}

lab_wait_off() {  # lab_wait_off VM SECONDS - polls until the VM is Off
  local vm=$1 deadline=$((SECONDS + $2)) state
  while :; do
    state=$(lab_vm_state "$vm" 2>/dev/null) || state=unknown
    [[ $state == Off ]] && return 0
    (( SECONDS < deadline )) || return 1
    sleep 3
  done
}

lab_print_status() {
  local vm host state ssh bao
  lab_refresh_all
  printf '\n%-12s %-9s %-10s %-15s %s\n' VM HOST STATE ADDRESS SSH
  for vm in "${VM_NAMES[@]}"; do
    host=${VM_HOST[$vm]}
    state=${VM_STATE[$vm]:-unknown}
    [[ ${HOST_OK[$host]:-no} == yes ]] || state=unknown
    ssh=-
    if [[ $state == Running ]]; then
      if lab_port_open "${VM_IP[$vm]}" 22; then ssh=up; else ssh=down; fi
    fi
    printf '%-12s %-9s %-10s %-15s %s\n' "$vm" "$host" "$state" "${VM_IP[$vm]}" "$ssh"
  done
  if [[ -n ${VM_HOST[$OPENBAO_VM]+set} && ${VM_STATE[$OPENBAO_VM]:-} == Running ]]; then
    IFS='|' read -r bao _ <<<"$(lab_bao_status)"
    case $bao in
      false) echo "OpenBao: unsealed" ;;
      true)  echo "OpenBao: SEALED" ;;
      *)     echo "OpenBao: not answering" ;;
    esac
  fi
  echo
}

lab_report_and_exit() {  # prints every problem; exit 0 only when there was none
  local problem
  if (( ${#PROBLEMS[@]} > 0 )); then
    for problem in "${PROBLEMS[@]}"; do printf 'ERROR: %s\n' "$problem" >&2; done
    exit 1
  fi
  echo "$1"
  exit 0
}
