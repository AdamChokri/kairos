#cloud-config
# infra/cloud-init/user-data.tpl - first-boot configuration of every lab VM (plan WP1.1, D-17).
# build-seeds.sh fills the @...@ fields from infra/lab/vms.csv; the result holds no secret
# (only the admin user's public key), so the seed ISO can stay attached.
hostname: @HOSTNAME@
manage_etc_hosts: localhost   # keeps 127.0.1.1 on the hostname; Ansible owns the lab block
timezone: Etc/UTC
users:                        # no "default" entry, so no stock "ubuntu" account
  - name: @ADMIN_USER@
    gecos: Kairos lab administrator
    groups: [adm, sudo]
    shell: /bin/bash
    lock_passwd: true         # key only: the account has no password
    sudo: "ALL=(ALL) NOPASSWD:ALL"
    ssh_authorized_keys:
      - @ADMIN_KEY@
disable_root: true
ssh_pwauth: false
# Host keys: cloud-init generates new ones on first boot (its default), so every VM has its own.
runcmd:
  - [userdel, --remove, builder]   # the golden image's installer account, locked since generalizing
