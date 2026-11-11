"""Kairos Assist (WP4.7): the feature answers, and is off unless it is switched on."""

import pytest

from app import config


@pytest.fixture
def assist_on(monkeypatch):
    monkeypatch.setattr(config, "ASSIST_ENABLED", True)
    monkeypatch.setattr(config, "ASSIST_PROVIDER", "stub")


def test_the_assistant_is_off_by_default(client, alice):
    response = client.post("/api/assist", json={"note": "buy milk"}, headers=alice)
    assert response.status_code == 404


def test_the_assistant_needs_a_login(client, assist_on):
    assert client.post("/api/assist", json={"note": "buy milk"}).status_code == 401


def test_the_assistant_answers(client, alice, assist_on):
    client.post("/api/tasks", json={"title": "Pay rent"}, headers=alice)
    response = client.post("/api/assist", json={"note": "buy milk"}, headers=alice)
    assert response.status_code == 200
    assert "Pay rent" in response.json()["suggestion"]
