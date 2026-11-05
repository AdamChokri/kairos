# infra/cloud-init/network-config.tpl - netplan v2 for every lab VM (plan section 3.1).
# The VM keeps the fixed MAC that New-LabVM.ps1 sets, and asks for its address with that MAC as
# the DHCP client identifier, so the router's reservation recognises it.
version: 2
ethernets:
  eth0:
    match:
      macaddress: "@MAC@"
    set-name: eth0
    dhcp4: true
    dhcp-identifier: mac
    dhcp6: false
