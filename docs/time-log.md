# Time log

One line per working session (plan section 0.4): it drives the checkpoints of section 11.2 and the report's lessons learned.

| Date | Work package(s) | Hours | Notes |
|---|---|---|---|
| 2026-11-03 | WP0.1 (complete), WP0.2 to 0.2.3 | ≈ 3 (estimate) | Repository, ruleset, accounts; H-01 (E-15), E-16; PM-01 |
| 2026-11-04 | WP0.2 (complete, P0 done), WP1.1, WP1.2, WP1.3, WP1.4 (complete) | ≈ 3 (estimate) | D-22 and CAP-01/02; E-17 to E-27; PM-02; V-01 passed; OpenBao initialized, AppRoles proven (30/30); Jenkins 2.580.2 with both agents, GitHub App connected |
| 2026-11-05 | WP1.4 (committed), WP1.5, WP1.6 (complete) | ≈ 3 (estimate) | D-23 and E-28 (Gitleaks and plugin pins); SonarQube 26.10 in MQR mode, gate "Kairos Secure", first analysis passed; SQ-01 fixed (controller image files owned by root); CAP-03 closed, NC-01 opened; Wazuh 4.14.9 with three agents, rule 5712 alert in Slack, SCA baseline 47 %; UPD-01 to UPD-03 recorded |
| 2026-11-06 | WP2.1, WP2.2, WP2.3 | ≈ 3 (estimate) | D-25, D-26, D-28, D-30; E-30 to E-33, E-39 to E-41; as-is job green on staging and production; W-01 to W-14 checked against the lab; NODE-01, DEP-01, UPD-05 opened |
| 2026-11-06 | P3 start (3.0), WP3.1 (begun) | ≈ 3 (estimate) | P3 started after the P2 merge; IDE profile: six extensions installed in WSL mode by exact id, versions checked against the 7-day rule |
| 2026-11-07 | WP3.1 (complete), WP3.2, WP3.3 | ≈ 3 (estimate) | D-27, D-29, D-31; E-34 to E-38; hooks installed and proven by the two refusals (EV-04, EV-05); five educational rules tested; IDE-01 to IDE-03 opened |
| 2026-11-11 | WP4.1 | ≈ 3 (estimate) | Jenkins accounts and matrix, Audit Trail, Resource Root URL, three AppRole credentials, Slack, job `kairos`; Docker Hub token `kairos-ci-rw` (as-is token revoked); two deploy key pairs in OpenBao |
| 2026-11-11 | WP4.2 to WP4.4 | ≈ 3 (estimate) | The CI pull request; E-42 to E-44, E-53, D-32, D-36; SonarQube new code set; DHT-01 if the token is account-wide |
| 2026-11-11 | WP4.5 | ≈ 3 (estimate) | SV-01 to SV-05, SV-07 and SV-09 fixed, each with its regression test (red first); REL-01 fixed; static controls in enforce mode except the image gate (ENF-02); D-33; DEP-01 re-read, still open |
| 2026-11-11 | WP4.6, WP4.7 (begun) | ≈ 3 (estimate) | HOOK-01 closed (D-34); required check in the ruleset; Dependabot version updates with a 7-day cooldown |
| 2026-11-12 | WP4.7 | ≈ 3 (estimate) | Threat model T-13 to T-15 and two Semgrep rules; Assist v1 refused by the ESLint hook; SV-12 to SV-14 red tests and fixes, pushed once; D-35 |
| 2026-11-12 | UI-01 | ≈ 1.5 (estimate) | A designed interface, Graphite: one stylesheet, the font as a file, the states of a finished product, 30 frontend tests; E-50, D-40 |
| 2026-11-12 | WP4.7 and UI-01 (closed) | ≈ 0.5 (estimate) | SonarQube's reliability condition fixed in code, no threshold lowered (the autofocus attribute of the New task field); the gate passes on main #13, which has Assist and Graphite (76 backend and 31 frontend tests); DEP-ALERTS closed: GitHub lists one open alert, #33 (DEP-01) |
