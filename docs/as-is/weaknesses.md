# Weakness analysis (as-is)

Everything here was read from the files of this repository and from the lab as WP2.2 left it; the measured numbers are in [`measurements.md`](measurements.md). Application flaws (SV-01 to SV-09) are in [`../../security/seeded-vulns.md`](../../security/seeded-vulns.md); this table covers the pipeline, the platform and the hosts, and points to the SV rows where the two meet. Each weakness has an ID (W-nn) and the work package that closes it; WP8.1 re-checks them all.

## Table

| ID | Weakness (what the as-is flow does) | Brief's category | OWASP CI/CD risk | Seen in | Planned control | WP |
|---|---|---|---|---|---|---|
| W-01 | No scan of any kind: the pipeline has seven stages and none looks for secrets, vulnerable code, vulnerable dependencies, misconfigured files or vulnerable images; the tests only prove that the application works | No scan of any kind | CICD-SEC-1 | `ci/as-is/Jenkinsfile` | Eight control scripts as stages, first in report mode, then enforced with the gates of plan section 4.2; the same checks on the workstation (hooks) | P3, WP4.2, WP4.5 |
| W-02 | Secrets in clear: the token signing key is in `backend/app/config.py`, `deploy/.env` is committed with the database password, the Dockerfile sets `ADMIN_API_KEY` in the image (all fake values, SV-01 and SV-09) | Secrets in clear | CICD-SEC-6 | `config.py`, `deploy/.env`, `backend/Dockerfile` | Gitleaks in the hook and in CI, secrets read from `*_FILE` paths, OpenBao at deploy time, fake values rotated anyway | P3, WP4.2, WP4.5, WP5.3 |
| W-03 | Dependencies are not verified: the lockfiles are honoured, but nothing audits them (SV-07), `npm ci` runs install scripts, no registry signature is checked, and `pip install uv` takes the newest uv on every run | Unverified dependencies | CICD-SEC-3 | Stages 2, 3 and 4; both Dockerfiles | Trivy on the lockfiles, `npm ci --ignore-scripts`, `npm audit signatures`, the 7-day rule, Dependabot with a cooldown | WP4.2, WP4.5, WP4.6 |
| W-04 | Images are neither scanned nor pinned: `python:latest` and `node:latest` as bases, the images run as root, the web tier is the Vite dev server, the produced images carry the mutable tag `:latest` (SV-09) | Unscanned images | CICD-SEC-9 | `backend/Dockerfile`, `frontend/Dockerfile`, stage 4 | Bases and tools by digest, Hadolint, Trivy config and image, hardened containers, digest-only deploys | WP4.2, WP4.5, WP5.2 |
| W-05 | Flow control: nothing builds a pull request, no check is required before a merge, and the production stage needs only a ticked box: any logged-in Jenkins user can tick it, and nobody approves | — | CICD-SEC-1 | Job configuration, `Jenkinsfile` (`DEPLOY_PRODUCTION`) | Pull-request builds from origin only, the Jenkins check required by the ruleset, production behind an approval by `release-manager` | WP4.1, WP4.6, WP6.1 |
| W-06 | Jenkins as the wizard left it: every logged-in user can do anything (including the script console), the two credentials have the global scope so any job can use them, the markup formatter and the agent settings are the defaults | — | CICD-SEC-2, CICD-SEC-7 | `measurements.md`; screenshot `wp2.3-as-is-jenkins-security.png` | Matrix Authorization with named roles, scoped credentials, hardened configuration, Audit Trail | WP4.1 |
| W-07 | Poisoned pipeline: the Jenkinsfile is read from the branches the job watches and runs with the Docker Hub token and the deploy password bound for the whole pipeline, not stage by stage; whoever can change that file on a watched branch can make the pipeline send both anywhere | — | CICD-SEC-4 | `Jenkinsfile` (`environment { credentials() }`) | Credentials bound inside the stage that needs them and only on `main`; pull requests from origin only, never from forks; the Jenkinsfile reaches `main` through the ruleset | WP4.1, WP4.2 |
| W-08 | One agent does everything: the build agent runs untrusted dependency code, holds the registry write token and the deploy password, and its account is in the `docker` group (root-equivalent) | — | CICD-SEC-5 | Stages 2 to 7, `dso-agent` | Separate build and deploy agents (D-05); keys only in the deploy stage; Docker for tools only through the wrapper with dropped privileges | WP4.2, WP5.3 |
| W-09 | Credential hygiene: the Docker Hub token and the deploy password are pasted into command lines by Groovy interpolation (Jenkins warns), so they appear in the process list of the agent while a command runs; the password is a password | Secrets in clear | CICD-SEC-6 | Stages 5 to 7 (SV-10) | Secrets from OpenBao in the stage that uses them, single-quoted `sh`, tokens through stdin, per-environment SSH keys, the as-is token revoked | WP4.1, WP5.3 |
| W-10 | Host keys are not checked (`StrictHostKeyChecking=no`, `UserKnownHostsFile=/dev/null`): a machine answering for `staging.kairos.lab` receives the deploy password and the Compose file | — | CICD-SEC-5 | `deployTo()` in the `Jenkinsfile` | `known_hosts` filled by Ansible, keys instead of passwords, forced commands | WP5.3, WP6.1 |
| W-11 | Artifact integrity and recovery: whatever sits behind `:latest` on Docker Hub is what the hosts run; nothing is signed or verified; no smoke test follows a deploy and there is no rollback, so a broken deploy ends green | Unscanned images | CICD-SEC-9 | Stages 5 to 7 | Digest-only deploys, cosign signatures verified on the host, smoke tests, rollback | WP5.2, WP5.3, WP6.1 |
| W-12 | Third-party services without governance: a Read & Write Docker Hub token that works for every repository of the account, created for this job and not recorded anywhere but Jenkins. The token is also left unencrypted in `.docker/config.json` on the build agent (ASIS-01, T-10) | — | CICD-SEC-8 | `dockerhub-rw-as-is` | Revoked once the as-is job stops polling; tokens scoped and listed in `docs/runbooks/accounts.md` | WP4.1 |
| W-13 | Logging and visibility: only the console of each build and the system log; nothing records who changed a job, a credential or a setting, who approved a deploy or what ran on the hosts | — | CICD-SEC-10 | Jenkins controller, hosts | Audit Trail to a file, approver recorded by `input`, deploy logs and OpenBao's audit log into Wazuh, Slack alerts | WP4.1, WP4.3, WP6.2 |
| W-14 | The runtime hosts as an installer leaves them plus the as-is practices: the `deploy` account with a password and `PasswordAuthentication yes`, no firewall, ports 22, 5173 and 8000 open on every interface, plain HTTP, default sysctls, no auditd (SV-08, SV-11); Wazuh SCA starts at 47 % | Host and network | CICD-SEC-7 | `infra/ansible/roles/as-is`, `deploy/compose.yaml`, Wazuh SCA | Lynis and SCA before and after, the hardening role, key-only SSH, UFW and `DOCKER-USER` allow-lists, TLS | WP5.3, WP7.1 |

