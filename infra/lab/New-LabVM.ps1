<#
.SYNOPSIS
  Creates this host's Kairos lab VMs from infra/lab/vms.csv, or brings existing ones back to it.

.DESCRIPTION
  Plan WP1.1, D-17. Run on each Hyper-V host for its own VMs (provision-vms.sh does it for both).
  For every VM of -HostName in vms.csv:
    - missing: copies the golden VHDX, grows it to the VM's disk size, creates a Generation 2 VM
      with static memory, the fixed MAC, the External switch, Secure Boot (UEFI CA template),
      AutomaticStartAction Nothing, AutomaticStopAction ShutDown, checkpoints disabled, and the
      VM's NoCloud seed ISO in a DVD drive; boots from the disk. The VM is left Off.
    - present and Off: corrects every setting above that drifted (a disk is only ever grown).
    - present and running: reports drift and changes nothing.
  Idempotent: a second run reports "ok" for every VM. Exit code 0 = every VM matches vms.csv.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File D:\Projects\Kairos\New-LabVM.ps1 -HostName legion -Root D:\Projects\Kairos
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)] [string] $HostName,
  [Parameter(Mandatory = $true)] [string] $Root,
  [string] $SwitchName = 'External',
  [string] $GoldenName = 'ubuntu-24.04-golden.vhdx'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$csvPath = Join-Path $Root 'vms.csv'
$golden = Join-Path (Join-Path $Root 'golden') $GoldenName
$seedDir = Join-Path $Root 'seeds'
$vmRoot = Join-Path $Root 'Hyper-V'
$GB = [int64]1073741824

if (-not (Test-Path -LiteralPath $csvPath)) { throw "missing $csvPath" }
if (-not (Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue)) { throw "no Hyper-V switch named '$SwitchName' on this host" }

$rows = @(Import-Csv -LiteralPath $csvPath | Where-Object { $_.host -eq $HostName })
if ($rows.Count -eq 0) { throw "vms.csv lists no VM for host '$HostName'" }

$script:drift = 0

function Write-State([string] $vm, [string] $state, [string] $detail) {
  '{0,-12} {1,-8} {2}' -f $vm, $state, $detail
}

function Format-Mac([string] $mac) { ($mac.ToUpper() -replace '[^0-9A-F]', '') }

function New-LabMachine($row) {
  $name = $row.name
  $seed = Join-Path $seedDir ($name + '.iso')
  if (-not (Test-Path -LiteralPath $golden)) { throw "missing golden image $golden" }
  if (-not (Test-Path -LiteralPath $seed)) { throw "missing seed ISO $seed (build-seeds.sh, then provision-vms.sh)" }

  $diskDir = Join-Path (Join-Path $vmRoot $name) 'Virtual Hard Disks'
  $vhd = Join-Path $diskDir ($name + '.vhdx')
  if (Test-Path -LiteralPath $vhd) { throw "$vhd exists but no VM '$name' does - remove the stale disk by hand" }
  New-Item -ItemType Directory -Force -Path $diskDir | Out-Null
  Copy-Item -LiteralPath $golden -Destination $vhd
  Set-ItemProperty -LiteralPath $vhd -Name IsReadOnly -Value $false   # the golden copy is read-only
  $size = [int64]$row.disk_gb * $GB
  if ((Get-VHD -Path $vhd).Size -lt $size) { Resize-VHD -Path $vhd -SizeBytes $size }

  $newVm = @{
    Name = $name; Generation = 2; MemoryStartupBytes = ([int64]$row.memory_gb * $GB)
    VHDPath = $vhd; SwitchName = $SwitchName; Path = $vmRoot
  }
  New-VM @newVm | Out-Null
  $setVm = @{
    Name = $name; ProcessorCount = [int]$row.cpu; StaticMemory = $true
    AutomaticStartAction = 'Nothing'; AutomaticStopAction = 'ShutDown'; CheckpointType = 'Disabled'
    Notes = ('Kairos lab: ' + $row.role)
  }
  Set-VM @setVm
  Set-VMNetworkAdapter -VMName $name -StaticMacAddress (Format-Mac $row.mac)
  Set-VMFirmware -VMName $name -EnableSecureBoot On -SecureBootTemplate MicrosoftUEFICertificateAuthority
  Add-VMDvdDrive -VMName $name -Path $seed
  Set-VMFirmware -VMName $name -FirstBootDevice (Get-VMHardDiskDrive -VMName $name | Select-Object -First 1)
  Write-State $name 'created' ('{0} vCPU, {1} GB, {2} GB disk, MAC {3}' -f $row.cpu, $row.memory_gb, $row.disk_gb, (Format-Mac $row.mac))
}

