#!/usr/bin/env python3
"""Bandit's JSON report as SARIF 2.1.0 (every issue), and the number of issues that block.

    bandit_to_sarif.py bandit.json --out reports/bandit.sarif --block-severity HIGH --min-confidence MEDIUM

Why this script exists: Bandit writes SARIF only through an optional extra that pulls more packages into the
backend's lockfile; converting its own JSON adds nothing to the dependencies, and Jenkins' Warnings plugin gets
the same SARIF as for every other tool. An issue blocks when its severity and its confidence are both at or above
the thresholds (plan section 4.2: severity HIGH, confidence MEDIUM or better). Prints "blocking: N".
"""

import argparse
import json
import sys
from pathlib import Path

RANK = {"LOW": 1, "MEDIUM": 2, "HIGH": 3}
LEVEL = {"LOW": "note", "MEDIUM": "warning", "HIGH": "error"}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("report", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--block-severity", choices=RANK, default="HIGH")
    parser.add_argument("--min-confidence", choices=RANK, default="MEDIUM")
    args = parser.parse_args()
    try:
        report = json.loads(args.report.read_text(encoding="utf-8"))
        issues = report["results"]
    except (OSError, ValueError, KeyError) as error:
        print(
            f"bandit_to_sarif: {args.report} is not a Bandit JSON report: {error}",
            file=sys.stderr,
        )
        sys.exit(3)

    rules: dict[str, dict] = {}
    results = []
    blocking = 0
    for issue in issues:
        rule_id = issue["test_id"]
        rules.setdefault(
            rule_id,
            {
                "id": rule_id,
                "name": issue.get("test_name", rule_id),
                "helpUri": issue.get("more_info", ""),
                "shortDescription": {"text": issue.get("test_name", rule_id)},
            },
        )
        severity, confidence = (
            issue["issue_severity"].upper(),
            issue["issue_confidence"].upper(),
        )
        if (
            RANK[severity] >= RANK[args.block_severity]
            and RANK[confidence] >= RANK[args.min_confidence]
        ):
            blocking += 1
        results.append(
            {
                "ruleId": rule_id,
                "level": LEVEL[severity],
                "message": {
                    "text": f"{issue['issue_text']} (severity {severity}, confidence {confidence}, {issue.get('issue_cwe', {}).get('id', '?') and 'CWE-' + str(issue['issue_cwe']['id'])})"
                },
                "locations": [
                    {
                        "physicalLocation": {
                            "artifactLocation": {
                                "uri": issue["filename"]
                                .removeprefix("/src/")
                                .removeprefix("./")
                            },
                            "region": {"startLine": issue["line_number"]},
                        }
                    }
                ],
            }
        )
    sarif = {
        "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
        "version": "2.1.0",
        "runs": [
            {
                "tool": {"driver": {"name": "Bandit", "rules": list(rules.values())}},
                "results": results,
            }
        ],
    }
    args.out.write_text(json.dumps(sarif, indent=2) + "\n", encoding="utf-8")
    print(f"bandit_to_sarif: {len(results)} issue(s) written to {args.out}")
    print(f"blocking: {blocking}")


if __name__ == "__main__":
    main()
