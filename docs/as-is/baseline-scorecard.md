# Baseline scorecard

What every control of the pipeline reports on the Kairos v0 code **as it was seeded**: the first builds of `main` after the controls went live, before any weakness was fixed (plan WP4.2). It is the first column of the detection matrix of WP8.1. The numbers are copied from the build's reports (`reports/` in the build's artifacts) and never rounded or estimated.

Build: `kairos` / `main` #__ , commit `________`, date ________. All controls in `report` mode.

## Static controls

| Control | Tool | Findings at or above the threshold | Findings in all | Threshold | Seeded weakness it shows |
|---|---|---|---|---|---|
| secrets_scan | Gitleaks (files) | | | any | SV-01 |
| secrets_scan | Gitleaks (history) | | | any | SV-01 |
| sast | Semgrep | | | ERROR | SV-01, SV-02, SV-03, SV-04 |
| sast | Bandit | | | HIGH, confidence MEDIUM or better | SV-05 |
| sast | ESLint | | | error | SV-03 |
| sast | SonarQube | | | gate "Kairos Secure" | |
| scan_dependencies | Trivy, `backend/uv.lock` | | | Critical, High with a fix, KEV | SV-07 |
| scan_dependencies | Trivy, `frontend/package-lock.json` | | | Critical, High with a fix, KEV | SV-07 |
| iac_scan | Hadolint | | | error | SV-09 |
| iac_scan | Trivy config | | | High, Critical | SV-09 |
| docker_scan | Trivy image, `kairos-api` | | | Critical, High with a fix, KEV, secrets | SV-09 |
| docker_scan | Trivy image, `kairos-web` | | | Critical, High with a fix, KEV, secrets | SV-09 |

## Dynamic controls (WP5.1)

Filled in P8 from `docs/results/dast-before.txt` (the gate's own lines: `<scan>: FAIL a, WARN b, INFO c, IGNORE d`).

| Control | Target | FAIL | WARN | INFO | Report |
|---|---|---|---|---|---|
| dast, ZAP baseline | `http://staging.kairos.lab:5173` | | | | |
| dast, ZAP API scan | `http://staging.kairos.lab:8000/openapi.json` | | | | |

## Notes

What a tool found that no seeded weakness explains, and what was done about it (a fix, or a tracked item), is written here with the date.
