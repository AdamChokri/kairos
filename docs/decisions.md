# Decision log

The decisions the project starts from: D-01 to D-20 of the project plan (`docs/plan/PROJECT-PLAN.md`, section 2), recorded on 2026-11-01 at bootstrap.

**How this file changes.** An entry is never edited. A decision changes only through a new dated entry at the end, which names the entry it supersedes, says why, and links the pull request — so the history of every choice stays readable. Corrections to the plan's facts (versions, names) go to `docs/plan/ERRATA.md` instead.

Template for a new entry:

```markdown
🧭 **D-NN — <decision>** · 2026-MM-DD · supersedes D-XX (or "new")
*Why:* <the reason, with the evidence>.
*Alternative:* <what was considered and why not>.
*Pull request:* #<number>
```

---

🧭 **D-01 — CI/CD engine: Jenkins with a declarative `Jenkinsfile` and a Multibranch Pipeline.**
*Why:* the brief names the Jenkinsfile; ESPRIT's DevOps module and your experience are Jenkins; Warnings NG gives free per-tool trend charts; hardening Jenkins itself is DevSecOps content (§8).
*Alternative:* GitLab CI — its security dashboards are Ultimate-tier, and hosting would move to GitLab.

🧭 **D-02 — Code hosting: the public GitHub repository `AdamChokri/kairos` (Apache-2.0), protected by a ruleset on `main`.**
*Ruleset:* pull request required (approvals 0, D-18), squash merge only, required Jenkins status check (added in WP4.6), linear history, signed commits, no force push or deletion. Secret scanning with push protection, Dependabot alerts and security updates, and private vulnerability reporting are on.
*Why public:* free rulesets, push protection and Dependabot, easy access for the jury.
*Consequence:* only fake seeded secrets ever enter the repository; pull requests from forks are never built.

🧭 **D-03 — Application: Kairos, kept deliberately small — FastAPI on Python 3.13, React 19 + TypeScript (Vite), PostgreSQL 17.**
*Scope:* register and log in (JWT), tasks with search, comments, YAML import, health and version endpoints — nothing else. Every feature carries a seeded weakness or a control.
*Why:* it exercises every local tool the brief names (Bandit, ESLint security rules, Semgrep, SonarQube for IDE) and FastAPI publishes the OpenAPI document that authenticated DAST needs.

🧭 **D-04 — Lab: seven Ubuntu 24.04 VMs on two Hyper-V hosts on one portable LAN — your router and switch — on their existing External switches.**
*Why:* OpenBao and SonarQube bring the lab to 24 GB of VM memory, more than the Legion's 19 GB available; the Legion and the OptiPlex already share 192.168.1.0/24, so bridged VMs talk directly — no overlay, tunnel or routing to build, and nothing changes in either host's network setup.
*Placement:* the CI tier on the OptiPlex (`dso-jenkins`, `dso-agent`, `dso-sonar`, 14 GB); secrets, monitoring and the runtime tier on the Legion (`dso-bao`, `dso-siem`, `dso-staging`, `dso-prod`, 10 GB), which leaves 9 GB for your own work.
*Addresses:* each VM has a fixed MAC (`00:15:5D:7A:00:70`–`76`) and a router reservation (.70–.76); cloud-init asks with `dhcp-identifier: mac` so the router recognises it.
*Consequence:* the lab runs wherever its LAN goes — router, switch, cables and both hosts travel together, the Legion on wired Ethernet — so in-class sessions and the defense are live; the router's internet uplink is the one thing a venue must provide (R-08).
*Alternative:* plan v1's Tailscale overlay — the lab reachable from anywhere while it stays at home, about 10 h more.

🧭 **D-05 — Agents: builds run on `dso-agent`; signing and deployment run on a deploy agent on `dso-jenkins`, which has no Docker.**
*Why:* membership of the `docker` group is root-equivalent, so the machine that executes untrusted build code (dependencies, scanners) must hold neither `JENKINS_HOME` nor any signing or deploy credential; it cannot even reach OpenBao (D-07).
💡 **The VM that runs pull-request code never holds a credential that can sign an image or deploy it — and pull-request builds receive no secret at all.**

🧭 **D-06 — Triggers: Jenkins polls GitHub (Multibranch scan every 2 minutes); there is no inbound webhook.**
*Why:* nothing in the lab is exposed to the internet; pushes and pull requests still build within minutes, and commit statuses go back to GitHub outbound.
*Alternative:* a webhook through a tunnel — faster feedback, but an internet-facing route to secure.

