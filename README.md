# Kairos

Kairos is a small task manager — FastAPI, React and PostgreSQL — built as the subject of a DevSecOps project: a Jenkins pipeline that secures it from the developer's editor to production, with every control measured before and after.

> **Status:** P1 — the lab is being built. The application arrives in P2.

## What is here

| Path | What it holds |
|---|---|
| `docs/plan/PROJECT-PLAN.md` | The project plan: decisions, architecture, gates, phases, evidence |
| `docs/plan/ERRATA.md` | Corrections to the plan found while implementing it |
| `docs/decisions.md` | The decision log (D-NN entries) |
| `docs/lab/` | The lab's capacity, network and reachability records |
| `docs/runbooks/` | Operating procedures, and the account inventory (names only, never values) |
| `infra/lab/` | The lab description (`hosts.csv`, `vms.csv`) and the scripts that build and power it |
| `infra/cloud-init/` | First-boot configuration of the VMs |
| `infra/pki/` | The lab CA certificate and the scripts that issue from it |
| `infra/openbao/` | OpenBao policies, AppRoles and the scripts that apply and test them |
| `infra/ansible/` | The configuration of every VM |
| `ci/` | The Jenkins controller image and the pipeline tooling |

## Lab power

From WSL2 on the workstation, at the repository root:

```bash
make lab-up       # checks both hosts, starts the VMs in order, asks for the OpenBao unseal key shares
make lab-status   # every VM's state, its SSH port and OpenBao's seal status
make lab-down     # graceful shutdown in reverse order
```

## Security

The repository is public. It never holds a real credential: every secret lives in OpenBao. To report a vulnerability, see [SECURITY.md](SECURITY.md).

## Licence

[Apache License 2.0](LICENSE).