## Coverage of the OWASP Top 10 CI/CD Security Risks

Plan section 8.1 asks that all ten are addressed. Each has at least one weakness above, and the to-be control is in the plan's table.

| Risk | Weaknesses |
|---|---|
| CICD-SEC-1 Insufficient Flow Control | W-01, W-05 |
| CICD-SEC-2 Inadequate Identity and Access Management | W-06 |
| CICD-SEC-3 Dependency Chain Abuse | W-03 |
| CICD-SEC-4 Poisoned Pipeline Execution | W-07 |
| CICD-SEC-5 Insufficient Pipeline-Based Access Controls | W-08, W-10 |
| CICD-SEC-6 Insufficient Credential Hygiene | W-02, W-09 |
| CICD-SEC-7 Insecure System Configuration | W-06, W-14 |
| CICD-SEC-8 Ungoverned Usage of Third-Party Services | W-12 |
| CICD-SEC-9 Improper Artifact Integrity Validation | W-04, W-11 |
| CICD-SEC-10 Insufficient Logging and Visibility | W-13 |

## The brief's four categories

| Category | Weaknesses | In one sentence |
|---|---|---|
| No scan of any kind | W-01 | The pipeline can build and ship a leaked secret, an injectable query and a vulnerable package without a single warning |
| Secrets in clear | W-02, W-09 | Secrets are in the source, in the image, in `deploy/.env` and in command lines |
| Unverified dependencies | W-03 | The lockfiles are used but never audited, and install scripts run |
| Unscanned images | W-04, W-11 | The images are built, pushed and deployed on trust |

## What this table does not claim

- Counts of findings are not here: they come from the first report-mode run of the scanners on this same code (WP4.2, `baseline-scorecard.md`), DAST results from WP5.1, and host scores from Wazuh SCA (WP1.6) and Lynis (WP7.1).
- Weaknesses W-05 to W-13 are properties of the design of the pipeline and the platform. No scanner covers them (plan SV-10), so the check is a review against the OWASP list, which is what this file is.