🧭 **D-07 — Secrets: OpenBao is the single store for pipeline and runtime secrets.**
- **Server:** OpenBao 2.7 on `dso-bao` — single node, integrated Raft storage, TLS from the lab CA, file audit device shipped to Wazuh; port 8200 open only to the Legion, `dso-jenkins` and the two runtime hosts.
- **Pipeline:** Jenkins keeps only bootstrap identities — the GitHub App key, the Slack bot token (the Slack plugin reads Jenkins credentials only) and three AppRole credentials — `bao-build`, `bao-deploy` and `bao-signer`, for the AppRoles `jenkins-build`, `jenkins-deploy` and `jenkins-signer` — each bound to `dso-jenkins`'s address. `withVault` fetches a stage's secrets on the controller when that stage runs, and masks them in logs.
- **Runtime:** an OpenBao Agent on staging and production (AppRole bound to that host) renders the database password and JWT key into files the containers read through `*_FILE` paths.
- **Signing:** the cosign key is a non-exportable Transit key (D-14).
- **Operations:** Shamir unseal with 3 key shares and a threshold of 2, kept in your password manager; `make lab-up` asks for them (D-19); the root token is revoked after setup and you administer through a `userpass` account.
*Alternative:* Jenkins credentials and host-generated secrets (plan v2) — less to run, but no central audit, no rotation in one place and no key that cannot leave its store.

🧭 **D-08 — Registry: Docker Hub public repositories; images referenced by digest only.**
Every pull is authenticated with a *read-only* token kept in OpenBao and logged in by Ansible, through stdin, on the build agent and both runtime hosts: anonymous pulls share one per-IP limit with everyone behind the same NAT. The token can only read public images, so on a runtime host it exposes nothing but pull quota.

🧭 **D-09 — Code hub: a self-hosted SonarQube Community Build on `dso-sonar` (PostgreSQL 17), with the quality gate "Kairos Secure".**
*Scope:* Community Build analyzes a single branch, so SonarQube runs in the `main` lane: its gate blocks the release (publish, sign, deploy) and it keeps the history; pull requests are gated by Semgrep, Bandit and ESLint, which carry the blocking SAST rules anyway.
*Why self-hosted:* code and findings stay in the lab, and running the server is part of the work.
*Rejected:* the community branch plugin — it adds pull-request analysis by patching SonarQube with a Java agent, is unsupported by SonarSource and must match every SonarQube release, which a pinned toolchain cannot afford; a commercial edition — cost.

🧭 **D-10 — Toolchain: one well-tuned tool per job.**

| Job | Tool | Not used, and why |
|---|---|---|
| Secrets | Gitleaks | TruffleHog — overlaps ([PLUS] for verified-secret checks) |
| SAST | Semgrep CE (registry + custom rules), Bandit, ESLint security plugins on every pull request; SonarQube Community Build on `main` | CodeQL — a second deep engine the budget cannot absorb |
| SCA, image, Dockerfile configuration | Trivy (fs, image, config), with the CISA KEV catalog for exploitation-aware blocking | Grype, OWASP Dependency-Check — overlap; Snyk, Docker Scout — SaaS accounts |
| Dockerfile lint | Hadolint | — |
| SBOM | Syft (CycloneDX), signed and attached to each image with cosign | — |
| DAST | ZAP (baseline + API scan) | Nikto — legacy and noisy; Nuclei — overlap |
| Infrastructure as code beyond Dockerfiles | none in the core; Conftest for Compose is [PLUS] | Checkov (CVE-2026-0302), KICS (2026 distribution compromise), Terrascan (archived) |
| Secrets management | OpenBao | HashiCorp Vault — BSL licence; Jenkins credentials alone — no audit or Transit |
| Model behind Kairos Assist | DeepSeek `deepseek-flash` through its OpenAI-compatible API (D-20) | `deepseek-v4-pro` — pricier, with a lower concurrency limit, for a task this simple; a self-hosted model — a GPU service to run |
| Host | Wazuh (HIDS, FIM, SCA), Lynis | — |

💡 **The slides' "three well-tuned checks beat ten noisy ones" is applied literally. Trivy covers three jobs from one pinned, signature-verified tool — a conscious trade-off given its 2026 compromise, mitigated by D-12.**

🧭 **D-11 — Gates: thresholds and rollout modes in one policy file, `security/policy/gates.env`; fail-closed.**
Each control script runs its tool with the tool's own fail switch off, writes the full JSON/SARIF report, applies the threshold from `gates.env` and exits 0 (pass), 1 (blocked), 2 (would block, but the control is still in report mode) or any other code on a tool error. The Jenkinsfile turns 2 into a yellow stage and every other non-zero code into a red stage and a failed build, so a broken tool never passes.
💡 **Report → fix → enforce: every control lands reporting, the findings it reveals are fixed, and only then does it block — a new control never stalls on an untriaged backlog, and a fix is never stuck behind the very problem it fixes.**

🧭 **D-12 — Security tools are part of the supply chain.**
Every tool image is pinned by digest in `ci/tools/tools.lock`; vendor signatures are verified where published (Trivy images and the OpenBao package, keylessly); a denylist records known-compromised versions; every tool runs through `ci/scripts/run-tool.sh` (read-only source, non-root, no capabilities, memory limit, no network unless needed, never the Docker socket); tool updates arrive only through pull requests after a 7-day cooldown.
💡 **The 2026 Trivy, KICS and Checkov incidents make "the scanner is part of the supply chain" a concrete, citable lesson.**

🧭 **D-13 — Exemptions: a register with expiry, the tools' own suppression markers tied to an `EXC-` ID, and an automatic validator** (§4.3).

