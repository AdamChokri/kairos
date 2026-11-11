"""SV-07: the lockfile never resolves the vulnerable PyJWT again (plan WP4.5).

Trivy (every push, the pipeline) and Dependabot are the detectors. This test is the offline guard
for the dependency that was seeded: PyJWT 2.3.0 (CVE-2022-29217 and the advisories after it) must
not come back through a merge conflict, a regenerated lockfile or a hurried downgrade. The floor is
the release of the Dependabot pull request that fixed it (#4, 2.15.0). Raising it is a one-line
change; lowering it is a decision, and goes to docs/decisions.md first.
"""

import re
import tomllib
from pathlib import Path

LOCK = Path(__file__).resolve().parents[1] / "uv.lock"
FLOORS = {"pyjwt": (2, 15, 0)}


def locked_version(name: str) -> tuple[int, ...] | None:
    packages = tomllib.loads(LOCK.read_text(encoding="utf-8"))["package"]
    for package in packages:
        if package["name"] == name:
            return tuple(int(part) for part in re.findall(r"\d+", package["version"])[:3])
    return None


def test_the_vulnerable_releases_do_not_come_back() -> None:
    for name, floor in FLOORS.items():
        found = locked_version(name)
        assert found is not None, f"{name} is not in uv.lock"
        assert found >= floor, (
            f"{name} {'.'.join(map(str, found))} is below {'.'.join(map(str, floor))}: "
            "it has known advisories (security/seeded-vulns.md, SV-07)"
        )
