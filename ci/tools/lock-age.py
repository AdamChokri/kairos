#!/usr/bin/env python3
"""ci/tools/lock-age.py - the 7-day rule (decision D-12) applied to what a lockfile adds or changes.

    python3 ci/tools/lock-age.py [--min-days 7] [--base REV] backend/uv.lock frontend/package-lock.json

With --base REV, only the packages that are new or at another version than in `git show REV:FILE` are
checked (what a pull request brings in); without it, every package of the file. Each one is looked up on the
registry (PyPI for uv.lock, the npm registry for package-lock.json) and its upload date is read from there,
never judged from the version number. A package younger than --min-days is reported as YOUNG and the exit
code is 1; a lookup that failed is reported as NOT VERIFIED and the exit code is 2 (the rule could not be
checked, which is not a pass). Needs Python 3.11+ and network access to pypi.org and registry.npmjs.org.
Exit code 0: every checked package is old enough.
"""

import argparse
import json
import subprocess
import sys
import tomllib
import urllib.error
import urllib.parse
import urllib.request
from datetime import UTC, datetime
from pathlib import Path


def uv_packages(text: str) -> dict[str, str]:
    found = {}
    for package in tomllib.loads(text).get("package", []):
        source = package.get("source", {})
        if (
            "registry" in source
        ):  # a virtual (the project itself) or editable source has none
            found[package["name"]] = package["version"]
    return found


def npm_packages(text: str) -> dict[str, str]:
    found = {}
    for path, package in json.loads(text).get("packages", {}).items():
        if (
            path.startswith("node_modules/")
            and not package.get("link")
            and "version" in package
        ):
            found[path.rsplit("node_modules/", 1)[1]] = package["version"]
    return found


def read_packages(kind: str, text: str) -> dict[str, str]:
    return uv_packages(text) if kind == "uv" else npm_packages(text)


def fetch_json(url: str) -> dict:
    request = urllib.request.Request(url, headers={"User-Agent": "kairos-lock-age"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def upload_date(kind: str, name: str, version: str) -> datetime:
    if kind == "uv":
        data = fetch_json(f"https://pypi.org/pypi/{name}/{version}/json")
        stamps = [item["upload_time_iso_8601"] for item in data["urls"]]
    else:
        data = fetch_json(
            f"https://registry.npmjs.org/{urllib.parse.quote(name, safe='@')}"
        )
        stamps = [data["time"][version]]
    return min(datetime.fromisoformat(stamp) for stamp in stamps)


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawTextHelpFormatter
    )
    parser.add_argument("files", nargs="+")
    parser.add_argument("--min-days", type=int, default=7)
    parser.add_argument(
        "--base", help="a Git revision: check only what differs from the file there"
    )
    args = parser.parse_args()

    now = datetime.now(UTC)
    young = unverified = checked = 0
    for name in args.files:
        kind = "uv" if name.endswith("uv.lock") else "npm"
        packages = read_packages(kind, Path(name).read_text(encoding="utf-8"))
        before: dict[str, str] = {}
        if args.base:
            shown = subprocess.run(
                ["git", "show", f"{args.base}:./{name}"],
                capture_output=True,
                text=True,
                check=False,
            )
            if shown.returncode == 0:
                before = read_packages(kind, shown.stdout)
        for package, version in sorted(packages.items()):
            if before.get(package) == version:
                continue
            checked += 1
            try:
                date = upload_date(kind, package, version)
            except (urllib.error.URLError, KeyError, ValueError, TimeoutError) as error:
                print(
                    f"NOT VERIFIED  {package} {version}: the registry did not answer ({error})"
                )
                unverified += 1
                continue
            days = (now - date).days
            if days < args.min_days:
                print(
                    f"YOUNG         {package} {version}  {date:%Y-%m-%d}  {days} day(s): D-12 says wait"
                )
                young += 1
            else:
                print(
                    f"ok            {package} {version}  {date:%Y-%m-%d}  {days} days"
                )
    print(
        f"lock-age: {checked} package(s) checked, {young} younger than {args.min_days} days, {unverified} not verified"
    )
    return 1 if young else 2 if unverified else 0


if __name__ == "__main__":
    sys.exit(main())
