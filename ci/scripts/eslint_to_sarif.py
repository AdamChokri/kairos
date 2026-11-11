#!/usr/bin/env python3
"""ESLint's JSON report as SARIF 2.1.0, with paths relative to the repository.

    eslint_to_sarif.py eslint.json --out reports/eslint.sarif [--prefix frontend/] [--strip /src/frontend/]

Why this script exists (erratum E-42): the plan names @microsoft/eslint-formatter-sarif, but its 3.1.0 release
(the newest, April 2024) lists `eslint ^8.9.0` as a *dependency* (a second, end-of-life ESLint inside the frontend's
lockfile) and `jschardet` at the version `latest` (whatever is published at install time). Converting ESLint's own
JSON adds no package at all, and Jenkins' Warnings plugin still reads SARIF. An ESLint severity of 2 is an error,
1 a warning; a fatal parse error is an error. Prints "results: N".
"""

import argparse
import json
import sys
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("report", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument(
        "--prefix", default="frontend/", help="added in front of each path"
    )
    parser.add_argument(
        "--strip", default="/src/frontend/", help="removed from the start of each path"
    )
    args = parser.parse_args()
    try:
        files = json.loads(args.report.read_text(encoding="utf-8"))
        if not isinstance(files, list):
            raise TypeError("expected a list of files")
    except (OSError, ValueError, TypeError) as error:
        print(
            f"eslint_to_sarif: {args.report} is not an ESLint JSON report: {error}",
            file=sys.stderr,
        )
        sys.exit(3)

    rules: dict[str, dict] = {}
    results = []
    for entry in files:
        path = str(entry.get("filePath", "?")).removeprefix(args.strip)
        for message in entry.get("messages") or []:
            rule_id = message.get("ruleId") or "eslint-fatal"
            rules.setdefault(
                rule_id,
                {"id": rule_id, "name": rule_id, "shortDescription": {"text": rule_id}},
            )
            fatal = bool(message.get("fatal"))
            level = "error" if fatal or message.get("severity") == 2 else "warning"
            region = {
                "startLine": message.get("line", 1),
                "startColumn": message.get("column", 1),
            }
            if message.get("endLine"):
                region["endLine"] = message["endLine"]
            if message.get("endColumn"):
                region["endColumn"] = message["endColumn"]
            results.append(
                {
                    "ruleId": rule_id,
                    "level": level,
                    "message": {"text": message.get("message", "")},
                    "locations": [
                        {
                            "physicalLocation": {
                                "artifactLocation": {"uri": args.prefix + path},
                                "region": region,
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
                "tool": {"driver": {"name": "ESLint", "rules": list(rules.values())}},
                "results": results,
            }
        ],
    }
    args.out.write_text(json.dumps(sarif, indent=2) + "\n", encoding="utf-8")
    print(f"eslint_to_sarif: {len(results)} result(s) written to {args.out}")


if __name__ == "__main__":
    main()
