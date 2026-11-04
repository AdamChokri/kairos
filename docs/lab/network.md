# Lab network

Plan section 3.1 and WP0.2: the single reference for every router the lab sits behind. The lab sits behind **one router**, the same device at home and at school (the router you carry), so every reservation below is made once, on it.

LAN: 192.168.1.0/24. Gateway and DNS: the router, 192.168.1.1. The VMs ask for their address with their MAC as DHCP client identifier (`dhcp-identifier: mac`).

| Address | Name(s) | Machine | MAC | Reservation on the router |
|---|---|---|---|---|
| 192.168.1.30 | — | Legion (Ethernet, vEthernet External; also set statically on the host) | 6C:24:08:3F:0C:04 | ☑ |
| 192.168.1.34 | — | OptiPlex (Ethernet, vEthernet External) | A4:BB:6D:91:9A:60 | ☑ |
| 192.168.1.70 | `openbao.kairos.lab` | `dso-bao` | 00:15:5D:7A:00:70 | ☑ |
| 192.168.1.71 | `jenkins.kairos.lab`, `jenkins-res.kairos.lab` | `dso-jenkins` | 00:15:5D:7A:00:71 | ☑ |
| 192.168.1.72 | `agent.kairos.lab` | `dso-agent` | 00:15:5D:7A:00:72 | ☑ |
| 192.168.1.73 | `sonar.kairos.lab` | `dso-sonar` | 00:15:5D:7A:00:73 | ☑ |
| 192.168.1.74 | `wazuh.kairos.lab` | `dso-siem` | 00:15:5D:7A:00:74 | ☑ |
| 192.168.1.75 | `staging.kairos.lab` | `dso-staging` | 00:15:5D:7A:00:75 | ☑ |
| 192.168.1.76 | `prod.kairos.lab` | `dso-prod` | 00:15:5D:7A:00:76 | ☑ |

**DHCP pool** of the router: 192.168.1.11–192.168.1.253 (lease 1440 minutes). Every address above sits inside the pool and is held by its reservation, so the router never leases it to another device; the Legion's static setting matches its reservation. The router's other reservations use none of these addresses.

**Checks before creating the reservations (WP0.2):** .70–.76 answered no `ping` and were absent from `arp -a` on the Legion; the router's client list (every page) showed none of .30 or .70–.76 — 2026-11-04. Reservations created and checked on the router's page — 2026-11-04.
