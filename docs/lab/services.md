# Lab services

What runs in the lab, where, at which version, and the facts later work packages need. Filled in P1; update a row with the pull request that changes it.

| Service | URL / address | VM | Version (pinned in) | Notes |
|---|---|---|---|---|
| OpenBao | `https://openbao.kairos.lab:8200` | `dso-bao` | 2.7.2 (`infra/ansible/group_vars/all/versions.yml`) | Raft, TLS from the lab CA, audit `/var/log/openbao/audit.log`; 3 shares, threshold 2 |
| Jenkins controller | `http://jenkins.kairos.lab:8080/` | `dso-jenkins` | 2.580.2 LTS, `lts-jdk21` by digest (`ci/jenkins/Dockerfile`); plugins pinned (`ci/jenkins/plugins.txt`) | Built-in node: 0 executors; only port 8080 published. Agents over WebSocket (`agent.jar -webSocket`, E-27): `build-agent` on `dso-agent` (user `jagent`, in `docker`; label `build`, 2 executors), `deploy-agent` on `dso-jenkins` (user `jdeploy`, no Docker access; label `deploy`, 1 executor). GitHub App credential `github-app` |
| SonarQube Community Build | `http://sonar.kairos.lab:9000` | `dso-sonar` | 26.10.0.133078-community with PostgreSQL 17, both by digest (`infra/ansible/group_vars/all/images.yml`) | Mode: **MQR** (Multi-Quality Rule); project `kairos` (display name Kairos), main branch `main`; gate "Kairos Secure" assigned to it (*Sonar way* stays the instance default); new code: **Previous version**, set on the project, with `SONAR_PROJECT_VERSION=0.2.0` held in `security/policy/gates.env` (D-32). First analysis 2026-11-05 with `sonar-scanner-cli:12.3.0.4285_8.1.0` (`sha256:47956b669bf486bdad919e1cbd0533223515aa0b6d1d31763e5a3754942df6d7`): gate Passed |
| Wazuh | `https://wazuh.kairos.lab` | `dso-siem` | 4.14.9: manager, indexer and dashboard by digest, certificate generator 0.0.4 (`infra/ansible/group_vars/all/images.yml`, `versions.yml`) | Single node. Agents 4.14.9 on `dso-bao`, `dso-staging`, `dso-prod` (all Active, enrolled with a password); Slack from level 10 (rule 5712 alert on `dso-staging` seen in `#kairos-secops`, 2026-11-05); retention 14 days; no active response until P7. Secrets in OpenBao `kv/infra/wazuh` |
| Kairos v0 staging (as-is) | `http://staging.kairos.lab:8000` (API), `:5173` (web) | `dso-staging` | PostgreSQL 17, `adamchokri22/kairos-api:latest` and `adamchokri22/kairos-web:latest` (mutable tags: as-is) | Deployed by `kairos-as-is`; `deploy` account with a password (SV-11) |
| Kairos v0 production (as-is) | `http://prod.kairos.lab:8000`, `:5173` | `dso-prod` | the same | Only when the job's `DEPLOY_PRODUCTION` box is ticked |
| Jenkins job `kairos-as-is` | `http://jenkins.kairos.lab:8080/job/kairos-as-is/` | `dso-jenkins` (builds on `dso-agent`) | Multibranch Pipeline of `ci/as-is/Jenkinsfile`, periodic scan every 5 minutes (E-31) | Kept for WP8.1; the periodic scan is switched off in WP4.1 |

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

**NC-01 (closed by D-32):** the new-code period is *Previous version*; the version sent by the scanner is `0.2.0` and does not change. Reason and alternatives: `docs/decisions.md`.

## Wazuh SCA baseline (the "before" of WP7.1)

| Host | Policy | Score | Passed / failed / not applicable | Date |
|---|---|---|---|---|
| `dso-staging` | CIS Ubuntu Linux 24.04 LTS Benchmark v1.0.0 | 47 % | 111 / 125 / 43 | 2026-11-05 |
| `dso-prod` | CIS Ubuntu Linux 24.04 LTS Benchmark v1.0.0 | 47 % | 111 / 125 / 43 | 2026-11-05 |

Screenshots of both baselines: `docs/evidence/EV-22-sca-before-dso-staging.png` and `EV-22-sca-before-dso-prod.png`. The two hosts score the same because they come from the same golden image and the same Ansible plays; the score is passed / (passed + failed).

## Pending updates (D-12: a new tool version waits 7 days, then arrives in its own pull request)

| ID | What | Since | Action |
|---|---|---|---|
| UPD-01 | testssl.sh v3.2.5 (pinned: v3.2.4, E-03) | tagged 2026-11-04, eligible from 2026-11-11 | Its own pull request: new tag and commit in `versions.yml`, rerun `--tags jenkins-agents` |
| UPD-02 | `wazuh-certs-generator` 0.0.5 (pinned: 0.0.4, which Wazuh's own `v4.14.9` files use) | published 2026-10-29 | With the next Wazuh update, when its files reference it |
| UPD-03 | Wazuh manager and indexer: the `4.14.9` tags were republished on 2026-11-03, two days before the first pin (2026-11-05); version unchanged, contents rebuilt, with no published reason found. Pinned: manager `sha256:9d07740f…02a2`, indexer `sha256:08a8d5a0…c98c` (dashboard unchanged since 2026-10-16) | 2026-11-05 | At the next Wazuh update, compare the new digests with these and read the release notes |
| NODE-01 | `node:26.13.0-slim`: the tag was republished on 2026-11-05; pinned `sha256:e4db4c91…a02c39` kept (D-30) | 2026-11-05 | From 2026-11-12, after reading what changed: its own pull request with the new digest in `ci/tools/node-image.txt`; pairs with WP4.6 |
| DEP-01 | Moderate advisory GHSA-g3hv-75wg-m249 (minimatch) in the typescript-eslint chain of the frontend lockfile, found by npm audit of the lockfile and confirmed by Dependabot alert #33 | 2026-11-06 | Re-read at WP4.5; close it when a release of `typescript-eslint` depends on minimatch 11.0.1 or later |
| UPD-05 | Trivy 0.76.2 (pinned: 0.76.1) | published 2026-11-05, eligible from 2026-11-12 | Its own pull request: the version and the hashes pinned in `ci/tools/install-scan-tools.sh` and `hook-trivy.sh`, then `make hooks-selftest` |
| UPD-04 | ESLint 10.14.0 (pinned: 9.39.5, the registry's `maintenance` line, which `npm ci` now flags `deprecated: This version is no longer supported`): `eslint-plugin-react` 7.37.5, which provides `react/no-danger` (SV-03), declares support for ESLint up to 9 only | 2026-11-05 | Its own pull request when `npm view eslint-plugin-react peerDependencies` allows ESLint 10; rerun `ci/tools/frontend-deps.sh` and the hooks |
