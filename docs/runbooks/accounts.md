# Accounts and credentials

Every account and credential of the project, by **name** — never a value (plan WP0.1). Values live in OpenBao, in Jenkins credentials (bootstrap identities only) or in your password manager, as the "Stored in" column says. Update the row whenever a credential is created, rotated or revoked.

Rotation periods follow plan sections 3.3 and 14: 90 days for tokens and AppRole secret IDs (OpenBao enforces it for the secret IDs), yearly for the Slack and GitHub App credentials.

| Name | Kind | Scope / permissions | Stored in | Created | Rotate by |
|---|---|---|---|---|---|
| GitHub `AdamChokri` | Account | Owner of `AdamChokri/kairos` | Password manager (2FA on) | — | — |
| `kairos_signing` | SSH signing key | Commit signing (GitHub *signing* key) | `~/.ssh` in WSL2, passphrase in password manager | | Yearly |
| `kairos_lab` | SSH key, no passphrase (automation: power scripts — accepted lab risk) | Legion → OptiPlex host (`administrators_authorized_keys`) | `~/.ssh` in WSL2 | | Project end |
| `kairos_admin` | SSH key, no passphrase (automation: Ansible — accepted lab risk) | Legion → every lab VM, user `adam` (passwordless `sudo`) | `~/.ssh` in WSL2 | | Project end |
| Docker Hub `<dh-user>` | Account | Owner of `kairos-api`, `kairos-web` | Password manager (2FA on) | | — |
| `kairos-lab-pull` | Docker Hub token | Read-only, public repositories | OpenBao `kv/infra/dockerhub-ro` (WP1.3) | | 90 days |
| Slack workspace | Account | `#kairos-ci`, `#kairos-secops` | Password manager | | — |
| Kairos CI (Slack app) | Bot token `xoxb-…` | `chat:write` only | Password manager until WP4.3, then Jenkins credentials | | Yearly |
| Kairos SecOps Alerts (Slack app) | Incoming webhook | Posts to `#kairos-secops` only | OpenBao `kv/infra/wazuh` (WP1.6) | | Yearly |
| Lab CA | CA key (`~/.kairos-pki/kairos-lab-ca.key`) | Issues certificates for `kairos.lab` and 192.168.1.0/24 only | WSL2 home, passphrase in password manager | | Project end |
| OpenBao unseal key shares (3, threshold 2) | Shamir shares | Unseal OpenBao | Password manager, plus one offline copy | | On suspicion (`bao operator rekey`) |
| OpenBao root token | Token | Initial setup only | Revoked after setup (WP1.3) | | — |
| OpenBao `adam` | userpass account | Policy `admin` | Password manager | | Yearly |
| AppRole `jenkins-build`, `jenkins-deploy`, `jenkins-signer` | Role ID + secret ID | Policies of the same name, bound to 192.168.1.71 | Jenkins credentials `bao-build`, `bao-deploy`, `bao-signer` (WP4.1) | | 90 days (enforced) |
| AppRole `kairos-staging`, `kairos-prod` | Role ID + secret ID | Policies of the same name, bound to .75 / .76 | Runtime host, 0400 (WP5.3 staging, WP6.1 production) | | 90 days (enforced) |
| Jenkins `admin` | Account | Break-glass administrator | Password manager | | Yearly |
| Jenkins agent secrets (`build-agent`, `deploy-agent`) | Agent secrets | Connect one agent each | OpenBao `kv/infra/jenkins-agents` (WP1.4) | | When the node is recreated |
| GitHub App `kairos-jenkins` | App private key | This repository only: contents/metadata/pull requests read, commit statuses read & write | Jenkins credentials (WP1.4); the downloaded key is shredded | | Yearly |
| SonarQube `admin` | Account | Administrator | Password manager | | Yearly |
| SonarQube `kairos-ci` | Analysis token | Project `kairos` | OpenBao `kv/ci/sonarqube` (WP1.5) | | 90 days |
| Wazuh indexer `admin`, `kibanaserver`, API `wazuh-wui`, enrollment password | Passwords | Wazuh internals and the dashboard login | OpenBao `kv/infra/wazuh` (WP1.6) | | Yearly |
| DeepSeek API keys (staging, production) | API keys | Kairos Assist | OpenBao `kv/kairos/staging/llm`, `kv/kairos/prod/llm` (WP4.7) | | 90 days |
