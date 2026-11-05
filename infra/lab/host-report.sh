#!/usr/bin/env bash
# infra/lab/host-report.sh [HOST] - prints what plan WP0.2 records about a Hyper-V host, for
# docs/lab/capacity.md: available RAM, free space per fixed volume, how much the host's existing
# dynamic VHDX files can still grow on each volume, its virtual switches, and its VMs.
# Default host: optiplex (the Legion's figures are already recorded). Changes nothing.
set -Eeuo pipefail
# shellcheck source=lablib.sh
source "$(dirname "$(readlink -f "$0")")/lablib.sh"

lab_init
host=${1:-optiplex}
[[ -n ${HOST_TARGET[$host]+set} ]] || lab_fail "unknown host '$host' (hosts.csv)"

snippet=$(cat <<'PS'
$GB = [double]1073741824
try { $avail = [int64](Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory).AvailableMBytes }
catch { $avail = [int64][math]::Floor((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1024) }
$total = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / $GB, 1)
'RAM: {0} GB installed, {1} MB available now' -f $total, $avail
''
'Fixed volumes (GB):'
Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' } | Sort-Object DriveLetter | ForEach-Object {
  '  {0}:  size {1,7:N1}   free {2,7:N1}' -f $_.DriveLetter, ($_.Size / $GB), ($_.SizeRemaining / $GB)
}
''
'Virtual switches:'
Get-VMSwitch | ForEach-Object { '  {0,-20} {1,-9} {2}' -f $_.Name, $_.SwitchType, $_.NetAdapterInterfaceDescription }
''
'Existing VMs (memory and disks, GB):'
$grow = @{}
Get-VM | Sort-Object Name | ForEach-Object {
  $vm = $_
  '  {0,-24} {1,-8} memory {2,5:N1}' -f $vm.Name, $vm.State, ($vm.MemoryStartup / $GB)
  Get-VMHardDiskDrive -VMName $vm.Name | ForEach-Object {
    if ($_.Path) {
      $v = Get-VHD -Path $_.Path
      $room = 0
      # 64-bit arithmetic: [math]::Max(0, ...) would pick the Int32 overload and fail above 2 GB.
      if ($v.VhdType -eq 'Dynamic' -or $v.VhdType -eq 'Differencing') { $room = [math]::Max([int64]0, [int64]$v.Size - [int64]$v.FileSize) }
      $drive = $_.Path.Substring(0, 1).ToUpper()
      $grow[$drive] = [double]$grow[$drive] + $room
      '      {0}  {1}  max {2,7:N1}  on disk {3,7:N1}  can still grow {4,7:N1}' -f $drive, $v.VhdType, ($v.Size / $GB), ($v.FileSize / $GB), ($room / $GB)
    }
  }
}
''
'Room the existing dynamic disks can still take, per volume (GB):'
foreach ($d in ($grow.Keys | Sort-Object)) { '  {0}:  {1,7:N1}' -f $d, ($grow[$d] / $GB) }
''
'Hyper-V default VHD folder: ' + (Get-VMHost).VirtualHardDiskPath
PS
)
echo "== $host (${HOST_TARGET[$host]}) =="
lab_ps "$host" "$PS_TIMEOUT_SECONDS" "$snippet" || lab_fail "$(lab_host_hint "$host")"
