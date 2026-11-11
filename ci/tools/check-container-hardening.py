#!/usr/bin/env python3
"""ci/tools/check-container-hardening.py - the container half of SV-09, checked in `preflight` (plan WP4.5).

Compose and Dockerfiles are configuration, and nothing else in the pipeline reads Compose (Conftest is [PLUS]).
This script reads them and refuses what SV-09 seeded and what a later edit could bring back:

  deploy/compose.yaml (the runtime definition, used by the Legion, staging and production), every service:
    read_only: true, cap_drop: [ALL] (cap_add only from a short list for the database), security_opt with
    no-new-privileges, a memory limit and a PID limit; never privileged, never host networking, PID or IPC,
    never the Docker socket; no published port on the database or the API, and on every other one a host address that is
    not a wildcard (the default of an interpolated ${NAME:-default} counts).
  deploy/compose.dev.yaml (the Legion's overlay): every published port bound to 127.0.0.1.
  backend/Dockerfile and frontend/Dockerfile:
    every FROM names a tag and a digest (never latest), the last stage runs as a numeric non-root USER,
    and no ENV or ARG carries a secret (a name with KEY, SECRET, TOKEN or PASSWORD, except *_FILE paths).

  python3 -I ci/tools/check-container-hardening.py [REPOSITORY_ROOT]
Needs Python 3 and PyYAML (python3-yaml). Exit code 0: nothing found; 1: findings, each printed with the fix.
"""

import re
import sys
from pathlib import Path

import yaml

DB_CAPS = {
    "CHOWN",
    "DAC_OVERRIDE",
    "FOWNER",
    "SETGID",
    "SETUID",
}  # what PostgreSQL's entrypoint needs
SECRET_NAME = re.compile(r"(KEY|SECRET|TOKEN|PASSWORD|PASSWD)", re.IGNORECASE)
problems: list[str] = []


def bad(where: str, what: str) -> None:
    problems.append(f"{where}: {what}")


def as_list(value) -> list:
    return value if isinstance(value, list) else []


def memory_limit(service: dict) -> bool:
    limits = ((service.get("deploy") or {}).get("resources") or {}).get("limits") or {}
    return bool(service.get("mem_limit") or limits.get("memory"))


WILDCARD = {"", "0.0.0.0", "::"}  # a host address that listens on every interface
INTERPOLATION = re.compile(r"\$\{[A-Za-z_][A-Za-z0-9_]*(?::?-([^}]*))?\}")


def expand(text: str) -> str:
    """Compose's ${NAME:-default} with the default taken: what a bare `docker compose up` would use."""
    return INTERPOLATION.sub(lambda found: found.group(1) or "", text)


def port_host(spec) -> str | None:
    """The host address a published port listens on, or None when it names none (every interface)."""
    if isinstance(spec, dict):
        host = spec.get("host_ip")
        return None if host is None else expand(str(host)).strip("[]")
    text = expand(str(spec))
    if text.startswith("["):  # [::1]:8080:8080
        return text[1 : text.index("]")]
    parts = text.split(":")
    return parts[0] if len(parts) == 3 else None


def on_every_interface(spec) -> bool:
    host = port_host(spec)
    return host is None or host in WILDCARD


