# Exception process (WP4.4)

A blocking finding is fixed. When it cannot be fixed now, it is **excepted for a limited time, in writing, by someone other than the person who wants it**, and the exception stops working by itself.

## Who

| Role | Does |
|---|---|
| Developer (requester) | Opens the pull request with the entry and the marker, explains why |
| Security Champion | Approves (`approved_by`); for a Critical finding the Release Manager also approves |
| Release Manager | Approves Critical entries; approves production deployments |

In this project the three roles are held by one person; the process is written for a team and the register records the role that approved.

## What is never excepted

A live secret (rotate it) and a Critical or KEV-listed vulnerability that has a fix (apply it). `check_exceptions.py` refuses such an entry.

## How

1. Write the entry in `security/exceptions.yaml` (the fields are in the file's header): tool, finding, scope, classification (`false_positive`, `not_affected`, `accepted_risk`), severity, justification, compensating controls (required for an accepted risk), requester, approver, creation and expiry dates, and the issue and pull request.
2. Add the **marker** where the tool looks for it, naming the same `EXC-NNNN`: `.trivyignore.yaml` (with `expired_at` equal to the entry's `expires`), `.gitleaksignore`, an `# nosec`, `// eslint-disable-next-line` or `# nosemgrep` comment, a Hadolint `# hadolint ignore=`, or the ZAP rule files. A marker that names no approved entry fails the build; an approved entry with no marker fails it too.
3. Open one pull request with both. `preflight` validates the register.
4. The maximum duration follows severity: Critical 7 days, High 30, Medium 90, Low 180 (`security/policy/gates.env`).

## What happens at the end

Seven days before `expires`, every build lists the entry as a warning. After `expires` an approved entry **fails every build** until it is renewed (a new pull request with a new justification) or the finding is fixed and the entry and marker are removed. The register is the build log's list of what was waived (EV-18).

## Check by hand

```
python3 ci/scripts/check_exceptions.py                       # today's date
python3 ci/scripts/check_exceptions.py --today 2027-01-01    # what the build will say after a date
```
