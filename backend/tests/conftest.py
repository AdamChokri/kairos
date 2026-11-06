"""Test setup: an in-memory SQLite database, a fresh schema for every test.

The real PostgreSQL 17 is exercised by the smoke test of the Compose stack (ci/as-is/smoke.sh).
"""

import os

os.environ["DATABASE_URL"] = "sqlite://"

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from app.db import Base, engine  # noqa: E402
from app.main import app  # noqa: E402


@pytest.fixture
def client():
    Base.metadata.drop_all(engine)
    Base.metadata.create_all(engine)
    # An unexpected error must come back as a response, not be raised into the test.
    with TestClient(app, raise_server_exceptions=False) as test_client:
        yield test_client


def register_and_login(
    client: TestClient, username: str, password: str = "correct-horse-1"
) -> dict:
    client.post("/api/auth/register", json={"username": username, "password": password})
    token = client.post(
        "/api/auth/login", json={"username": username, "password": password}
    ).json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def alice(client):
    return register_and_login(client, "alice")


@pytest.fixture
def bob(client):
    return register_and_login(client, "bob")