def check_compose(root: Path) -> None:
    path = root / "deploy" / "compose.yaml"
    if not path.is_file():
        bad("deploy/compose.yaml", "is missing")
        return
    services = (yaml.safe_load(path.read_text(encoding="utf-8")) or {}).get(
        "services"
    ) or {}
    if not services:
        bad("deploy/compose.yaml", "defines no service")
    for name, service in services.items():
        where = f"deploy/compose.yaml, service {name}"
        if service.get("read_only") is not True:
            bad(
                where,
                "read_only: true is missing (the root filesystem must be read-only; use tmpfs for /tmp)",
            )
        if "ALL" not in [str(cap).upper() for cap in as_list(service.get("cap_drop"))]:
            bad(where, "cap_drop: [ALL] is missing")
        allowed = DB_CAPS if name == "db" else set()
        extra = {str(cap).upper() for cap in as_list(service.get("cap_add"))} - allowed
        if extra:
            bad(where, f"cap_add {sorted(extra)} is not allowed for this service")
        options = [
            str(option).replace("=", ":").lower()
            for option in as_list(service.get("security_opt"))
        ]
        if "no-new-privileges:true" not in options:
            bad(where, "security_opt: [no-new-privileges:true] is missing")
        if not memory_limit(service):
            bad(where, "no memory limit (mem_limit)")
        if not service.get("pids_limit"):
            bad(where, "no PID limit (pids_limit)")
        if service.get("privileged"):
            bad(where, "privileged: true")
        for key in ("network_mode", "pid", "ipc"):
            if service.get(key) == "host":
                bad(where, f"{key}: host")
        for volume in as_list(service.get("volumes")):
            source = (
                volume.get("source", "") if isinstance(volume, dict) else str(volume)
            )
            if "docker.sock" in str(source):
                bad(where, "mounts the Docker socket, which is root on the host")
        ports = as_list(service.get("ports"))
        if name in ("db", "api") and ports:
            bad(where, "publishes a port: only the web tier is reached from outside")
        for spec in ports:
            if on_every_interface(spec):
                bad(
                    where,
                    f"port {spec} has no host address, or a wildcard one: it would listen on every interface",
                )


def check_dev_overlay(root: Path) -> None:
    path = root / "deploy" / "compose.dev.yaml"
    if not path.is_file():
        return
    services = (yaml.safe_load(path.read_text(encoding="utf-8")) or {}).get(
        "services"
    ) or {}
    for name, service in services.items():
        for spec in as_list(service.get("ports")):
            if port_host(spec) not in ("127.0.0.1", "::1"):
                bad(
                    f"deploy/compose.dev.yaml, service {name}",
                    f"port {spec} must be bound to 127.0.0.1",
                )


def instructions(text: str) -> list[tuple[str, str]]:
    """Dockerfile instructions as (KEYWORD, arguments), continuation lines joined, comments dropped."""
    joined, current = [], ""
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.endswith("\\"):
            current += line[:-1] + " "
            continue
        joined.append(current + line)
        current = ""
    result = []
    for line in joined:
        keyword, _, rest = line.partition(" ")
        result.append((keyword.upper(), rest.strip()))
    return result


def check_dockerfile(root: Path, relative: str) -> None:
    path = root / relative
    if not path.is_file():
        bad(relative, "is missing")
        return
    last_user = None
    for keyword, rest in instructions(path.read_text(encoding="utf-8")):
        if keyword == "FROM":
            image = rest.split()[0]
            if re.search(r":latest(@|$)", image):
                bad(relative, f"FROM {image}: latest is a mutable tag")
            elif image.lower() != "scratch" and not re.search(
                r":[^:@/]+@sha256:[0-9a-f]{64}$", image
            ):
                bad(relative, f"FROM {image}: name a tag and a digest (tag@sha256:...)")
            last_user = None  # USER is per stage: only the last stage's counts
        elif keyword == "USER":
            last_user = rest.split(":")[0]
        elif keyword in ("ENV", "ARG"):
            for name in re.findall(r"(?:^|\s)([A-Za-z_][A-Za-z0-9_]*)=", rest) or [
                rest.split()[0]
            ]:
                if SECRET_NAME.search(name) and not name.upper().endswith("_FILE"):
                    bad(
                        relative,
                        f"{keyword} {name}: a secret in an image layer (read it from a file at run time)",
                    )
    if last_user is None or last_user in ("root", "0"):
        bad(
            relative,
            "the last stage has no USER, or runs as root: use a numeric non-root USER",
        )
    elif not last_user.isdigit():
        bad(
            relative,
            f"USER {last_user}: use the numeric id, so that a runtime can check it is not root",
        )


def main() -> int:
    root = (
        Path(sys.argv[1]).resolve()
        if len(sys.argv) > 1
        else Path(__file__).resolve().parents[2]
    )
    check_compose(root)
    check_dev_overlay(root)
    for relative in ("backend/Dockerfile", "frontend/Dockerfile"):
        check_dockerfile(root, relative)
    if problems:
        print("\n".join(f"FAIL  {problem}" for problem in problems))
        print(
            f"check-container-hardening: {len(problems)} problem(s); see docs/secure-coding.md#insecure-containers"
        )
        return 1
    print(
        "check-container-hardening: compose.yaml, compose.dev.yaml and both Dockerfiles are hardened"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
