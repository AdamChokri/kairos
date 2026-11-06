# Tools inventory (as-is)

What the as-is flow touches, and how each piece is pinned. "Floating" means a later run may behave differently without any change in this repository.

| Tool | Role in the as-is flow | Version | Pinned? |
|---|---|---|---|
| Git and GitHub | Source of truth; branch `main` is reached by pull request only (ruleset, P0) | GitHub-hosted | n/a |
| GitHub App `kairos-jenkins-adamchokri` | Lets Jenkins read the repository and report statuses; installed on this repository only | n/a | Key rotated yearly |
| Jenkins controller | Scans, schedules, shows the console | 2.580.2 LTS (`lts-jdk21`, by digest in `ci/jenkins/Dockerfile`) | Yes: image digest and `ci/jenkins/plugins.txt` |
| Jenkins plugins | Pipeline, Git, GitHub Branch Source, Credentials Binding, Timestamper and the rest of `ci/jenkins/plugins.txt` (95 lines, every version pinned) | See the file | Yes |
| Build agent `build-agent` | Runs every stage; user `jagent`, member of the `docker` group (root-equivalent) | Java 21, Docker Engine from Docker's apt repository | Docker: floating (apt) |
| Docker Engine and Compose | Builds, pushes, runs the stack | Docker Engine and the Compose plugin from Docker's apt repository | Floating (apt) |
| Docker Hub | Holds `kairos-api` and `kairos-web` (public repositories) | SaaS | n/a |
| `python:latest` | Test container and base of `backend/Dockerfile` | Whatever the tag points to on the day (Python 3.15 on 2026-11-05) | **No** (SV-09) |
| `node:latest` | Build container and base of `frontend/Dockerfile` | Whatever the tag points to (Node 26 on 2026-11-05) | **No** (SV-09) |
| `postgres:17` | The database | The 17 line, floating within it | Partly |
| uv | Installs the backend from `uv.lock` inside the test container and the image | Latest at run time (`pip install uv`) | **No**; the lockfile is frozen |
| npm | `npm ci` in the test container; `npm install` in the image | The one bundled with `node:latest` | **No**; the lockfile is used |
| pytest, Vitest, Vite | Backend tests, frontend tests, frontend build and dev server | `uv.lock`, `package-lock.json` | Yes (lockfiles) |
| OpenSSH, `sshpass` | Deploy: `scp` and `ssh` with a password on the command line | Ubuntu 24.04 packages | Floating (apt) |
| Ansible role `as-is` | Creates the `deploy` account and the password SSH setting; installs `sshpass`; removable with `-e as_is_state=absent` | `infra/ansible/roles/as-is` | Yes |
| OpenBao | Holds the deploy password (`kv/infra/as-is-deploy`); not used by the as-is job itself | 2.7.2 | Yes |

Not present at all, by design: any scanner, any signature check, any SBOM, any registry other than Docker Hub, any notification.
