# Jenkins: how the controller is configured

The rebuild guide for a third party (plan WP4.1): what was set in the web interface, where, and how to check it. The controller itself (image, plugins, agents) is built by Ansible and `ci/jenkins/` (WP1.4); everything below is the configuration that lives inside Jenkins, which is not in a file. Screens are in `docs/evidence/` (the names are given with each part). Secrets are never written here: a credential is named, and its value is in OpenBao (`docs/runbooks/accounts.md`).

Controller 2.580.2 LTS on `dso-jenkins`, `http://jenkins.kairos.lab:8080/`, no executor of its own (builds run on `build-agent` and `deploy-agent`).

## 1. Users and authorization (D-18)

*Manage Jenkins → Security*:

- **Security Realm:** Jenkins' own user database, with **Allow users to sign up** switched off.
- **Authorization:** Matrix-based security. The rows, and nothing else:

| User | Overall | Job / Run | Credentials, Agents, Script console |
|---|---|---|---|
| Anonymous | nothing (no *Read*) | nothing | nothing |
| `admin` (break-glass) | Administer | everything | everything |
| `adam` | Read | Build, Read, Cancel, Workspace, Discover | nothing |
| `release-manager` | Read | Read, and the right to answer the production `input` (P6) | nothing |

- **CSRF protection** stays on, **Agent → controller security** stays on, and the **Markup Formatter** stays on *Plain text*: a build description or a job name is never rendered as HTML.
- A user without *Administer* cannot open `/script`: that is the check of WP4.1.

## 2. Audit Trail

*Manage Jenkins → System → Audit Trail*: a **Log file** logger writing to `/var/jenkins_home/audit/audit-%g.log` (the controller's data volume), with a size limit and a few rotated files. It records logins, configuration changes and job runs.

## 3. Resource Root URL

*Manage Jenkins → System → Resource Root URL*: `http://jenkins-res.kairos.lab:8080/`. It is a second host name for the same VM, because Jenkins requires a different host name for the resources it serves. Reports that Jenkins shows as HTML (the Trivy reports of `publishHTML`, ZAP in P5) are then served from that name, so they render with Jenkins' default Content-Security-Policy and without relaxing it. The name is in `infra/lab/lab-hosts.txt`.

## 4. OpenBao

*Manage Jenkins → System → Vault Plugin* (HashiCorp Vault plugin): **Vault URL** `https://openbao.kairos.lab:8200`, **K/V engine version** 2, TLS verification on (the lab CA is in the controller's trust store, WP1.4).

*Manage Jenkins → Credentials → System → Global credentials*, kind **Vault App Role Credential**, one per AppRole of WP1.3:

| Credential ID | AppRole | Used by |
|---|---|---|
| `bao-build` | `jenkins-build` | the `ci` stages (SonarQube token, Docker Hub write token) |
| `bao-deploy` | `jenkins-deploy` | the deploy stages (SSH deploy keys) |
| `bao-signer` | `jenkins-signer` | the `sign` stage (the Transit key, through a short-lived token) |

Each holds a role ID and a secret ID. The secret ID lasts 90 days (OpenBao enforces it): rotate it with `infra/openbao/` and update the credential. The AppRoles are bound to the controller's address, so a stolen secret ID does not work from another machine. A pull-request build binds none of them.

Other credentials: `github-app` (the GitHub App key, WP1.4) and `slack-bot-token` (the Slack bot token, kind *Secret text*, WP4.3).

## 5. Slack

*Manage Jenkins → System → Slack*: **Workspace** the workspace's name, **Credential** `slack-bot-token`, **Default channel** `#kairos-ci`. The bot has `chat:write` only. *Test Connection* posts one message.

## 6. The Multibranch job `kairos`

*New Item → Multibranch Pipeline*, name `kairos`:

- **Branch Sources:** GitHub, credentials `github-app`, repository `AdamChokri/kairos`.
- **Behaviours:** *Discover branches* (strategy: *Exclude branches that are also filed as PRs*), *Discover pull requests from origin* (strategy: *Merging the pull request with the current target branch revision*). **No** behaviour for forks: a fork's pull request is never built (it could change the Jenkinsfile).
- **Build Configuration:** by Jenkinsfile, path `Jenkinsfile`.
- **Scan Multibranch Pipeline Triggers:** *Periodically if not otherwise run*, every 2 minutes (D-06; there is no webhook, the controller is not reachable from the internet).
- The old job `kairos-as-is` is kept, with its polling switched off, because WP8.1 runs it on purpose to show the platform refusing it.

## 7. What was checked

- A user that is not `admin` gets *403* on `/script`.
- A push and a pull request each start a build within about 2 minutes, and the commit status appears on GitHub.
- Each AppRole reads its own paths and nothing else: `bash infra/openbao/test-approles.sh` (P1, 30 checks). The first `main` build reads `kv/ci/sonarqube` through `bao-build`, and OpenBao's audit log (`/var/log/openbao/audit.log` on `dso-bao`) shows the read coming from `192.168.1.71` only. A pull-request build has no `withVault` step and no `VAULT_TOKEN` at all.

Screens: `EV-25-*.png` in `docs/evidence/`.
