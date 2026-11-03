# Security policy

## Reporting a vulnerability

Please report vulnerabilities privately through GitHub's **private vulnerability reporting**: open the repository's **Security** tab and choose **Report a vulnerability**. Do not open a public issue.

You will get an answer within 7 days. This is a student project run in a closed lab; there is no bug bounty.

## Scope

Kairos deliberately contains **seeded weaknesses** for teaching purposes, listed in `security/seeded-vulns.md` once the application exists (plan section 5). Reports about those are welcome but expected.

## Secrets

No real credential is ever committed: secret scanning with push protection is enabled, and every secret lives in OpenBao. If you find something that looks like a live secret in this repository, report it privately as above.
