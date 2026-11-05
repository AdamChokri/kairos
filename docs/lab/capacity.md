# Lab capacity and reachability

Plan WP0.2 and section 3.1, with E-10 and decision D-22. The Legion's figures were recorded when the plan was written and are not measured again (CAP-02 below says when they are completed).

## Hosts

Measured on 2026-11-04 with `infra/lab/host-report.sh optiplex`, the host's other VMs Off.

| | Legion 5 Pro (192.168.1.30) | OptiPlex 5090 (192.168.1.34) |
|---|---|---|
| RAM available with your usual load | 19 GB (recorded) | 28,657 MB (≈ 28.0 GB) of 31.7 GB installed |
| Free space on the VHDX volume | about 200 GB (recorded) | C: 94.4 GB free of 237.4 GB |
| Room the existing dynamic VHDX files can still take on that volume | not recorded (CAP-02) | 51.1 GB (`worker-1` 19.5 of 60 GB max, `worker-2` 31.7 of 80 GB max) |
| External switch | `External` (Realtek NIC) | `External` (Intel Ethernet Connection (14) I219-LM) |
| Other VMs (kept Off during lab sessions) | `control-plane`, `gitea`, `harbor`, `openbao` | `worker-1` (10 GB), `worker-2` (12 GB) |
| Project folder | `D:\Projects\Kairos` | `C:\Projects\Kairos` |

## Capacity rules (section 3.1) applied

| Rule | Legion | OptiPlex |
|---|---|---|
| Lab VM memory (from `vms.csv`) | 10 GB | 14 GB |
| RAM left with the lab running (≥ 4 GB) | 9 GB | ≈ 14 GB |
| Lab VHDX maxima (from `vms.csv`) | 90 GB | 105 GB |
| Ceiling: free − existing growth room − 25 GB (E-10) | 175 GB (recorded before E-10; growth room in CAP-02) | 94.4 − 51.1 − 25 = **18.3 GB** |
| Verdict | fits | memory fits; disk below the ceiling — **kept as planned by D-22**, under the guards below. `vms.csv` unchanged |

## Guards (D-22)

| ID | What | When | Action | Closes when |
|---|---|---|---|---|
| CAP-01 | `infra/lab/host-report.sh optiplex`, C: free recorded in the log below | At the start of every phase | C: below 25 GB free → move `dso-sonar` to the Legion through `infra/lab/vms.csv` (Legion: 14 GB of VMs, 5 GB left; 110 of 175 GB) — **not possible on RAM since CAP-03 (2026-11-05)**: the action is decided again when C: reaches 25 GB | `worker-1` and `worker-2` are gone and the ceiling is measured above 105 GB |
| CAP-02 | `infra/lab/host-report.sh legion`: the growth room of the Legion's own VMs | Before any CAP-01 move | Check the move against the full E-10 rule on the Legion | Measured once |
| CAP-03 | Legion RAM with the lab running: 12,741 MB available at start, 2,501 MB left once the lab runs (plan: 4,096); the largest listed processes are `brave`, `Discord` and the NVIDIA overlays, `vmmemWSL` 0.5 GB | `make lab-up` warning, 2026-11-05 | None: the four Legion VMs hold 10 GB at their full assigned size, so this is their steady state. The OptiPlex has about 15 GB of RAM to spare (29,357 MB available, 14,336 MB needed), so a VM can move there through `vms.csv` if needed | Closed by the owner, 2026-11-05 |

**CAP-01 log**

| Date | Phase | C: free (GB) | Existing growth room (GB) | Action |
|---|---|---|---|---|
| 2026-11-04 | P0 (WP0.2) | 94.4 | 51.1 | none (baseline) |

## Reachability

Output of `infra/lab/reachability.sh` (paste the table it prints).

### At home — 2026-11-04

Reachability from DESKTOP-T6I977T on 2026-11-04T17:24Z

| Endpoint | Purpose | Result |
|---|---|---|
| `archive.ubuntu.com` | Ubuntu packages (apt, port 80) | reachable (HTTP 206) |
| `security.ubuntu.com` | Ubuntu security updates (apt, port 80) | reachable (HTTP 206) |
| `download.docker.com` | Docker Engine packages | reachable (HTTP 206) |
| `registry-1.docker.io` | Docker Hub registry | reachable (HTTP 401) |
| `auth.docker.io` | Docker Hub token service | reachable (HTTP 200) |
| `production.cloudflare.docker.com` | Docker Hub image layers | reachable (HTTP 403) |
| `ghcr.io` | GitHub container registry | reachable (HTTP 401) |
| `quay.io` | Quay registry | reachable (HTTP 401) |
| `mirror.gcr.io` | Google registry mirror | reachable (HTTP 401) |
| `pypi.org` | PyPI index | reachable (HTTP 206) |
| `files.pythonhosted.org` | PyPI files | reachable (HTTP 404) |
| `registry.npmjs.org` | npm registry | reachable (HTTP 200) |
| `github.com` | GitHub | reachable (HTTP 206) |
| `api.github.com` | GitHub API | reachable (HTTP 206) |
| `updates.jenkins.io` | Jenkins update center | reachable (HTTP 206) |
| `get.jenkins.io` | Jenkins downloads | reachable (HTTP 206) |
| `packages.wazuh.com` | Wazuh packages | reachable (HTTP 403) |
| `semgrep.dev` | Semgrep rules registry | reachable (HTTP 206) |
| `rekor.sigstore.dev` | Sigstore transparency log | reachable (HTTP 200) |
| `tuf-repo-cdn.sigstore.dev` | Sigstore trust root (TUF) | reachable (HTTP 206) |
| `fulcio.sigstore.dev` | Sigstore certificate authority | reachable (HTTP 404) |
| `slack.com` | Slack | reachable (HTTP 200) |
| `hooks.slack.com` | Slack incoming webhooks | reachable (HTTP 302) |
| `www.cisa.gov` | CISA KEV feed | reachable (HTTP 200) |
| `api.deepseek.com` | DeepSeek API | reachable (HTTP 401) |
| `keyserver.ubuntu.com` | Ubuntu key server (ISO signature) | reachable (HTTP 206) |
| `releases.ubuntu.com` | Ubuntu ISO downloads | reachable (HTTP 200) |
| `release-assets.githubusercontent.com` | GitHub release files (followed a real download) | reachable (HTTP 200) |

0 endpoint(s) failed.

### At school — _date_ (before the first in-class session, plan section 14)

_table_

### Recorded alternatives

| Endpoint | Status | Alternative / why it does not matter |
|---|---|---|
| — | Every endpoint was reachable at home on 2026-11-04, `quay.io` included | None needed |