🧭 **D-14 — Delivery: images and their SBOMs signed with an OpenBao-held key, verified by the host through a forced-command deploy script, with automatic rollback.**
- The signing key is the Transit key `kairos-images` (ECDSA P-256, not exportable). The deploy agent's `sign` stage gets a short-lived token through the `jenkins-signer` AppRole and runs `cosign sign --key openbao://kairos-images`, then attaches each image's CycloneDX SBOM as a signed attestation with the same key (`cosign attest --type cyclonedx`); the public key is in the repository and on the hosts; signatures are recorded in the public Rekor log, which suits a public repository.
- Deployment uses SSH with one key per environment, kept in OpenBao and fetched only by the deploy stages, restricted in `authorized_keys` by `restrict`, `from=` and `command=`. The script accepts only `deploy <api@digest> <web@digest>`, `rollback` and `status`; it verifies both signatures, deploys by digest, checks health and rolls back on failure.
💡 **Even a fully bypassed pipeline cannot run an unsigned image: the host checks the signature itself.**
💡 **The signing key cannot be stolen from Jenkins, an agent or a backup: it never leaves OpenBao, and every signature is an audited Transit call.**

🧭 **D-15 — Monitoring and alerts: Wazuh 4.14.x single-node (Docker) and Slack.**
Wazuh covers host intrusion detection (file integrity, SSH brute force with active response), log analysis including the OpenBao audit log, and automated compliance (CIS Ubuntu 24.04 SCA policy) in one tool. Slack is the single notification channel for Jenkins and Wazuh; Teams' Office 365 connectors were retired in May 2026, and the brief asks for one channel.

🧭 **D-16 — TLS: a small lab CA for OpenBao, staging and production; Jenkins and SonarQube UIs stay on HTTP behind allow-lists.**
The CA is created once with `openssl` in WSL2 — its key never enters the repository, its certificate does (`infra/pki/kairos-lab-ca.crt`) — and is trusted by every VM (Ansible), the Jenkins JVM and the Legion. OpenBao, staging and production serve TLS 1.2+; the Wazuh dashboard has its own certificates. Jenkins and SonarQube stay on HTTP inside the LAN, reachable only from the addresses that need them — an accepted lab risk (R-10), with TLS for tool UIs as an improvement axis.

🧭 **D-17 — Provisioning: golden image + cloud-init NoCloud seeds + PowerShell on each host + Ansible from WSL2; no Terraform.**
*Why:* a golden image with cloud-init seeds builds a VM in minutes, and Ansible keeps every VM reproducible for a third party. `infra/lab/vms.csv` is the single description of the VMs — read by `New-LabVM.ps1` on each host and by the power scripts.

🧭 **D-18 — Solo-proof roles and repository hygiene.**
Jenkins accounts `admin` (Platform Admin, break-glass only), `adam` (Developer and Security Champion) and `release-manager` (production approval). GitHub required approvals stay at 0 because GitHub does not let authors approve their own pull requests; raising them to 1 is the only change a team needs. From commit #1: `.gitattributes` (LF everywhere, CRLF for PowerShell scripts, `*.ps1`), the repository in WSL2 ext4, SSH commit signing.

🧭 **D-19 — Lab power: one command from WSL2 on the Legion drives both hosts, and unseals OpenBao on the way up.**
`make lab-up`, `make lab-down` and `make lab-status` run the scripts of Appendix G: the Legion's Hyper-V through Windows PowerShell (WSL interop), the OptiPlex's over SSH with a dedicated key. Nothing starts unless every host has the rights, the wired link and the memory; VMs start and stop one at a time in a fixed order; nothing is ever saved or powered off hard.
💡 **Unseal key shares are typed, never stored: they reach OpenBao through stdin and HTTPS — never a file, a command-line argument or the screen.**

🧭 **D-20 — AI: Kairos Assist, an LLM feature on DeepSeek's API, is part of the core and arrives as a new feature through the gates (WP4.7).**
*Why:* it brings the OWASP Top 10 for LLM Applications into the same pipeline. Its three LLM weaknesses (SV-12–SV-14), written the way a developer under pressure would write them, must be caught by the existing gates and two new Semgrep rules, then fixed test-first.
*Provider:* DeepSeek's OpenAI-compatible API (`https://api.deepseek.com`) with `deepseek-flash` (DeepSeek-V4.1-Flash-1017) in non-thinking mode — turning a note into a task needs no reasoning, and Flash is the cheaper model with the higher concurrency limit; `deepseek-v4-pro` is one configuration value away. One API key per environment lives in OpenBao, rendered by the OpenBao Agent; CI uses a stub model (no key, no cost, deterministic tests); `ASSIST_ENABLED` switches the feature off without a release.
*Data:* DeepSeek's privacy policy stores the data it collects on servers in the People's Republic of China, so Kairos sends it only lab data — fake users' task text — with an opaque `user_id`, never an e-mail address; the report discusses data residency and the open-weights alternative of hosting the same model yourself (T-15).
*Alternative:* a local model on the Legion's GPU — free and offline, but one more always-on service on the workstation, and no key to protect.
💡 **DeepSeek's defaults — thinking mode on, up to 64K output tokens per call — are the unbounded-consumption weakness (LLM10) in its real-world form; the fix is three call settings and a per-user rate limit, and a Semgrep rule keeps them.**

