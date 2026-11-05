#!/usr/bin/env bash
# infra/cloud-init/golden-prepare.sh - turns a fresh Ubuntu Server 24.04 install into the lab's
# golden image (plan WP1.1, D-17). Run it inside the golden VM, as the installer account:
#   sudo bash golden-prepare.sh
# It updates the system, installs the Hyper-V integration tools, makes SSH a plain service (no
# socket activation: no systemd ordering cycle with cloud-init at boot), removes what the installer
# left behind (its cloud-init and network files, its log with the account's password hash), pins
# cloud-init to the NoCloud seed, locks the installer account, deletes the SSH host keys, resets
# cloud-init and the machine-id, then powers the VM off. The next boot of any copy is a first boot.
set -euo pipefail
[[ $(id -u) -eq 0 ]] || { echo "run it with sudo" >&2; exit 1; }
installer_user=${SUDO_USER:-builder}
export DEBIAN_FRONTEND=noninteractive

echo "== packages"
apt-get update
apt-get -y full-upgrade
apt-get -y install linux-cloud-tools-virtual cloud-init openssh-server
apt-get -y autoremove --purge
apt-get clean

echo "== SSH as a plain service"
systemctl disable --now ssh.socket
rm -f /etc/systemd/system/ssh.service.d/00-socket.conf /etc/systemd/system/ssh.socket.d/addresses.conf
systemctl daemon-reload
systemctl enable ssh.service

echo "== cloud-init: installer leftovers out, NoCloud only"
rm -f /etc/cloud/cloud-init.disabled \
      /etc/cloud/cloud.cfg.d/90-installer-network.cfg \
      /etc/cloud/cloud.cfg.d/99-installer.cfg \
      /etc/cloud/cloud.cfg.d/subiquity-disable-cloudinit-networking.cfg
printf '%s\n' '# Kairos lab (plan WP1.1): first boot reads the NoCloud seed ISO and nothing else.' \
  'datasource_list: [ NoCloud, None ]' > /etc/cloud/cloud.cfg.d/99-kairos-datasource.cfg
rm -f /etc/netplan/00-installer-config.yaml /etc/netplan/50-cloud-init.yaml
rm -rf /var/log/installer

echo "== hosts file without the golden VM's name"
printf '%s\n' '127.0.0.1 localhost' '' \
  '# The following lines are desirable for IPv6 capable hosts' \
  '::1     ip6-localhost ip6-loopback' 'fe00::0 ip6-localnet' 'ff00::0 ip6-mcastprefix' \
  'ff02::1 ip6-allnodes' 'ff02::2 ip6-allrouters' > /etc/hosts

echo "== installer account locked (cloud-init deletes it on each VM's first boot)"
passwd -l "$installer_user"
rm -f "/home/$installer_user/.bash_history" /root/.bash_history

echo "== identity reset: SSH host keys, cloud-init state, machine-id, logs"
rm -f /etc/ssh/ssh_host_*
cloud-init clean --logs --machine-id --seed
journalctl --rotate >/dev/null 2>&1 || true
journalctl --vacuum-time=1s >/dev/null 2>&1 || true

echo "== golden image generalized - powering off now"
systemctl poweroff
