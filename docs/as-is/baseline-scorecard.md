# Baseline scorecard

What every control of the pipeline reports on the Kairos v0 code **as it was seeded**: the first builds of `main` after the controls went live, before any weakness was fixed (plan WP4.2). It is the "before" of the project. The numbers are copied from the build's reports (`reports/` in the build's artifacts) and never rounded or estimated.

Build: `kairos` / `main` #2, commit `7b61e7e`, date 2026-11-11. All controls in `report` mode.

## Static controls

| Control | Tool | Findings at or above the threshold | Findings in all | Threshold | Seeded weakness it shows |
|---|---|---|---|---|---|
| secrets_scan | Gitleaks (files) | 2 | 2 | any | SV-01 |
| secrets_scan | Gitleaks (history) | 2 | 2 | any | SV-01 |
| sast | Semgrep | 7 | 10 | ERROR | SV-01, SV-02, SV-03, SV-04 |
| sast | Bandit | 1 | 4 | HIGH, confidence MEDIUM or better | SV-05 |
| sast | ESLint | 1 | 1 | error | SV-03 |
| sast | SonarQube | gate Failed (2 conditions); Security Issues, Overall Code: 1 | Security Issues, New Code: 1 | gate "Kairos Secure" | |
| scan_dependencies | Trivy, `backend/uv.lock` | 6 | 13 | Critical, High with a fix, KEV | SV-07 |
| scan_dependencies | Trivy, `frontend/package-lock.json` | 4 | 6 | Critical, High with a fix, KEV | SV-07 |
| iac_scan | Hadolint | 0 | 5 | error | SV-09 |
| iac_scan | Trivy config | 3 | 3 | High, Critical | SV-09 |
| docker_scan | Trivy image, `kairos-api` | 31 (20 OS packages, 11 Python) | 2574 | Critical, High with a fix, KEV, secrets | SV-09 |
| docker_scan | Trivy image, `kairos-web` | 30 (20 OS packages, 10 Node.js) | 2532 | Critical, High with a fix, KEV, secrets | SV-09 |

## Notes

What a tool found that no seeded weakness explains, and what was done about it (a fix, or a tracked item), is written here with the date.

- 2026-11-11: the baseline is build #2 (commit `7b61e7e`). Build #1 stopped at `sast` because the SonarQube scanner could not run its JRE from the `noexec` /tmp of the sandbox; D-43 fixed it (pull request 8).
- 2026-11-11, SonarQube after build #2: the Overview header reads "Version not provided" and shows no new-code period label, although `gates.env` sets `SONAR_PROJECT_VERSION=0.2.0` (D-32). With *Issues in new code* on, the Issues page lists the same two issues as without it, so New Code and Overall Code both hold 1 Security Issue. Carried as VER-01, revisited at 4.5.6.
- IDE-03: SonarQube's server reports nothing on `backend/app/routers/tasks.py` (SV-02) or `backend/app/routers/importer.py` (SV-04). Its only issues are the hashing rule on `security.py` line 17 (Security, High) and an un-awaited promise on `TaskList.tsx` line 48 (Reliability, Medium). Semgrep's rules `sql-fstring-in-text` and `unsafe-yaml-load` detect SV-02 and SV-04, and Bandit (B608, B506) reports them below its blocking level.

**WP4.5.7: what else the baseline found, 2026-11-11**

- **REL-01** (SonarQube `typescript:S9383`, `frontend/src/TaskList.tsx`): the call that starts the debounced search was not marked as ignored on purpose, and the gate "Kairos Secure" failed on the first `main` build. Fixed in code the same day: `void searchLater(...)`, with `frontend/src/search.test.tsx`, which guards the property that makes `void` safe (a failed search becomes an alert on the page, never an unhandled rejection). The gate passed on the next `main` build. The workspace screen of the interface calls the same function and carries the same `void`.
- **Image findings, 22 rows** that no seeded weakness explains, all with a fixed version: 9 in the api image (Debian `apt`, `libapt-pkg7.0`, `zlib1g`; `msgpack` and `urllib3` vendored by pip; `setuptools` 70.3.0) and 13 in the web image (Alpine `brotli-libs`, Critical and in the CISA KEV catalog; `libxslt`, one row in KEV; `libexpat`; `musl`; `curl`; `zlib`). Choice: carried, not fixed and not excepted. **BASE-PY**: the `python` tag was re-pushed on 2026-11-08, so the 7-day rule of D-12 allows its new digest from 2026-11-15. **BASE-WEB**: no `alpine3.24` tag of `nginx-unprivileged` is newer than 2026-10-19. The KEV-listed and Critical rows are never excepted (`docs/process/exemptions.md`). `MODE_IMAGE` stays `report` until both close (**ENF-02**).
- **DEP-01**, read again: `@typescript-eslint/typescript-estree` 8.72.2 still depends on `minimatch` `^10.2.2`; the advisory is fixed in 11.0.1 and later. It stays open and carried.
- **Version notices** on the builds: Trivy 0.76.2 is UPD-05, ESLint 9.39.5 "no longer supported" is UPD-04, and SonarQube offers a newer build than 26.10 (UPD-06).
