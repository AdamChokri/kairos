"""SV-01: every secret comes from a file, and the API refuses to start without a good signing key.

Each case starts the application in a fresh interpreter (`import app.main`), because the key is read
when the settings module is imported: that is the moment the API would start serving.
"""

import ast
import os
import subprocess
import sys
from pathlib import Path

from app import config

BACKEND = Path(__file__).resolve().parents[1]


def start_api(tmp_path: Path, key: str | None, **extra: str) -> subprocess.CompletedProcess[str]:
    """Imports the application with a minimal environment; `key` is written to a key file."""
    env = {"PATH": os.environ["PATH"], "DATABASE_URL": "sqlite://", **extra}
    if key is not None:
        key_file = tmp_path / "jwt_secret_key"
        key_file.write_text(key)
        env["JWT_SECRET_KEY_FILE"] = str(key_file)
    return subprocess.run(
        [sys.executable, "-c", "import app.main"],
        cwd=BACKEND,
        env=env,
        capture_output=True,
        text=True,
        timeout=60,
        check=False,
    )


def test_refuses_to_start_without_a_key_file(tmp_path):
    result = start_api(tmp_path, key=None)
    assert result.returncode != 0
    assert "JWT_SECRET_KEY_FILE" in result.stderr


def test_refuses_a_key_file_that_does_not_exist(tmp_path):
    result = start_api(tmp_path, key=None, JWT_SECRET_KEY_FILE=str(tmp_path / "missing"))
    assert result.returncode != 0
    assert "JWT_SECRET_KEY_FILE" in result.stderr


def test_refuses_a_key_shorter_than_32_bytes(tmp_path):
    result = start_api(tmp_path, key="k" * 31)
    assert result.returncode != 0
    assert "at least 32 bytes" in result.stderr


def test_refuses_a_key_that_is_only_whitespace_around_a_short_value(tmp_path):
    result = start_api(tmp_path, key="\n  " + "k" * 31 + "  \n")
    assert result.returncode != 0
    assert "at least 32 bytes" in result.stderr


def test_starts_with_a_32_byte_key(tmp_path):
    result = start_api(tmp_path, key="k" * 32 + "\n")
    assert result.returncode == 0, result.stderr


def test_the_key_is_never_taken_from_the_environment(tmp_path):
    # A secret in an environment variable shows in `docker inspect` and /proc: only files are read.
    result = start_api(tmp_path, key=None, JWT_SECRET_KEY="e" * 48)
    assert result.returncode != 0


def test_the_source_holds_no_long_string_literal():
    tree = ast.parse((BACKEND / "app" / "config.py").read_text())
    literals = [
        node.value
        for node in ast.walk(tree)
        if isinstance(node, ast.Constant)
        and isinstance(node.value, str)
        and len(node.value) >= 32
        and " " not in node.value  # prose (docstrings) has spaces; a key has none
    ]
    assert literals == []


def test_the_database_password_comes_from_a_file(tmp_path):
    password_file = tmp_path / "db_password"
    password_file.write_text("p@ss/word:with*specials\n")
    url = config.build_database_url(
        {
            "POSTGRES_HOST": "db",
            "POSTGRES_USER": "kairos",
            "POSTGRES_DB": "kairos",
            "POSTGRES_PASSWORD_FILE": str(password_file),
        }
    )
    assert url.drivername == "postgresql+psycopg"
    assert url.password == "p@ss/word:with*specials"
    assert "p@ss/word" not in url.render_as_string(hide_password=True)


def test_the_database_password_is_never_taken_from_the_environment():
    try:
        config.build_database_url(
            {
                "POSTGRES_HOST": "db",
                "POSTGRES_USER": "kairos",
                "POSTGRES_DB": "kairos",
                "POSTGRES_PASSWORD": "x" * 24,
            }
        )
    except config.ConfigError as error:
        assert "POSTGRES_PASSWORD_FILE" in str(error)
    else:
        raise AssertionError("the password was accepted from the environment")


def test_a_complete_database_url_is_still_accepted():
    # The unit tests use an in-memory SQLite database (D-25).
    assert str(config.build_database_url({"DATABASE_URL": "sqlite://"})) == "sqlite://"
