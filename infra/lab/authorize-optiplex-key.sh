#!/usr/bin/env bash
# infra/lab/authorize-optiplex-key.sh - gives the Legion key-only SSH access to the OptiPlex
# (plan WP0.2), from WSL2. Asks for the OptiPlex account's password once, then:
#   1. appends ~/.ssh/kairos_lab.pub to C:\ProgramData\ssh\administrators_authorized_keys (an
#      administrator's keys live there, not in the profile) as ASCII, unless it is already there;
#   2. restricts that file to Administrators and SYSTEM by SID, so it works in any Windows language
#      (sshd ignores the file otherwise);
#   3. checks that the account can run Hyper-V commands in an SSH session;
# then proves key-only access in batch mode, and finds how scp names a Windows path there.
# Idempotent: running it again changes nothing on the OptiPlex.
set -Eeuo pipefail
# shellcheck source=lablib.sh
source "$(dirname "$(readlink -f "$0")")/lablib.sh"
# shellcheck source=provision.conf
source "$LAB_DIR/provision.conf"

lab_init
host=optiplex
target=${HOST_TARGET[$host]:-}
[[ -n $target && $target != local ]] || lab_fail "hosts.csv has no remote host '$host'"
[[ -r $LAB_SSH_KEY.pub ]] || lab_fail "missing $LAB_SSH_KEY.pub - run: ssh-keygen -t ed25519 -f $LAB_SSH_KEY"
pub=$(tr -d '\r\n' < "$LAB_SSH_KEY.pub")
# A plain ed25519 key; its comment may hold letters, digits, spaces and @ . _ : , - only, because the
# key is placed inside a single-quoted PowerShell string (no quote, backslash or $ can get in) (E-16).
key_re='^ssh-ed25519 [A-Za-z0-9+/=]+( [A-Za-z0-9@._:, -]+)?$'
[[ $pub =~ $key_re ]] || lab_fail "$LAB_SSH_KEY.pub is not a plain ed25519 public key (comment: letters, digits, spaces, @ . _ : , - only)"

snippet=$(cat <<'PS'
$ProgressPreference = 'SilentlyContinue'   # no progress records (CLIXML) over SSH (C-01)
$ErrorActionPreference = 'Stop'
$key = '@PUBKEY@'
$me = [Security.Principal.WindowsIdentity]::GetCurrent()
$admins = New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')
$isAdmin = @(Get-LocalGroupMember -SID $admins.Value | Where-Object { $_.SID -eq $me.User }).Count -gt 0
if (-not $isAdmin) { throw "$($me.Name) is not in the local Administrators group - Hyper-V over SSH needs it" }
$file = Join-Path $env:ProgramData 'ssh\administrators_authorized_keys'
$lines = @()
if (Test-Path -LiteralPath $file) { $lines = @(Get-Content -LiteralPath $file | Where-Object { $_.Trim() -ne '' }) }
if ($lines -contains $key) { 'key: already authorized' } else {
  Set-Content -LiteralPath $file -Value ($lines + $key) -Encoding ascii
  'key: appended'
}
& icacls.exe $file /inheritance:r /grant '*S-1-5-32-544:F' /grant '*S-1-5-18:F' | Out-Null
if ($LASTEXITCODE -ne 0) { throw "icacls failed on $file" }
'acl: Administrators and SYSTEM only'
$null = Get-VMHost
'hyper-v: OK'
PS
)
snippet=${snippet//@PUBKEY@/$pub}
encoded=$(printf '%s' "$snippet" | iconv -f UTF-8 -t UTF-16LE | base64 -w0)

echo "Connecting to $target with its password (once; accept the host key if asked)..."
"$LAB_SSH" -o PubkeyAuthentication=no -o PreferredAuthentications=password,keyboard-interactive \
  "$target" "powershell -NoProfile -NonInteractive -EncodedCommand $encoded" | tr -d '\r'

echo "Checking key-only access in batch mode..."
remote_name=$("$LAB_SSH" -i "$LAB_SSH_KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=5 \
  "$target" hostname | tr -d '\r') || lab_fail "key-only SSH to $target failed"
echo "ssh: key-only access works (remote hostname: $remote_name)"

# scp on a Windows server: find which spelling of a path works, with a 1-line test file.
root=${LAB_ROOT_OPTIPLEX//\\//}
lab_ps "$host" "$PS_TIMEOUT_SECONDS" "New-Item -ItemType Directory -Force -Path '$LAB_ROOT_OPTIPLEX' | Out-Null" >/dev/null \
  || lab_fail "cannot create $LAB_ROOT_OPTIPLEX on $host"
probe=$(mktemp)
trap 'rm -f "$probe"' EXIT
echo "kairos scp probe" > "$probe"
found=no style=''
for prefix in '' '/'; do
  if scp -q -i "$LAB_SSH_KEY" -o IdentitiesOnly=yes -o BatchMode=yes "$probe" "$target:${prefix}$root/scp-probe.txt" 2>/dev/null; then
    found=yes style=$prefix
    break
  fi
done
lab_ps "$host" "$PS_TIMEOUT_SECONDS" "Remove-Item -Force -ErrorAction SilentlyContinue -LiteralPath '$LAB_ROOT_OPTIPLEX\\scp-probe.txt'" >/dev/null || true
[[ $found == yes ]] || lab_fail "scp to $target failed with both path spellings ('$root/...' and '/$root/...')"
if [[ $style == "$LAB_SCP_PREFIX" ]]; then
  echo "scp: works with paths like ${style}$root/... (matches LAB_SCP_PREFIX in provision.conf)"
else
  echo "scp: works with paths like ${style}$root/... - set LAB_SCP_PREFIX=\"$style\" in infra/lab/provision.conf"
fi
echo "Done: the OptiPlex accepts $LAB_SSH_KEY in batch mode."
