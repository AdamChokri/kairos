#!/usr/bin/env python3
"""Counts the results of SARIF files by level, and prints the number that blocks.

    sarif_gate.py --level error FILE [FILE...]

`--level` is the lowest level that blocks: error blocks only errors, warning blocks warnings and errors, note
blocks everything. A missing file is an error (exit 3): a tool that wrote no report must not pass. Exit code 0
always when the files can be read; the calling script turns "blocking: N" into a verdict (ci/scripts/lib.sh).
"""

import argparse
import json
import sys
from pathlib import Path

ORDER = {"none": 0, "note": 1, "warning": 2, "error": 3}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--level", choices=["note", "warning", "error"], default="error"
    )
    parser.add_argument("files", nargs="+", type=Path)
    args = parser.parse_args()
    threshold = ORDER[args.level]
    total = blocking = 0
    for path in args.files:
        try:
            document = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError) as error:
            print(f"sarif_gate: {path} cannot be read: {error}", file=sys.stderr)
            sys.exit(3)
        for run in document.get("runs") or []:
            rules = {
                rule.get("id"): rule
                for rule in (run.get("tool", {}).get("driver", {}).get("rules") or [])
            }
            for result in run.get("results") or []:
                total += 1
                level = result.get("level")
                if (
                    level is None
                ):  # SARIF: the rule's default level, and "warning" when it names none
                    rule = rules.get(result.get("ruleId"), {})
                    level = (rule.get("defaultConfiguration") or {}).get(
                        "level", "warning"
                    )
                if ORDER.get(level, 2) >= threshold:
                    blocking += 1
                    location = (result.get("locations") or [{}])[0].get(
                        "physicalLocation", {}
                    )
                    where = location.get("artifactLocation", {}).get("uri", "?")
                    line = location.get("region", {}).get("startLine", "?")
                    print(f"BLOCKS  {result.get('ruleId', '?')}  {where}:{line}")
    print(f"sarif_gate: {total} result(s) in {len(args.files)} file(s)")
    print(f"blocking: {blocking}")


if __name__ == "__main__":
    main()
