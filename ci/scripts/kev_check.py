#!/usr/bin/env python3
"""The Trivy gate of plan section 4.1/4.2: severity, fix availability, and the CISA KEV catalog.

    kev_check.py --name sca --trivy reports/trivy-fs-backend.json [...] [--cache /cache/kev.json]
                 [--kev-file FILE] [--out reports/gate-sca.json]

A finding blocks when
  - its severity is in TRIVY_BLOCK_ALWAYS (default CRITICAL), or
  - its severity is in TRIVY_BLOCK_IF_FIXED (default HIGH) and a fixed version exists, or
  - its CVE is in CISA's Known Exploited Vulnerabilities catalog (TRIVY_BLOCK_KEV), whatever its severity, or
  - it is a secret found in an image (TRIVY_IMAGE_BLOCK_SECRETS).
Trivy's .trivyignore.yaml has already removed approved exceptions from the report, so an exception covers a
KEV finding too. The catalog is downloaded at most once a day into --cache; when CISA cannot be reached, a copy
younger than KEV_MAX_AGE_DAYS is used, and anything older is a tool error, because a stale list would let a
newly exploited CVE through (fail closed).

Exit code: 0 nothing blocks, 1 something blocks, 3 the check itself could not run. Reads the thresholds from the
environment (security/policy/gates.env, sourced by the calling script).
"""

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

KEV_URL = "https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json"
DAY = 86400


def fail(message: str) -> None:
    print(f"kev_check: {message}", file=sys.stderr)
    sys.exit(3)


def load_kev(
    cache: Path | None, kev_file: Path | None, max_age_days: int
) -> tuple[set[str], str]:
    """Returns the set of CVE ids in the catalog and a sentence saying where it came from."""
    if kev_file:
        return ids_of(kev_file), f"{kev_file} (given)"
    if cache is None:
        fail("--cache or --kev-file is needed")
    age = (time.time() - cache.stat().st_mtime) if cache.exists() else None
    if age is None or age > DAY:
        try:
            with urllib.request.urlopen(KEV_URL, timeout=30) as response:
                data = response.read()
            json.loads(
                data
            )  # refuse anything that is not JSON before it replaces the cache
            cache.parent.mkdir(parents=True, exist_ok=True)
            tmp = cache.with_suffix(".tmp")
            tmp.write_bytes(data)
            tmp.replace(cache)
            return ids_of(cache), "downloaded from CISA now"
        except (urllib.error.URLError, OSError, ValueError) as error:
            if age is None or age > max_age_days * DAY:
                fail(
                    f"CISA's KEV feed cannot be fetched ({error}) and there is no copy younger than {max_age_days} days"
                )
            print(
                f"kev_check: CISA cannot be reached ({error}); using the cached copy, {age / DAY:.1f} days old",
                file=sys.stderr,
            )
            return ids_of(cache), f"cache, {age / DAY:.1f} days old (CISA unreachable)"
    return ids_of(cache), f"cache, {age / DAY:.1f} days old"


def ids_of(path: Path) -> set[str]:
    try:
        catalog = json.loads(path.read_text(encoding="utf-8"))
        return {entry["cveID"] for entry in catalog["vulnerabilities"]}
    except (OSError, ValueError, KeyError, TypeError) as error:
        fail(f"{path} is not a KEV catalog: {error}")
        return set()


def listed(name: str, default: str) -> set[str]:
    return {
        item.strip().upper()
        for item in os.environ.get(name, default).split(",")
        if item.strip()
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--name", required=True)
    parser.add_argument("--trivy", nargs="+", required=True, type=Path)
    parser.add_argument("--cache", type=Path)
    parser.add_argument("--kev-file", type=Path)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()

    always = listed("TRIVY_BLOCK_ALWAYS", "CRITICAL")
    if_fixed = listed("TRIVY_BLOCK_IF_FIXED", "HIGH")
    use_kev = os.environ.get("TRIVY_BLOCK_KEV", "true").lower() == "true"
    block_secrets = (
        os.environ.get("TRIVY_IMAGE_BLOCK_SECRETS", "true").lower() == "true"
    )
    max_age = int(os.environ.get("KEV_MAX_AGE_DAYS", "7"))

    kev: set[str] = set()
    kev_source = "not used (TRIVY_BLOCK_KEV is false)"
    if use_kev:
        kev, kev_source = load_kev(args.cache, args.kev_file, max_age)

    blocking: list[dict] = []
    seen = 0
    for path in args.trivy:
        try:
            document = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError) as error:
            fail(f"{path} is not a Trivy JSON report: {error}")
        for result in document.get("Results") or []:
            target = result.get("Target", "?")
            for vuln in result.get("Vulnerabilities") or []:
                seen += 1
                severity = (vuln.get("Severity") or "UNKNOWN").upper()
                fixed = vuln.get("FixedVersion") or ""
                cve = vuln.get("VulnerabilityID", "?")
                reasons = []
                if severity in always:
                    reasons.append(f"{severity} always blocks")
                if severity in if_fixed and fixed:
                    reasons.append(f"{severity} with a fix ({fixed})")
                if use_kev and cve in kev:
                    reasons.append("in the CISA KEV catalog")
                if reasons:
                    blocking.append(
                        {
                            "id": cve,
                            "package": vuln.get("PkgName"),
                            "installed": vuln.get("InstalledVersion"),
                            "fixed": fixed,
                            "severity": severity,
                            "target": target,
                            "reasons": reasons,
                        }
                    )
            if block_secrets:
                for secret in result.get("Secrets") or []:
                    seen += 1
                    blocking.append(
                        {
                            "id": secret.get("RuleID", "secret"),
                            "package": secret.get("Title", ""),
                            "installed": "",
                            "fixed": "",
                            "severity": (secret.get("Severity") or "").upper(),
                            "target": target,
                            "reasons": ["a secret in the image"],
                        }
                    )

    summary = {
        "gate": args.name,
        "findings_seen": seen,
        "blocking": len(blocking),
        "kev_catalog": kev_source,
        "kev_entries": len(kev),
        "details": blocking,
    }
    if args.out:
        args.out.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    for item in blocking[:50]:
        print(
            f"BLOCKS  {item['id']} {item['severity']:8} {item['package']} {item['installed']}  "
            f"({'; '.join(item['reasons'])})  [{item['target']}]"
        )
    if len(blocking) > 50:
        print(f"... and {len(blocking) - 50} more, see {args.out}")
    print(f"kev_check[{args.name}]: {seen} finding(s) read, KEV catalog: {kev_source}")
    print(f"blocking: {len(blocking)}")
    sys.exit(1 if blocking else 0)


if __name__ == "__main__":
    main()