---

## Decisions after the plan

🧭 **D-21 — The repository lives in the project folder, `D:\Projects\Kairos\kairos`, worked on from WSL2 with Linux permissions on the D: drive** · 2026-11-01 · supersedes the part of D-18 that kept the repository in WSL2's ext4 disk
*Why:* one folder, `D:\Projects\Kairos`, holds the whole project — repository, Ubuntu ISO, golden image, seeds, VMs, verified releases, guides — so it is found, backed up and moved as one.
*How:* WSL2 mounts the Windows drives with permission metadata (`/etc/wsl.conf`, `[automount] options = "metadata,umask=22,fmask=11"`, Microsoft's documented setting). Files created from WSL2 keep real Linux modes, so the executable bit, Git's file modes and Ansible's refusal of a world-writable `ansible.cfg` folder all behave as on ext4. Git is used from WSL2 only, and repository files are edited through WSL2 (VS Code's WSL mode): a file a Windows program creates or rewrites has no metadata and shows as `rwxr--r--`, which Git would record as executable — screenshots saved from Windows into `docs/evidence/` get `chmod 644` before they are staged.
*Kept outside the folder:* key material and per-user tools — `~/.ssh` (SSH keys), `~/.kairos-pki` (the lab CA key and issued keys), `~/.local/bin` (pinned tools) and the OpenBao login token — which belong to the WSL2 account, not to a project folder that backup and sync tools copy.
*Cost:* Git and Docker bind mounts are slower on the D: drive than on ext4 — acceptable at this repository's size.
*Alternative:* the repository in WSL2's ext4 disk (`~/projects/kairos`, D-18 as written) — faster, but the project split across two places.
*Recorded in:* the bootstrap commit.

