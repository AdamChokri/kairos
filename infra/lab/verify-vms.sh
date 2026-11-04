#!/usr/bin/env bash
# infra/lab/verify-vms.sh - checks every lab VM after its first boot (plan WP1.1 "done when"):
# the right hostname, its reserved address on eth0, a machine-id and an SSH host key of its own,
# no systemd "ordering cycle" in this boot's journal, cloud-init finished without errors, and the
# golden image's installer account gone. Runs from WSL2 over SSH as the admin user. Changes nothing.
# Exit code 0 only when every VM passes every check.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${LAB_ADMIN_USER:=adam}"
: "${LAB_ADMIN_KEY:=$HOME/.ssh/kairos_admin}"

remote=$(cat <<'REMOTE'
printf 'hostname=%s\n' "$(hostname)"
printf 'address=%s\n' "$(ip -4 -o addr show dev eth0 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)"
printf 'machine_id=%s\n' "$(cat /etc/machine-id)"
printf 'host_key=%s\n' "$(ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub | awk '{print $2}')"
printf 'cycles=%s\n' "$(sudo journalctl -b --no-pager 2>/dev/null | grep -ci 'ordering cycle')"
printf 'cloud_init=%s\n' "$(cloud-init status 2>/dev/null | awk '/^status:/ {print $2}')"
printf 'builder=%s\n' "$(getent passwd builder >/dev/null && echo present || echo absent)"
REMOTE
)

declare -A seen_id=() seen_key=()
failures=0
printf '%-12s %-15s %-8s %-6s %-6s %-6s %-6s %-6s %s\n' VM ADDRESS HOSTNAME ADDR MID KEY CYCLES CINIT BUILDER
while IFS=, read -r name _ ip _; do
  [[ -z $name || $name == name ]] && continue
  if ! out=$(ssh -i "$LAB_ADMIN_KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=5 \
        -o StrictHostKeyChecking=accept-new "$LAB_ADMIN_USER@$ip" "$remote" 2>&1); then
    printf '%-12s %-15s FAIL: no SSH (%s)\n' "$name" "$ip" "$(tail -1 <<<"$out")"
    failures=$((failures + 1)); continue
  fi
  declare -A v=()
  while IFS='=' read -r k val; do [[ -n $k ]] && v[$k]=$val; done <<<"$out"
  row=()
  check() { if [[ $1 == yes ]]; then row+=(ok); else row+=(FAIL); failures=$((failures + 1)); fi; }
  check "$([[ ${v[hostname]:-} == "$name" ]] && echo yes)"
  check "$([[ ${v[address]:-} == "$ip" ]] && echo yes)"
  check "$([[ ${v[machine_id]:-} =~ ^[0-9a-f]{32}$ && -z ${seen_id[${v[machine_id]}]:-} ]] && echo yes)"
  check "$([[ -n ${v[host_key]:-} && -z ${seen_key[${v[host_key]:-x}]:-} ]] && echo yes)"
  check "$([[ ${v[cycles]:-} == 0 ]] && echo yes)"
  check "$([[ ${v[cloud_init]:-} == "done" ]] && echo yes)"
  check "$([[ ${v[builder]:-} == absent ]] && echo yes)"
  [[ -n ${v[machine_id]:-} ]] && seen_id[${v[machine_id]}]=$name
  [[ -n ${v[host_key]:-} ]] && seen_key[${v[host_key]}]=$name
  printf '%-12s %-15s %-8s %-6s %-6s %-6s %-6s %-6s %s\n' "$name" "$ip" "${row[@]}"
  unset v
done < <(tr -d '\r' < "$DIR/vms.csv")

echo
if (( failures == 0 )); then echo "All VMs pass."; else echo "$failures check(s) failed."; fi
(( failures == 0 ))
