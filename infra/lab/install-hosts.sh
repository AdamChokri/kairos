#!/usr/bin/env bash
# infra/lab/install-hosts.sh - writes the lab names of lab-hosts.txt into the Legion's two hosts
# files (plan WP1.1, E-15), from WSL2:
#   1. the Windows hosts file - read by the browser and every Windows program. Windows shows one UAC
#      prompt: that file needs an administrator. A copy of the previous file is kept as
#      hosts.kairos-backup;
#   2. WSL2's own /etc/hosts - read by Ansible, the bao CLI and every lab script. This Legion's
#      /etc/wsl.conf sets generateHosts = false, so WSL2 never copies the Windows file at start; the
#      block is written here directly (sudo asks for your password). A copy of the previous file is
#      kept as /etc/hosts.kairos-backup.
# In both files only the block between "# BEGIN kairos-lab" and "# END kairos-lab" is replaced (or
# appended the first time); every other line stays as it is. Idempotent: a second run reports
# "unchanged" twice and changes nothing. No WSL2 restart is needed afterwards.
set -Eeuo pipefail
# shellcheck source=lablib.sh
source "$(dirname "$(readlink -f "$0")")/lablib.sh"

lab_init
block_file="$LAB_DIR/lab-hosts.txt"
hosts_wsl=${WIN_HOSTS_FILE:-/mnt/c/Windows/System32/drivers/etc/hosts}
etc_hosts=${WSL_HOSTS_FILE:-/etc/hosts}
block=$(tr -d '\r' < "$block_file")
[[ $block == "# BEGIN kairos-lab"*"# END kairos-lab" ]] || lab_fail "$block_file must start with '# BEGIN kairos-lab' and end with '# END kairos-lab'"
[[ $block =~ ^[[:print:][:space:]]*$ ]] || lab_fail "$block_file must be plain ASCII"

block_in() { tr -d '\r' < "$1" | sed -n '/^# BEGIN kairos-lab/,/^# END kairos-lab/p'; }

# --- 1. The Windows hosts file ----------------------------------------------------
if [[ -r $hosts_wsl && $(block_in "$hosts_wsl") == "$block" ]]; then
  echo "unchanged: the Windows hosts file already holds the lab block"
else
  inner=$(cat <<'PS'
$ErrorActionPreference = 'Stop'
$hosts = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
$block = (@'
@BLOCK@
'@).Replace("`r`n", "`n").Replace("`n", "`r`n")
$text = ''
if (Test-Path -LiteralPath $hosts) { $text = [IO.File]::ReadAllText($hosts) }
$pattern = '(?ms)^# BEGIN kairos-lab.*?^# END kairos-lab[^\r\n]*\r?\n?'
if ([regex]::IsMatch($text, $pattern)) {
  $new = [regex]::Replace($text, $pattern, ($block + "`r`n"))
} else {
  $new = $text.TrimEnd("`r", "`n") + "`r`n`r`n" + $block + "`r`n"
}
Copy-Item -LiteralPath $hosts -Destination ($hosts + '.kairos-backup') -Force
[IO.File]::WriteAllText($hosts, $new, [Text.Encoding]::ASCII)
PS
)
  inner=${inner//@BLOCK@/$block}
  inner_enc=$(printf '%s' "$inner" | iconv -f UTF-8 -t UTF-16LE | base64 -w0)
  outer="Start-Process -FilePath powershell.exe -Verb RunAs -Wait -WindowStyle Hidden -ArgumentList '-NoProfile','-NonInteractive','-EncodedCommand','$inner_enc'"

  echo "Windows will ask for administrator approval (UAC) to edit its hosts file..."
  lab_ps legion 120 "$outer" >/dev/null || lab_fail "the elevated update did not run (UAC declined?)"
  [[ $(block_in "$hosts_wsl") == "$block" ]] || lab_fail "the Windows hosts file does not hold the expected block after the update"
  echo "updated: the Windows hosts file now holds the lab block (backup: hosts.kairos-backup)"
fi

# --- 2. WSL2's /etc/hosts (generateHosts = false, E-15) ------------------------------
if [[ $(block_in "$etc_hosts") == "$block" ]]; then
  echo "unchanged: $etc_hosts already holds the lab block"
else
  new=$(mktemp)
  trap 'rm -f "$new"' EXIT
  # Every line outside an existing kairos-lab block, trailing blank lines dropped, then the block.
  awk '/^# BEGIN kairos-lab/ {skip = 1; next}
       /^# END kairos-lab/   {skip = 0; next}
       !skip {lines[++n] = $0}
       END {while (n > 0 && lines[n] ~ /^[[:space:]]*$/) n--
            for (i = 1; i <= n; i++) print lines[i]}' "$etc_hosts" > "$new"
  printf '\n%s\n' "$block" >> "$new"
  echo "sudo writes the lab block into $etc_hosts (backup: $etc_hosts.kairos-backup)..."
  sudo cp -p "$etc_hosts" "$etc_hosts.kairos-backup"
  sudo install -m 0644 -o root -g root "$new" "$etc_hosts"
  [[ $(block_in "$etc_hosts") == "$block" ]] || lab_fail "$etc_hosts does not hold the expected block after the update"
  echo "updated: $etc_hosts now holds the lab block"
fi
echo "check: getent hosts openbao.kairos.lab jenkins.kairos.lab prod.kairos.lab"
