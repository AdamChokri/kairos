# Seeded weaknesses of Kairos v0

Kairos v0 contains these weaknesses **on purpose** (plan section 5): the project measures every control against code that really has the flaw it catches. Nothing here is a real credential: every secret is a fake value shaped like a generic API key, never a provider's format. "Expected detectors" are hypotheses; WP8.1 records what each tool actually found.

**Fix as soon as detected** (section 5): a weakness is fixed right after the control that reveals it goes live, so `main` is clean before the to-be pipeline deploys anything. The vulnerable version stays available as the tag `v0.1-as-is`.

## The weaknesses

| ID | Where and how it is written | Expected detectors | Fixed in |
|---|---|---|---|
| SV-01 | `backend/app/config.py` writes the token signing key (`JWT_SECRET_KEY`); `deploy/.env` is committed with the database password. Both values are fake. The commit-time scan accepts exactly these two findings: `security/seeded-secrets.tsv` | Gitleaks, Semgrep (custom rule), SonarQube | WP4.5 |
| SV-02 | `backend/app/routers/tasks.py` builds the search SQL with an f-string inside `text()`: `lower(title) LIKE lower('%{search}%')` (E-30: the plan's `ILIKE` became `lower() LIKE lower()`, which SQLite, used by the unit tests, also runs) | Semgrep (custom rule), SonarQube, Bandit B608 (reported), ZAP API scan | WP4.5 |
| SV-03 | `frontend/src/CommentList.tsx` inserts a comment's text with `dangerouslySetInnerHTML` (stored XSS) | ESLint `react/no-danger`, Semgrep (custom rule), SonarQube | WP4.5 |
| SV-04 | `backend/app/routers/importer.py` reads the YAML body with `yaml.load(..., Loader=yaml.Loader)` | Bandit B506, Semgrep (custom rule), SonarQube | WP4.5 |
| SV-05 | `backend/app/security.py` hashes passwords with unsalted MD5 | Bandit B324, Semgrep, SonarQube | WP4.5 |
| SV-06 | `backend/app/routers/tasks.py` fetches a task by its id alone (`get_task`), so any logged-in user reads, changes and deletes anyone's task; the comment routes use the same function | None expected: regression test and pentest | WP5.4 |
| SV-07 | `PyJWT 2.3.0` (Python) and `lodash 4.17.11` (npm), versions listed below | Trivy fs, Dependabot | WP4.5 |
| SV-08 | `backend/app/main.py`: stack traces in 500 responses, CORS `*` with credentials, no security headers, `X-Powered-By` with the versions; plain HTTP | ZAP baseline, Semgrep (CORS), smoke tests | WP5.3 (TLS), WP5.4 |
| SV-09 | `backend/Dockerfile` and `frontend/Dockerfile`: `python:latest` and `node:latest`, root user, `ENV ADMIN_API_KEY` (a fake secret), the Vite dev server as the web tier; `deploy/compose.yaml` publishes 8000 and 5173 on every interface with Docker's default runtime settings | Hadolint, Trivy config, Trivy image; the Compose half by review | WP4.5 |
| SV-10 | `ci/as-is/Jenkinsfile`: Docker Hub token through Groovy interpolation, password SSH with `sshpass`, host keys unchecked, mutable `:latest` tags, no scan, no pull-request build | Jenkins' interpolation warning; review against the OWASP CI/CD Top 10 | P4 to P6 |
| SV-11 | The as-is hosts (`infra/ansible/roles/as-is`): the `deploy` account with a password, `PasswordAuthentication yes`, no firewall, default sysctls, no auditd | Lynis, Wazuh SCA (CIS Ubuntu 24.04) | WP7.1 |

## SV-07: the two vulnerable packages (OI-06)

Chosen by installing them and reading scanner output (2026-11-05). Both install cleanly with the lockfiles in the repository (`backend/uv.lock`, `frontend/package-lock.json`).

| Package | Version | Headline advisory | Severity | Fixed in | What a Dependabot security pull request proposes |
|---|---|---|---|---|---|
| `pyjwt` (Python) | 2.3.0 | CVE-2022-29217 (GHSA-ffqj-6fqr-9h24), algorithm confusion: some public-key formats are not refused as HMAC secrets | High (7.5) | 2.4.0 | 2.15.1 or newer, which also closes the later PyJWT advisories |
| `lodash` (npm) | 4.17.11 | CVE-2019-10744 (GHSA-jf85-cpcp-j695), prototype pollution in `defaultsDeep` | Critical (9.1) | 4.17.12 | 4.18.1 or newer |

A scanner lists more advisories than the headline for each package: `pip-audit` reports 14 for PyJWT 2.3.0 and `npm audit` 6 for lodash 4.17.11 on 2026-11-05. The headline is the one that makes the package High or Critical *with a fix*, which is what the gate looks at. Kairos signs and verifies with HS256 and a fixed algorithm list, and calls only `lodash/debounce`, so the headline flaws are not reachable through its own use; a scanner reports the package anyway, which is how vulnerable dependencies are usually found.

## Checklist (WP2.1 and WP2.2)

Run each command, read what it shows, and tick the line only when it showed the weakness. `bash security/check-seeded.sh` (API running) covers SV-01, SV-02, SV-04, SV-06 and SV-08 at once.

- [x] SV-01 the key is in the source, and a token signed with it is accepted: `bash security/check-seeded.sh` → `PASS SV-01`; `git ls-files deploy/.env` prints the file
- [x] SV-02 an SQL payload returns another user's task: `bash security/check-seeded.sh` → `PASS SV-02`
- [x] SV-03 a comment runs script in the browser: add the comment `<img src=x onerror="document.title='XSS'">` to a task in the app; the tab's title becomes `XSS`
- [x] SV-04 a YAML tag runs a function in the server: `bash security/check-seeded.sh` → `PASS SV-04`
- [x] SV-05 the stored hash is plain MD5, the same for the same password: `docker compose -f deploy/compose.yaml exec db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "select username, password_hash from users"'` shows 32 hexadecimal characters, identical for the accounts that share a password
- [x] SV-06 one user reads and changes another user's task: `bash security/check-seeded.sh` → `PASS SV-06`
- [x] SV-07 the scanner reports both packages (Trivy takes one target per run): `trivy fs --scanners vuln --severity HIGH,CRITICAL backend/uv.lock` lists `pyjwt 2.3.0` (High); `trivy fs --scanners vuln --severity HIGH,CRITICAL frontend/package-lock.json` lists `lodash 4.17.11` (Critical)
- [x] SV-08 errors, CORS, headers and plain HTTP: `bash security/check-seeded.sh` → the five `PASS SV-08` lines
- [x] SV-09 root, a secret in the image, the dev server: `docker compose -f deploy/compose.yaml exec api id` prints `uid=0(root)`; `docker compose -f deploy/compose.yaml exec api printenv ADMIN_API_KEY` prints the fake value; `trivy config --severity HIGH,CRITICAL backend/Dockerfile` reports DS-0002 (High) and DS-0031 (Critical), and the same command on `frontend/Dockerfile` reports DS-0002 (High)
- [ ] SV-10 the as-is job exists and its console shows Jenkins' warning about Groovy string interpolation (WP2.2)
- [ ] SV-11 the hosts accept password logins for the deploy account (WP2.2): `ssh dso-staging "sudo sshd -T -C user=deploy,host=lab,addr=127.0.0.1 | grep ^passwordauthentication"` prints `passwordauthentication yes`; the same on `dso-prod`

## Not seeded

Two ordinary design choices are not seeded weaknesses and no work package fixes them on purpose: the single-page app keeps its token in `localStorage` (ASVS V3, looked at again by the WP5.4 pentest), and the unit tests run on SQLite while the Compose smoke test (`ci/as-is/smoke.sh`) runs the same API on PostgreSQL 17.
