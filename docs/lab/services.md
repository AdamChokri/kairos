# Lab services

What runs in the lab, where, at which version, and the facts later work packages need. Filled in P1; update a row with the pull request that changes it.

| Service | URL / address | VM | Version (pinned in) | Notes |
|---|---|---|---|---|
| OpenBao | `https://openbao.kairos.lab:8200` | `dso-bao` | 2.7.2 (`infra/ansible/group_vars/all/versions.yml`) | Raft, TLS from the lab CA, audit `/var/log/openbao/audit.log`; 3 shares, threshold 2 |
| Jenkins controller | `http://jenkins.kairos.lab:8080/` | `dso-jenkins` | 2.580.2 LTS, `lts-jdk21` by digest (`ci/jenkins/Dockerfile`); plugins pinned (`ci/jenkins/plugins.txt`) | Built-in node: 0 executors; only port 8080 published. Agents over WebSocket (`agent.jar -webSocket`, E-27): `build-agent` on `dso-agent` (user `jagent`, in `docker`; label `build`, 2 executors), `deploy-agent` on `dso-jenkins` (user `jdeploy`, no Docker access; label `deploy`, 1 executor). GitHub App credential `github-app` |
| SonarQube Community Build | `http://sonar.kairos.lab:9000` | `dso-sonar` | 26.10.0.133078-community with PostgreSQL 17, both by digest (`infra/ansible/group_vars/all/images.yml`) | Mode: **MQR** (Multi-Quality Rule); project `kairos` (display name Kairos), main branch `main`; gate "Kairos Secure" assigned to it (*Sonar way* stays the instance default); new code follows the instance default (previous version) until WP4.2 (NC-01 below). First analysis 2026-11-05 with `sonar-scanner-cli:12.3.0.4285_8.1.0` (`sha256:47956b669bf486bdad919e1cbd0533223515aa0b6d1d31763e5a3754942df6d7`): gate Passed |
| Wazuh | `https://wazuh.kairos.lab` | `dso-siem` | _4.14.x_ (`versions.yml`, `images.yml`) | Agents: `dso-bao`, `dso-staging`, `dso-prod`; Slack from level 10; retention 14 days |

## SonarQube quality gate "Kairos Secure" (plan section 4.2)

Mode: **MQR** — condition names as the server shows them:

| Condition (on new code) | Operator and value |
|---|---|
| Security Issues | is greater than 0 |
| Security Hotspots Reviewed | is less than 100 % |
| Reliability Rating | is worse than A |
| Coverage | is less than 60.0 % |
| Duplicated Lines (%) | is greater than 3.0 % |

In MQR mode the plan's "no new vulnerabilities" is the condition **Security Issues**; the metric named plain **Issues** counts issues of every kind (it is the one *Sonar way* uses) and is not part of this gate.

**NC-01 (tracked):** the plan starts the new-code period at the baseline analysis of WP4.2, but the Community Build 26.10 offers only *Previous version*, *Number of days* and *Reference branch* for a project. At WP4.2 the choice is made and recorded as a decision (`docs/decisions.md`); until then the project follows the instance default.

## Wazuh SCA baseline (the "before" of WP7.1)

| Host | Policy | Score | Passed / failed / not applicable | Date |
|---|---|---|---|---|
| `dso-staging` | CIS Ubuntu Linux 24.04 LTS Benchmark | | | |
| `dso-prod` | CIS Ubuntu Linux 24.04 LTS Benchmark | | | |
