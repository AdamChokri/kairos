"""Kairos settings.

Every secret is read from a file whose path an environment variable gives (`<NAME>_FILE`), never
from the source or from a plain environment variable: the files are throwaway ones in development
and in CI, and are made by whoever runs the stack anywhere else (SV-01, fixed in WP4.5).
The API refuses to start without a signing key of at least 32 bytes.
"""

import os
from collections.abc import Mapping
from pathlib import Path

from sqlalchemy.engine import URL, make_url

MIN_KEY_BYTES = 32


class ConfigError(RuntimeError):
    """The settings are missing or unsafe: the API must not start."""


def read_secret(name: str, env: Mapping[str, str] = os.environ) -> str:
    """Returns the secret NAME, read from the file named by the variable NAME_FILE."""
    variable = f"{name}_FILE"
    path = env.get(variable)
    if not path:
        raise ConfigError(
            f"{variable} is not set: {name} is read from a file, never from the environment"
        )
    try:
        return Path(path).read_text(encoding="utf-8").strip()
    except OSError as error:
        raise ConfigError(
            f"{variable} points to {path}, which cannot be read ({error.strerror})"
        ) from error


def read_signing_key(env: Mapping[str, str] = os.environ) -> str:
    key = read_secret("JWT_SECRET_KEY", env)
    if len(key.encode()) < MIN_KEY_BYTES:
        raise ConfigError(f"the key in JWT_SECRET_KEY_FILE must be at least {MIN_KEY_BYTES} bytes")
    return key


def build_database_url(env: Mapping[str, str] = os.environ) -> URL:
    """DATABASE_URL if set (unit tests: SQLite), else PostgreSQL with the password from a file."""
    if env.get("DATABASE_URL"):
        return make_url(env["DATABASE_URL"])
    try:
        host, user, database = env["POSTGRES_HOST"], env["POSTGRES_USER"], env["POSTGRES_DB"]
    except KeyError as error:
        raise ConfigError(f"{error.args[0]} is not set (or set DATABASE_URL)") from error
    return URL.create(
        "postgresql+psycopg",
        username=user,
        password=read_secret("POSTGRES_PASSWORD", env),
        host=host,
        port=int(env.get("POSTGRES_PORT", "5432")),
        database=database,
    )


JWT_SECRET_KEY = read_signing_key()
JWT_ALGORITHM = "HS256"
ACCESS_TOKEN_MINUTES = 60

DATABASE_URL = build_database_url()
GIT_SHA = os.getenv("GIT_SHA", "dev")


# Kairos Assist (D-20, WP4.7). Off by default: a release never switches it on by accident.
ASSIST_ENABLED = os.environ.get("ASSIST_ENABLED", "false").lower() in ("1", "true", "yes")
ASSIST_PROVIDER = os.environ.get("ASSIST_PROVIDER", "deepseek")  # "stub" answers without a key
ASSIST_MODEL = os.environ.get("ASSIST_MODEL", "deepseek-flash")
ASSIST_BASE_URL = os.environ.get("ASSIST_BASE_URL", "https://api.deepseek.com")