function Test-LabMachine($row, $vm) {
  $name = $row.name
  $issues = New-Object System.Collections.Generic.List[string]
  $fixes = New-Object System.Collections.Generic.List[scriptblock]
  $mem = [int64]$row.memory_gb * $GB
  $size = [int64]$row.disk_gb * $GB
  $mac = Format-Mac $row.mac

  if ($vm.ProcessorCount -ne [int]$row.cpu) {
    $issues.Add("vCPU $($vm.ProcessorCount) (want $($row.cpu))")
    $fixes.Add({ Set-VM -Name $name -ProcessorCount ([int]$row.cpu) })
  }
  if ($vm.DynamicMemoryEnabled -or $vm.MemoryStartup -ne $mem) {
    $issues.Add("memory $([int64]($vm.MemoryStartup / $GB)) GB dynamic=$($vm.DynamicMemoryEnabled) (want $($row.memory_gb) GB static)")
    $fixes.Add({ Set-VM -Name $name -StaticMemory -MemoryStartupBytes $mem })
  }
  if ($vm.AutomaticStartAction -ne 'Nothing' -or $vm.AutomaticStopAction -ne 'ShutDown') {
    $issues.Add("automatic actions $($vm.AutomaticStartAction)/$($vm.AutomaticStopAction) (want Nothing/ShutDown)")
    $fixes.Add({ Set-VM -Name $name -AutomaticStartAction Nothing -AutomaticStopAction ShutDown })
  }
  if ($vm.CheckpointType -ne 'Disabled') {
    $issues.Add("checkpoints $($vm.CheckpointType) (want Disabled)")
    $fixes.Add({ Set-VM -Name $name -CheckpointType Disabled })
  }
  $nic = @(Get-VMNetworkAdapter -VMName $name)
  if ($nic.Count -ne 1 -or $nic[0].DynamicMacAddressEnabled -or (Format-Mac $nic[0].MacAddress) -ne $mac -or $nic[0].SwitchName -ne $SwitchName) {
    $issues.Add("network adapter (want one, MAC $mac static, on '$SwitchName')")
    $fixes.Add({
      $a = Get-VMNetworkAdapter -VMName $name | Select-Object -First 1
      Connect-VMNetworkAdapter -VMNetworkAdapter $a -SwitchName $SwitchName
      Set-VMNetworkAdapter -VMNetworkAdapter $a -StaticMacAddress $mac
    })
  }
  $fw = Get-VMFirmware -VMName $name
  if ($fw.SecureBoot -ne 'On' -or $fw.SecureBootTemplate -ne 'MicrosoftUEFICertificateAuthority') {
    $issues.Add("Secure Boot $($fw.SecureBoot)/$($fw.SecureBootTemplate) (want On/MicrosoftUEFICertificateAuthority)")
    $fixes.Add({ Set-VMFirmware -VMName $name -EnableSecureBoot On -SecureBootTemplate MicrosoftUEFICertificateAuthority })
  }
  $disk = Get-VMHardDiskDrive -VMName $name | Select-Object -First 1
  if ($disk) {
    $have = (Get-VHD -Path $disk.Path).Size
    if ($have -lt $size) {
      $issues.Add("disk $([int64]($have / $GB)) GB (want $($row.disk_gb) GB)")
      $fixes.Add({ Resize-VHD -Path $disk.Path -SizeBytes $size })
    } elseif ($have -gt $size) {
      $issues.Add("disk $([int64]($have / $GB)) GB is larger than $($row.disk_gb) GB - never shrunk; update vms.csv")
    }
  } else {
    $issues.Add('no hard disk')
  }

  if ($issues.Count -eq 0) { Write-State $name 'ok' ([string]$vm.State); return }
  if ($vm.State -ne 'Off') {
    $script:drift++
    Write-State $name 'drift' (($issues -join '; ') + ' - stop the VM and run again to correct it')
    return
  }
  foreach ($fix in $fixes) { & $fix }
  $left = @($issues | Where-Object { $_ -like '*never shrunk*' -or $_ -eq 'no hard disk' })
  if ($left.Count -gt 0) { $script:drift++; Write-State $name 'drift' ($left -join '; ') }
  else { Write-State $name 'fixed' ($issues -join '; ') }
}

foreach ($row in $rows) {
  if ($row.name -notmatch '^[A-Za-z0-9-]+$') { throw "bad VM name '$($row.name)' in vms.csv" }
  $vm = Get-VM -Name $row.name -ErrorAction SilentlyContinue
  if ($vm) { Test-LabMachine $row $vm } else { New-LabMachine $row }
}

if ($script:drift -gt 0) { exit 1 }
exit 0
