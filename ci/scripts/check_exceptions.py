#!/usr/bin/env python3
"""Validates the exception register of plan section 4.3 (WP4.4). Run in `preflight`; a failure fails the build.

    check_exceptions.py [--root DIR] [--today YYYY-MM-DD] [--sonar URL]

Checks, for security/exceptions.yaml:
  - the schema: the fields, the value sets, the EXC-NNNN id (unique), the dates;
  - the approver role: an approved entry names the Security Champion, and a Critical one also the Release Manager
    and at least one compensating control (an accepted risk needs one at any severity);
  - the duration: expires minus created is at most EXC_MAX_DAYS_<SEVERITY> (security/policy/gates.env);
  - the expiry: an approved entry past its date fails every build until it is renewed or the finding is fixed;
    one that ends within EXC_WARN_BEFORE_DAYS is listed as a warning;
  - markers and entries agree: every EXC-NNNN in a suppression marker (.trivyignore.yaml, .gitleaksignore, source
    files, Dockerfiles, the ZAP rule files) names an approved entry, and every approved entry has a marker (SonarQube
    entries have an issue key instead, confirmed with --sonar on the main lane, where the analysis token exists);
  - a Trivy marker's expired_at equals the entry's expires (Trivy enforces its own date).
Prints the exceptions in force, which is the build log's list of what was waived. Exit code 0 ok, 1 any problem.
Needs Python 3 with PyYAML (Ubuntu's python3-yaml on the build agent) and nothing else.
"""

import argparse
import base64
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import date
from pathlib import Path

import yaml

TOOLS = {
    "gitleaks",
    "semgrep",
    "bandit",
    "eslint",
    "hadolint",
    "trivy-fs",
    "trivy-image",
    "trivy-config",
    "zap",
    "sonarqube",
}
STATUSES = {"proposed", "approved", "expired", "revoked"}
CLASSES = {"false_positive", "not_affected", "accepted_risk"}
SEVERITIES = ("critical", "high", "medium", "low")
REQUIRED = (
    "id",
    "status",
    "tool",
    "finding",
    "scope",
    "classification",
    "severity",
    "justification",
    "compensating_controls",
    "requested_by",
    "approved_by",
    "created",
    "expires",
    "issue",
    "pull_request",
)
ID = re.compile(r"^EXC-\d{4}$")
MARKER = re.compile(r"EXC-\d{4}")
ISSUE_URL = re.compile(r"^https://github\.com/AdamChokri/kairos/issues/\d+$")
PULL_URL = re.compile(r"^https://github\.com/AdamChokri/kairos/pull/\d+$")
# Where suppression markers live. Documentation may mention any EXC id freely, so it is not scanned.
MARKER_GLOBS = (
    ".trivyignore.yaml",
    ".gitleaksignore",
    "backend/**/*.py",
    "frontend/src/**/*.ts",
    "frontend/src/**/*.tsx",
    "frontend/*.js",
    "**/Dockerfile*",
    "security/policy/zap/*.tsv",
    "deploy/*.yaml",
)
SKIP_PARTS = {".venv", "node_modules", "reports", ".git", "tests"}


def as_date(value) -> date | None:
    if isinstance(value, date):
        return value
    try:
        return date.fromisoformat(str(value))
    except ValueError:
        return None


def limits() -> dict[str, int]:
    defaults = {"critical": 7, "high": 30, "medium": 90, "low": 180}
    return {
        name: int(os.environ.get(f"EXC_MAX_DAYS_{name.upper()}", default))
        for name, default in defaults.items()
    }


def find_markers(root: Path) -> dict[str, list[str]]:
    """EXC id -> the files that carry it as a suppression marker."""
    found: dict[str, list[str]] = {}
    seen: set[Path] = set()
    for pattern in MARKER_GLOBS:
        for path in root.glob(pattern):
            if (
                not path.is_file()
                or path in seen
                or SKIP_PARTS & set(path.relative_to(root).parts)
            ):
                continue
            seen.add(path)
            if path.name == ".trivyignore.yaml":
                continue  # structured: its statements are read below, a comment is not a marker
            for exc in set(
                MARKER.findall(path.read_text(encoding="utf-8", errors="replace"))
            ):
                found.setdefault(exc, []).append(str(path.relative_to(root)))
    for exc in trivy_markers(root):
        if exc:
            found.setdefault(exc, []).append(".trivyignore.yaml")
    return found


