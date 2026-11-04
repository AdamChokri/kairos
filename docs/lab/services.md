# Lab services

What runs in the lab, where, at which version, and the facts later work packages need. Filled in P1; update a row with the pull request that changes it.

| Service | URL / address | VM | Version (pinned in) | Notes |
|---|---|---|---|---|
| OpenBao | `https://openbao.kairos.lab:8200` | `dso-bao` | _2.7.x_ (`infra/ansible/group_vars/all/versions.yml`) | Raft, TLS from the lab CA, audit `/var/log/openbao/audit.log`; 3 shares, threshold 2 |
| Jenkins controller | `http://jenkins.kairos.lab:8080/` | `dso-jenkins` | _LTS version_ (`ci/jenkins/Dockerfile`) | Built-in node: 0 executors; agents `build-agent` (label `build`, 2 executors), `deploy-agent` (label `deploy`, 1 executor) over WebSocket |
| SonarQube Community Build | `http://sonar.kairos.lab:9000` | `dso-sonar` | _version_ (`images.yml`) | Mode: _Standard Experience / MQR_; project `kairos`; gate "Kairos Secure" |
| Wazuh | `https://wazuh.kairos.lab` | `dso-siem` | _4.14.x_ (`versions.yml`, `images.yml`) | Agents: `dso-bao`, `dso-staging`, `dso-prod`; Slack from level 10; retention 14 days |

## SonarQube quality gate "Kairos Secure" (plan section 4.2)

Mode: _Standard Experience / MQR_ — condition names as the server shows them:

| Condition (on new code) | Operator and value |
|---|---|
| _no new vulnerabilities_ | |
| _Security Hotspots reviewed_ | |
| _Reliability rating_ | |
| _Coverage_ | |
| _Duplicated lines (%)_ | |

## Wazuh SCA baseline (the "before" of WP7.1)

| Host | Policy | Score | Passed / failed / not applicable | Date |
|---|---|---|---|---|
| `dso-staging` | CIS Ubuntu Linux 24.04 LTS Benchmark | | | |
| `dso-prod` | CIS Ubuntu Linux 24.04 LTS Benchmark | | | |