🧭 **D-22 — The OptiPlex keeps the plan's VM sizes although its E-10 disk ceiling is below them, under a measured guard** · 2026-11-04 · supersedes, for the OptiPlex only, §3.1's rule "sum of VHDX maxima ≤ free disk − existing growth room − 25 GB" (E-10)
*Measured (WP0.2):* C: 94.4 GB free; the host's two existing VMs can still grow by 51.1 GB; ceiling 94.4 − 51.1 − 25 = 18.3 GB, against 105 GB of lab maxima (`dso-jenkins` 25, `dso-agent` 60, `dso-sonar` 20). Memory fits: about 14 GB stay free with the lab running.
*Why:* the lab disks are dynamic and grow only with use (a fresh VM takes a few GB); the existing VMs are kept Off during Kairos sessions and are due to be retired, after which the ceiling is about 158 GB and the rule holds as designed. No other placement meets §3.1 either: the Legion cannot take `dso-agent` and `dso-sonar` together (memory) or all seven VMs (disk).
*Guard (tracked in `docs/lab/capacity.md`):* **CAP-01** — `infra/lab/host-report.sh optiplex` at the start of every phase; if C: has less than 25 GB free, `dso-sonar` moves to the Legion through `infra/lab/vms.csv` (Legion: 14 GB of VMs, 5 GB left; 110 of 175 GB). **CAP-02** — before such a move, `infra/lab/host-report.sh legion` records the growth room of the Legion's own VMs, which its recorded figures predate. CAP-01 closes when the existing OptiPlex VMs are gone and the ceiling is measured above 105 GB.
*Risk if the guard is missed:* the volume fills, Hyper-V pauses the running VMs (state *Paused-Critical*) and `make lab-up` refuses to start until space is freed — no data is lost, a session is.
*Alternatives:* a dedicated lab SSD in the OptiPlex (no cost to the existing VMs, but hardware); moving the existing VMs off C: (frees 88.8 GB, at their owner's cost); shrinking their disk maxima, moving `dso-sonar` to the Legion and `dso-agent` to 40 GB (meets the rule with no margin, and leaves the build agent at the size where R-03 bites first).
*Pull request:* the P1 pull request (`feat/p1-lab`)

🧭 **D-23 — Gitleaks false positives that come from a file's format are fixed once in `.gitleaks.toml`, scoped to that file and that format; findings in content stay exceptions (§4.3)** · 2026-11-04 · adds to §4.3, which names only `.gitleaksignore` markers
*Found (WP1.4):* the commit-time scan (E-11) reported 29 `generic-api-key` findings in `ci/jenkins/plugins.txt`: every pin whose plugin id contains `api` (`analysis-model-api:13.x`, `jjwt-api:…`) looks like a key name followed by a random value. They are plugin versions, published on the Jenkins update center.
*How:* `.gitleaks.toml` at the repository root extends Gitleaks' default rules and adds one allowlist whose two conditions must both hold: the path is exactly `ci/jenkins/plugins.txt`, and the whole line is one `plugin-id:version` pin (version starting with a digit). Anything else in that file — a token after a plugin id, a second value on a pin line, a `key = …` line — and the same text in any other file are still reported. Tested with Gitleaks 8.30.1 in staged, directory and full-history scans, with those negative cases.
*Why not `.gitleaksignore`:* its fingerprints carry the line number, so every `pin-plugins.sh` run would move 29 of them; in history scans they also carry the commit, which the squash-merge changes, so the `main` lane would report them again; and each would be an exception with an expiry to renew for something that is not a secret.
*Rule kept:* `.gitleaks.toml` holds only format-level false positives of generated, non-secret files, each with its reason; it is reviewed in pull requests like code, and `ci/scripts/secrets_scan.sh` and the hook use it (no other `--config`).
*Alternative:* `.gitleaksignore` fingerprints under exception IDs (above).
*Pull request:* the P1 pull request (`feat/p1-lab`)

🧭 **D-24 — No password manager: every secret that is not in OpenBao or Jenkins lives in the owner's safe place, and every step that creates or asks for a secret carries a banner** · 2026-11-03 · supersedes the operations line of D-07 ("kept in your password manager") and nothing else in it
*Why:* the owner has no password manager (PM-01, 2026-11-03). The values that never move into OpenBao — the unseal key shares, the administrator passwords of OpenBao, Jenkins and SonarQube, the lab CA passphrase — therefore live in a safe place the owner controls (PM-02, 2026-11-04), the three unseal shares with one more, offline copy. D-07's rules are unchanged: OpenBao stays the single store for pipeline and runtime secrets.
*How:* before each step that creates or asks for a secret, a banner names the value exactly as it is saved, says when it appears and how long to keep it; a value that is only re-used, and a value that can be thrown away, each have their own banner. Secrets travel through hidden prompts, stdin or the clipboard, never on the screen, in a command line or in a chat, and a value that leaks is revoked or rotated at once. `docs/runbooks/accounts.md` and the scripts say "safe place".
*Alternative:* a password manager — not available to the owner (PM-01); a project file or the repository — never, the repository is public.
*Pull request:* the P2 pull request (`feat/p2-app`)

🧭 **D-25 — The unit tests run on SQLite; the real PostgreSQL 17 is exercised by the smoke test** · 2026-11-05 · adds to WP2.1
*Why:* the plan asks for pytest unit tests and for PostgreSQL 17 as the database, and does not say where the tests run. A suite that needs a database service is slower, asks more of the as-is pipeline's test stage, and fails for reasons that are not the code's.
*How:* `backend/tests/conftest.py` sets `DATABASE_URL=sqlite://` before the application is imported (in memory, a fresh schema for every test). `ci/as-is/smoke.sh` walks every endpoint against the Compose stack's PostgreSQL 17 on the Legion (WP2.1) and against staging and production (WP2.2). SV-02 uses `lower() LIKE lower()` so that both databases run it (E-30); its static detection (Bandit B608, the Semgrep rule) does not depend on the database.
*Cost:* a behaviour that only PostgreSQL has is seen by the smoke test, not by the unit tests.
*Alternative:* a PostgreSQL service container in the test stage (WP4.2 may add one to the to-be pipeline) · `testcontainers`.
*Pull request:* the P2 pull request (`feat/p2-app`)

🧭 **D-26 — Seeded secrets are accepted at commit time by an exact list, never by an ignore file or a wider configuration** · 2026-11-05 · adds to D-23 and E-11
*Found (WP2.1):* SV-01 puts two fake secrets in the repository on purpose (`backend/app/config.py` and `deploy/.env`). Gitleaks reports each as `generic-api-key`, so the commit-time scan fails on the commit that adds them.
*How:* `ci/tools/commit-scan.sh` runs the pinned Gitleaks with `.gitleaks.toml` on the staged changes and compares the findings with `security/seeded-secrets.tsv` (file, rule, one finding each). A finding outside the list, a listed file staged without its finding, or a second finding in a listed file blocks. The P3 hook runs the same script. WP4.5 fixes SV-01 and deletes the list.
*Why not the usual ways:* `.gitleaksignore` fingerprints carry line numbers and, in history scans, the commit (D-23's reasoning); `.gitleaks.toml` is reserved by D-23 for false positives that come from a file's format, and a seeded weakness is content that WP8.1 must be able to find; an inline `gitleaks:allow` marker would blind the scanner exactly where it has to look.
*Alternative:* any of those three.
*Pull request:* the P2 pull request (`feat/p2-app`)

🧭 **D-28 — The as-is practices are code, with a removal switch** · 2026-11-05 · adds to WP2.2
*Why:* the as-is state is the *before* of the project, and WP8.1 runs it again on purpose. The hardening work packages must be able to remove each practice cleanly, and the lab stays idempotent.
*How:* `infra/ansible/roles/as-is` (tag `as-is`): `sshpass` on the build agent; on staging and production the `deploy` account with a password read from OpenBao (`kv/infra/as-is-deploy`), SSH password logins through `/etc/ssh/sshd_config.d/10-kairos-as-is.conf`, the application folder, and an assertion that `sshd -T` agrees with the state. `-e as_is_state=absent` removes them (the stack stopped, the folder, the account, the drop-in); WP5.3 (staging), WP6.1 (production) and WP7.1 use it. The job `kairos-as-is` stays for WP8.1, its Docker Hub token until WP4.1.
*Alternative:* accounts and settings made by hand (not reproducible, not removable by code).
*Pull request:* the P2 pull request (`feat/p2-app`)

🧭 **D-30 — The Node image pin is kept after its tag was republished** · 2026-11-06 · adds to D-12
*Found (WP2.1, step 2.1.5):* the check of `ci/tools/node-image.txt` showed that the tag `node:26.13.0-slim` had been republished on 2026-11-05: the pinned digest `sha256:e4db4c91…a02c39` was no longer the one the tag serves.
*How:* the pinned digest stays, because it is still pullable (proved) and D-12 says a new version or rebuild waits 7 days and arrives in its own pull request. The re-pin is the tracked item NODE-01 (`docs/lab/services.md`): from 2026-11-12, after reading what changed, in its own pull request, together with WP4.6.
*Alternative:* re-pin at once to the new digest (it skips the 7-day rule and the reading).
*Pull request:* the P2 pull request (`feat/p2-app`)

🧭 **D-27 — The hooks look at changed files; the seeded findings pass only through two exact hook-only lists until WP4.5** · 2026-11-05 · adds to WP3.2
*Why:* Kairos v0 holds weaknesses on purpose (plan section 5) in the very files a hook scans, so a strict hook and a hook that works at all would otherwise exclude each other. The pipeline reports every one of them (WP4.2); the workstation must not block the pushes that fix them.
*How:* `pre-commit` runs on the files of the commit or push. The Gitleaks hook is `ci/tools/commit-scan.sh` with `security/seeded-secrets.tsv` (D-26, two rows). The Trivy hook is `ci/tools/hook-trivy.sh` with `security/seeded-trivy.tsv` (five rows: pyjwt 2.3.0 in `backend/uv.lock`, lodash 4.17.11 in `frontend/package-lock.json`, DS-0002 and DS-0031 on `backend/Dockerfile`, DS-0002 on `frontend/Dockerfile`); a finding outside the list (another package, another version of a listed package, or another check) blocks, whatever its severity, while every advisory of a listed package at its listed version passes, however many the database adds. Hadolint fails at level `error`. Bandit and ESLint list nothing: until WP4.5, `pre-commit run --all-files` is red on SV-05 and SV-03, and a commit that changes `backend/app/security.py` or `frontend/src/CommentList.tsx` is blocked. WP4.5 deletes the two lists with the fixes. `--no-verify` is never used. The done-when of WP3.2 is proved with two demo files (`ci/tools/hooks-demo.sh`), never committed to a pushed branch.
*Watch (HOOK-01):* the Python dependencies of the hooks themselves (Bandit's, Semgrep's) are resolved when pre-commit builds their environments, without the 7-day limit that `uv --exclude-newer` gives the tools; decide at WP4.6, with the dependency automation, how to pin them. The hook repositories' own revisions are frozen (E-34).
*Alternative:* ignore files for either scanner (rejected in D-23 and D-26) · hooks that skip the seeded files (a blind spot that someone would have to remember to remove).
*Pull request:* the P3 pull request (`feat/p3-shift-left`)

🧭 **D-29 — The IDE is VS Code in WSL mode only, with the extension hygiene of `docs/runbooks/ide.md`** · 2026-11-05 · adds to WP3.1 and D-21
*Why:* an editor extension runs with the developer's permissions, and two security extensions were compromised in early 2026 (the Trivy extension for VS Code; Checkmarx's on Open VSX). The editor is the first control of the project and must not be its weakest link.
*How:* `.vscode/extensions.json` lists six ids (Python, Pylance, Ruff, ESLint, SonarQube for IDE, YAML) and `.vscode/settings.json` points them at the project; both are in the repository and change only by pull request. The extensions are installed in a WSL window by exact id, the publisher is checked against the id, the version is at least 7 days old (D-12), and automatic updates are off. SonarQube for IDE is bound to project `kairos` on the lab server with a **user token**, `kairos-ide` (the CI analysis token is another kind and stays in OpenBao), kept in VS Code's secret storage, with a 90-day expiry and never in a file (IDE-01). The Trivy extension and Open VSX are not used; Trivy and Hadolint run as pinned binaries in the hooks.
*Cost:* the token is `admin`'s, the server's only account (IDE-01: renew it before the expiry noted in `docs/runbooks/accounts.md`, and replace it by a read-only account's token if one is ever created).
*Alternative:* a second, non-admin SonarQube account made now · a token with no expiry · VS Code on the Windows side.
*Pull request:* the P3 pull request (`feat/p3-shift-left`)

🧭 **D-31 — Extensions on the Windows side of a WSL window are part of the IDE profile: one that runs code is removed, and a version's date is read from the marketplace's public query** · 2026-11-07 · adds to D-29 and WP3.1
*Why:* a WSL window also runs the UI extensions installed on the Windows side ("Local – Installed"), with the developer's Windows permissions, outside WSL and outside the six ids of D-29. In WP3.1 one of them, a snippet pack, activated at startup and contributed commands: it ran code in the window. And the *Version History* tab that the guide relied on does not exist in the editor; the marketplace page lists only the newest builds, so a version's age (D-12) could not be read from it.
*How:* the Windows-side list is read once, when the profile is set up: in each extension's *Features* tab, a *Runtime Status*, activation events or commands mean it runs code; a pack that contributes only snippets or themes does not. An extension that runs code and is neither one of the six ids nor Microsoft's WSL extension is uninstalled from Windows (`code --uninstall-extension <id>`); that was done for the one found. Extensions marked **Built-in** are VS Code itself and are outside the list. The date and the release or pre-release flag of every installed version, companions included, are read from the marketplace's public query (`docs/runbooks/ide.md`). Installed: Python 2026.10.0, Ruff 2026.92.0, Python Environments 1.40.0 (the release before one that was 2 days old), all dated on or before the cutoff of 29 October 2026. VS Code's own `extensions.autoUpdate` takes `"on"` or `"off"` and is set to `"off"`.
*Watch (IDE-02):* an extension installed on the Windows side later is not seen by the repository: repeat the check of `docs/runbooks/ide.md` when the profile changes, and the pull request that touches `.vscode/extensions.json` says it was done.
*Watch (IDE-03):* in Connected Mode, SonarQube for IDE reported only `python:S4790` (on `security.py`) in the seeded code. It reported nothing on `tasks.py` (SV-02) or `importer.py` (SV-04), where only Ruff does. At WP4.2, read what the server's own analysis reports on those two files and find out why, before the quality gate of P4 counts on SonarQube for them.
*Alternative:* a dedicated VS Code profile with only the six ids (more setup, and the Windows-side extension stays installed) · disabling it for this workspace only (VS Code keeps that outside the repository, and it resets with its storage).
*Pull request:* the P3 pull request (`feat/p3-shift-left`)

🧭 **D-32 — SonarQube's new code is "Previous version", with a project version that never changes** · 2026-11-11 · closes NC-01
*Why:* the gate "Kairos Secure" judges new code. The plan started the new-code period at the baseline analysis, but the Community Build 26.10 offers only *Previous version*, *Number of days* and *Reference branch* for a project. A number of days slides: after that many days the seeded weaknesses would leave "new code" and the gate would pass with nothing fixed. A reference branch needs a second analysed branch, and the Community Build analyses one (D-09).
*How:* *Previous version* is set explicitly on the project, and the version the scanner sends is `SONAR_PROJECT_VERSION=0.2.0` in `security/policy/gates.env` (passed as `sonar.projectVersion`). The version does not change during the project, so the reference does not move: the only way to take a finding out of "new code" is to fix it. Changing that value starts a new period and hides what came before — it is a decision, in a pull request, with a record.
*Watch:* after the baseline analysis the label of the period is read on SonarQube's Overview and written in `docs/as-is/baseline-scorecard.md`; the **Overall Code** tab is the cross-check for the checks of WP4.5.
*Alternative:* Number of days · Reference branch.
*Pull request:* the CI pull request (`feat/p4-ci`)

🧭 **D-36 — P4 to P8 are cut to what a defendable pipeline needs; every cut is a named, tracked item** · 2026-11-11 · adds to the plan's section 11.2
*Why:* the time left is about a guide and a half; the plan's own rule for that case is to stop adding scope and protect P8, because the report and the defense carry the grade.
*How:* each cut is a complete end state, not a half-built feature — **RSC-01** production re-scan (WP7.4): a scan at every build instead; **PTS-01** pentest tools: a scripted subset of OWASP WSTG run before and after; **IR-1 not run**: one full incident loop (IR-2) instead; **HRD-02** hardening of the other VMs: measured on both runtime hosts; **WZH-01** custom Wazuh rules and active response: the built-in rules, alerts in the dashboard (file-integrity level 7 is below the level 10 that Slack receives); **AST-02** Kairos Assist in production: staging only, and **AST-01** the live DeepSeek key exists only there; **RBK-01** the live drill of a failing production release: the refusal is proved by tests and against a real web tier, and a manual rollback is drilled; **DEM-01** the to-be pipeline run on the as-is code: the scorecard and the detection matrix instead; **UI-01** a designed interface: the plain one stays; **JNK-01** Audit Trail is kept. Also decided: the enforce switches are **one** pull request, because each pull request's own build already shows which control would block; the throwaway OpenBao pipeline of the plan's WP4.1 is replaced by P1's 30/30 AppRole proof (negative) and the first real runs (positive); **DHT-01** if Docker Hub offered no repository-limited token, the pipeline's token covers the account's two public repositories, is held in OpenBao, is read by two stages that run on `main`, and expires in 90 days; the account also holds six personal access tokens that pre-date the project, with read, write and delete scope, that the project did not create and does not manage: they were left as they are, by the owner's decision of the day this record is dated, and are carried under DHT-01 — a small residual risk that the report states.
*Watch:* the cut line of the plan applies — if the clock says more than about 16 h at the end of P6, P7 is run on production only (**HRD-03**) and P8 starts at once. D-37 (P7) is the one exception the cuts make to the CIS recommendations. **Reinstated afterwards, at the owner's request, each by a record of its own:** WZH-01 in part (a) (D-39), UI-01 (D-40), RBK-01 (6.6), IR-1 (D-41), DEM-01 (D-42); this record says what the cut was, and it stays as it was written.
*Alternative:* keep the full plan and drop P8's report chapters (rejected: the report is graded) · a half-built version of each cut feature (rejected: a stopgap).
*Pull request:* the CI pull request (`feat/p4-ci`)

🧭 **D-43 — The Sonar scanner's container gets an executable `/tmp`; every other tool keeps the `noexec` one** · 2026-11-11 · adds to D-12
*Found (WP4.2, step 4.2.6):* the first build of `main` failed at `sast`: the scanner downloads its JRE into `SONAR_USER_HOME` under `/tmp` and runs it from there, and Docker mounts a `--tmpfs` with `noexec`. Proved on the agent: the mount line of `/tmp` showed `noexec` and a script written there answered `Permission denied`; mounted with `exec` it ran. Only `main` runs the scanner, so no pull-request build could show it.
*How:* `ci/scripts/run-tool.sh` has the option `--exec-tmp`, which mounts that container's `/tmp` as `rw,exec,nosuid,nodev`. Only the scanner call of `ci/scripts/sast.sh` uses it, and the self-test checks both facts. The root filesystem stays read-only, no capability is added back, the container runs as the build user, and the tmpfs disappears with the container.
*Alternative:* a persistent cache volume for the scanner (an executable folder that outlives the build, and a change to the agent's play) · skipping the scanner's JRE provisioning (it covers the Java binary only) · an executable `/tmp` for every tool.
*Pull request:* the follow-up pull request (`fix/p4-sonar-exec`)

🧭 **D-33 — The history is not rewritten; the two seeded fake values are baselined by fingerprint** · 2026-11-11 · adds to D-26
*Why:* Kairos v0 committed two fake values on purpose (SV-01: the signing key in `backend/app/config.py` and the password in `deploy/.env`). A public history keeps them: forks and clones hold copies, so a rewrite would not take them back, and it would break every signed commit and every pull request that points at the old history, and the signed tag of P8.
*How:* the files no longer hold them; `security/gitleaks-baseline.json` (written by `ci/tools/make-gitleaks-baseline.sh`, which refuses unless the history holds **exactly** these two findings) lists them by fingerprint (commit, file, rule, line) and `ci/scripts/secrets_scan.sh` passes it to the history scan: any other secret, and the same file at a new commit, is still reported. The list of seeded secrets of the commit hook (`security/seeded-secrets.tsv`) is gone. The development secrets are files made by `ci/tools/dev-secrets.sh`, mode 0444 on purpose (Compose mounts a secret file with the owner and mode it has on the host, and the containers run as other users); they are random values of a development machine.
*Watch:* a real secret found in the history is an incident: rotate it (plan 4.3); it is never added to the baseline.
*Alternative:* `git filter-repo` and a force-push (rejected above).
*Pull request:* the fix pull request (`fix/p4-seeded-weaknesses`)

🧭 **D-34 — HOOK-01 is closed by an installer that applies the 7-day rule to the hooks' own dependencies** · 2026-11-11 · adds to D-12 and WP3.2
*Why:* pre-commit builds one environment per hook repository and resolves its Python dependencies with whatever is newest, outside the 7-day limit that D-12 gives the tools (HOOK-01).
*How:* `ci/tools/hooks-install.sh` (`make hooks-install`) installs pre-commit 4.7.0 with `pre-commit-uv` and `uv`, exports `UV_EXCLUDE_NEWER` as seven days ago, runs `pre-commit clean`, installs the commit and push stages and rebuilds the hook environments under that limit; `ci/tools/check-tools-lock.sh`, run by `preflight`, compares its versions with the lock and with `.pre-commit-config.yaml`. The hook repositories' revisions stay frozen (E-34). With it: `frontend/.npmrc` (`min-release-age=7`, npm 11.10 or newer), Dependabot version updates with a cooldown of 7 days, and the required status check `continuous-integration/jenkins/pr-merge` in the ruleset of `main`.
*Watch:* run `make hooks-install` again after any change of a hook revision. NPM-01 (only if the npm of the pinned image is older than 11.10): the line of `frontend/.npmrc` is ignored until NODE-01 re-pins the image; `ci/tools/lock-age.py` and the cooldown carry the rule meanwhile.
*Alternative:* a lockfile of the hooks' dependencies (pre-commit has none, and a vendored requirements file per hook is heavy to keep true).
*Pull request:* the required-check pull request (`feat/p4-required-check`)
