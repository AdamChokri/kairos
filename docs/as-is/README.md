# The as-is state (P2)

The brief's first technical task is to analyse an existing pipeline. This project starts from nothing, so P2 builds what a typical team has — a small application and a working but naive pipeline — and this folder analyses it, so that every later control has a "before".

| File | What it answers |
|---|---|
| [`pipeline-map.md`](pipeline-map.md) | What runs, in which order, with which credentials, and who can start it |
| [`tools-inventory.md`](tools-inventory.md) | Every tool the as-is flow touches, with its version and where it is pinned (or not) |
| [`weaknesses.md`](weaknesses.md) | What is wrong, by the brief's categories and the OWASP CI/CD Top 10, each with an ID and the planned control |
| [`threat-model.md`](threat-model.md) | Two data-flow diagrams and the STRIDE table of plan section 3.5, checked against the real flows |
| [`measurements.md`](measurements.md) | The numbers that exist before any control: pipeline duration, image sizes, the Jenkins security settings, the hosts' score |

The application's own weaknesses (SV-01 to SV-09) are in [`../../security/seeded-vulns.md`](../../security/seeded-vulns.md); the pipeline and host weaknesses (SV-10, SV-11) are analysed here, as W-01 to W-14.

**State recorded:** the tag `v0.1-as-is` marks the commit that was deployed. `ci/as-is/Jenkinsfile` is kept: WP8.1 runs it again on purpose, to show the hardened platform refusing it.
