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
| ENF-02 | `MODE_IMAGE` is still `report`: 22 base-image findings (BASE-PY, BASE-WEB) block the image gate, and they can be neither fixed nor excepted yet (the KEV-listed and Critical ones are never excepted) | 2026-11-11 | Closed in the pull request that moves the last of the two base-image pins: `MODE_IMAGE=enforce` and this row removed. At the latest before 5.4.5, whose check expects all seven modes to read `enforce` |
| BASE-PY | api image, `python:3.13.18-slim-trixie`: 9 blocking findings, all with a fixed version: Debian `apt` and `libapt-pkg7.0` (CVE-2026-109518), `zlib1g` (CVE-2026-76844, CVE-2026-85091), `msgpack` and `urllib3` (pip's vendored copies in the base image), and `setuptools` 70.3.0 (CVE-2025-47273; not in the base image, origin not found yet). The tag was re-pushed on 2026-11-08 | 2026-11-11 | Actionable 2026-11-15 (D-12): `bash ci/tools/pin-tools.sh python` and the `FROM` digests of `backend/Dockerfile`, in their own pull request; read its `docker_scan`; if `setuptools` is still listed, find where it comes from in the built image |
| BASE-WEB | web image, `nginxinc/nginx-unprivileged:1.30.6-alpine3.24`: 13 blocking findings, all with a fixed version in Alpine's repository: `brotli-libs` CVE-2026-111497 (Critical, in the CISA KEV catalog), `libxslt` (one row in KEV), `libexpat` x4, `musl`, `curl`, `zlib`. The 30 `alpine3.24` tags of the repository listed on 2026-11-11 all date from 2026-10-19 and hold the old packages | 2026-11-11 | Actionable when `bash ci/tools/pin-tools.sh --check nginx` prints `DIFFERENT` and the tag is at least 7 days old: `pin-tools.sh nginx` and the `FROM` digest of `frontend/Dockerfile`, in their own pull request. First look on 2026-11-15. The KEV rows are never excepted |
| REL-01 | SonarQube `typescript:S9383` (reliability): the call that starts the debounced search must stay marked `void`. Fixed in `TaskList.tsx` with `frontend/src/search.test.tsx`; the assistant panel and the workspace screens of later phases call the same function | 2026-11-11 | In any pull request that adds or replaces `TaskList.tsx` or `Workspace.tsx`, keep `void searchLater(...)`: the gate "Kairos Secure" fails on `main` otherwise. Closed when the last of those screens is merged with it |
| UPD-06 | SonarQube Community Build: the server's page offers a newer build than 26.10 (version and date not read yet) | 2026-11-11 | Read the version and its release date; from 7 days after it, its own pull request (D-12) and the gate of 4.5.6 again |
| AST-01 | No DeepSeek key was created (4.7.8 not run): Assist is tested with a stub, and its live call to the model has never been made | 2026-11-12 | Create kv/kairos/staging/llm and try one live call when a runtime host exists |
| AST-02 | Kairos Assist in production: no production host was built | 2026-11-12 | With the production host |
| DUP-01 | The first run of dependabot.yml opened 7 version-update PRs (2 base images, 3 ESLint and TypeScript majors, a uv group, an npm group); none is merged. The image PRs move a pin without tools.lock (the route is pin-tools.sh, BASE-PY and BASE-WEB), the majors are a task of their own, and the uv group's lockfile is replaced by the Assist folder | 2026-11-11 | Triage once: ignore the image and major PRs with a Dependabot ignore comment, merge the two groups if green |
| SCP-01 | P5 was not run: the DAST script and its "before" measurements (5.1), the SBOM, publication and signature of the images (5.2), signed-only staging with the runtime secrets read from OpenBao (5.3), the dynamic fixes and DAST in enforce mode (5.4). The delivery stages of the Jenkinsfile (sbom, publish, sign, deploy_staging, dast) stay stubs: no image of the new Kairos is published, signed or deployed, and the dynamic scan never ran | 2026-11-12 | The steps of P5, in their order, when a runtime release is worth building |
| SCP-02 | Three seeded weaknesses stay open: SV-06 (one logged-in user reads, changes and deletes another's task: `get_task` in `backend/app/routers/tasks.py`, and the comment routes), SV-08 (stack traces in 500 answers, CORS `*` with credentials, no security headers, plain HTTP) and SV-11 (the runtime hosts accept password logins for the deploy account, no firewall, default sysctls). Each is described, with its check, in `security/seeded-vulns.md`; the "before" of SV-11 is the Wazuh SCA baseline above (47 %) | 2026-11-12 | SV-06 and SV-08 with SCP-01 (WP5.4), SV-11 with SCP-04 (WP7.1), each with its regression test written first |
| SCP-03 | P6 was not run: the production host with signed-only deploys and the approval (6.1, 6.2), the rollback drills (6.3, 6.6), the Slack rules of Kairos's own (6.4) and the release of the designed interface to staging and production (6.5.5). The interface (UI-01, D-40) is on `main` and runs locally with `make dev-up`; the lab's production host still runs the as-is application | 2026-11-12 | The steps of P6, after SCP-01; AST-02 (Assist in production) closes with them |
| SCP-04 | P7 was not run: the hardening of both runtime hosts and its "after" measurement (7.1), the penetration test (7.2), the incident drills of the edited deploy command (7.3, IR-2) and of a secret in a pull request (7.5, IR-1), and the second production release (7.4). What exists is the "before": the Wazuh SCA baseline of both hosts above | 2026-11-12 | The steps of P7, after SCP-03 |
| SCP-05 | P8 was not run: the final measurement of the pipeline (8.2), the detection matrix (8.3), the report built from P8's templates (8.4), the slides (8.5), the signed tag and the fresh clone (8.6), the demonstration and its rehearsal (8.7), and DEM-01 (the new pipeline run on the as-is code, 8.2.6). The report is written from the repository's records, with the baseline and the builds as they are | 2026-11-12 | The steps of P8, after SCP-04 |