def trivy_markers(root: Path) -> dict[str, set[date]]:
    """EXC id -> the expired_at dates written in .trivyignore.yaml."""
    path = root / ".trivyignore.yaml"
    result: dict[str, set[date]] = {}
    if not path.exists():
        return result
    document = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    for section in ("vulnerabilities", "misconfigurations", "secrets", "licenses"):
        for entry in document.get(section) or []:
            ids = MARKER.findall(str(entry.get("statement", "")))
            if not ids:
                result.setdefault("", set())  # an entry with no EXC id at all
            for exc in ids:
                result.setdefault(exc, set())
                expires = as_date(entry.get("expired_at"))
                if expires:
                    result[exc].add(expires)
    return result


def check_sonar(entries: list[dict], url: str) -> list[str]:
    problems = []
    token = os.environ.get("SONAR_TOKEN", "")
    if not token:
        return ["--sonar needs SONAR_TOKEN in the environment"]
    auth = base64.b64encode(f"{token}:".encode()).decode()
    for entry in entries:
        key = entry.get("sonar_issue")
        if not key:
            problems.append(
                f"{entry['id']}: a SonarQube exception needs the field sonar_issue (the issue key)"
            )
            continue
        request = urllib.request.Request(
            f"{url}/api/issues/search?issues={urllib.parse.quote(str(key))}&additionalFields=comments",
            headers={"Authorization": f"Basic {auth}"},
        )
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                issues = json.load(response).get("issues", [])
        except (urllib.error.URLError, OSError, ValueError) as error:
            problems.append(
                f"{entry['id']}: SonarQube cannot be asked about {key}: {error}"
            )
            continue
        if not issues:
            problems.append(f"{entry['id']}: SonarQube has no issue {key}")
            continue
        issue = issues[0]
        status = str(issue.get("issueStatus") or issue.get("resolution") or "")
        if status.upper() not in {"ACCEPTED", "FALSE_POSITIVE", "WONTFIX"}:
            problems.append(
                f"{entry['id']}: issue {key} is {status or 'open'} in SonarQube, not Accepted or False positive"
            )
        if entry["id"] not in json.dumps(issue.get("comments", [])):
            problems.append(
                f"{entry['id']}: no comment of issue {key} names {entry['id']}"
            )
    return problems


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--root", type=Path, default=Path(__file__).resolve().parents[2]
    )
    parser.add_argument("--today", type=date.fromisoformat, default=date.today())
    parser.add_argument("--sonar", metavar="URL")
    args = parser.parse_args()
    root, today = args.root, args.today
    warn_days = int(os.environ.get("EXC_WARN_BEFORE_DAYS", "7"))
    max_days = limits()

    register = root / "security" / "exceptions.yaml"
    try:
        document = yaml.safe_load(register.read_text(encoding="utf-8"))
    except (OSError, yaml.YAMLError) as error:
        sys.exit(f"check_exceptions: {register} cannot be read: {error}")
    if not isinstance(document, dict) or not isinstance(
        document.get("exceptions"), list
    ):
        sys.exit(
            "check_exceptions: security/exceptions.yaml must hold a list under the key 'exceptions'"
        )
    entries = document["exceptions"]

    problems: list[str] = []
    warnings: list[str] = []
    seen_ids: set[str] = set()
    in_force: list[dict] = []
    for index, entry in enumerate(entries, 1):
        if not isinstance(entry, dict):
            problems.append(f"entry {index}: not a mapping")
            continue
        name = str(entry.get("id", f"entry {index}"))
        missing = [
            field
            for field in REQUIRED
            if entry.get(field) in (None, "", [])
            and not (
                field == "compensating_controls"
                and entry.get("classification") != "accepted_risk"
                and entry.get("severity") != "critical"
            )
        ]
        if entry.get("status") == "proposed":
            missing = [
                field
                for field in missing
                if field not in ("approved_by", "pull_request")
            ]
        if missing:
            problems.append(f"{name}: missing field(s) {', '.join(missing)}")
        if not ID.match(name):
            problems.append(f"{name}: the id must look like EXC-0001")
        if name in seen_ids:
            problems.append(f"{name}: the id is used twice")
        seen_ids.add(name)
        if entry.get("status") not in STATUSES:
            problems.append(f"{name}: status must be one of {sorted(STATUSES)}")
        if entry.get("tool") not in TOOLS:
            problems.append(f"{name}: tool must be one of {sorted(TOOLS)}")
        if entry.get("classification") not in CLASSES:
            problems.append(f"{name}: classification must be one of {sorted(CLASSES)}")
        severity = entry.get("severity")
        if severity not in SEVERITIES:
            problems.append(f"{name}: severity must be one of {list(SEVERITIES)}")
        created, expires = as_date(entry.get("created")), as_date(entry.get("expires"))
        if created is None or expires is None:
            problems.append(f"{name}: created and expires must be dates (YYYY-MM-DD)")
        elif severity in max_days and (expires - created).days > max_days[severity]:
            problems.append(
                f"{name}: lasts {(expires - created).days} days, the maximum for {severity} is {max_days[severity]}"
            )
        if entry.get("issue") and not ISSUE_URL.match(str(entry["issue"])):
            problems.append(
                f"{name}: issue must be a URL of an issue of AdamChokri/kairos"
            )
        if entry.get("pull_request") and not PULL_URL.match(str(entry["pull_request"])):
            problems.append(
                f"{name}: pull_request must be a URL of a pull request of AdamChokri/kairos"
            )
        if entry.get("status") == "approved":
            approver = str(entry.get("approved_by", "")).lower()
            if "security-champion" not in approver:
                problems.append(
                    f"{name}: approved_by must name the security-champion role"
                )
            if severity == "critical" and "release-manager" not in approver:
                problems.append(
                    f"{name}: a Critical exception also needs the release-manager's approval"
                )
            if expires and expires < today:
                problems.append(
                    f"{name}: EXPIRED on {expires}: renew it (new review, new expiry) or fix the finding"
                )
            else:
                in_force.append(entry)
                if expires and (expires - today).days <= warn_days:
                    warnings.append(
                        f"{name}: ends on {expires}, in {(expires - today).days} day(s)"
                    )

    markers = find_markers(root)
    trivy = trivy_markers(root)
    by_id = {str(e.get("id")): e for e in entries if isinstance(e, dict)}
    for exc, files in sorted(markers.items()):
        entry = by_id.get(exc)
        if entry is None:
            problems.append(
                f"{exc}: used in {', '.join(files)} but not in the register"
            )
        elif entry.get("status") != "approved":
            problems.append(
                f"{exc}: used in {', '.join(files)} but its status is {entry.get('status')}"
            )
    if "" in trivy:
        problems.append(".trivyignore.yaml: an entry whose statement names no EXC-NNNN")
    for exc, dates in trivy.items():
        entry = by_id.get(exc)
        if (
            entry
            and entry.get("status") == "approved"
            and dates
            and as_date(entry.get("expires")) not in dates
        ):
            problems.append(
                f"{exc}: .trivyignore.yaml says expired_at {sorted(map(str, dates))}, the register says {entry.get('expires')}"
            )
    for entry in in_force:
        if entry.get("tool") != "sonarqube" and str(entry["id"]) not in markers:
            problems.append(
                f"{entry['id']}: approved, but no suppression marker carries it"
            )
    if args.sonar:
        problems += check_sonar(
            [e for e in in_force if e.get("tool") == "sonarqube"],
            args.sonar.rstrip("/"),
        )

    print(f"Exceptions in force on {today}: {len(in_force)}")
    for entry in in_force:
        expires = as_date(entry["expires"])
        left = (expires - today).days if expires else "?"
        print(
            f"  {entry['id']}  {entry['tool']:13} {entry['severity']:8} {entry['finding']}  until {expires} ({left} day(s))"
        )
    for line in warnings:
        print(f"WARN  {line}")
    for line in problems:
        print(f"FAIL  {line}")
    if problems:
        print(f"check_exceptions: {len(problems)} problem(s)")
        sys.exit(1)
    print("check_exceptions: the register and the markers agree")


if __name__ == "__main__":
    main()
