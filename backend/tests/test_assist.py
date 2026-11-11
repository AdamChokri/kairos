"""Kairos Assist (WP4.7): off unless switched on, and its answer is untrusted input (SV-12).

The model is never the real one: `ScriptedClient` returns what a test says a model might return,
including what a hostile or confused one would.
"""

import json
from types import SimpleNamespace

import pytest

from app import assist, config


class ScriptedClient:
    """A model that answers with `content`, and records the arguments of every call."""

    def __init__(self, content: str) -> None:
        self.calls: list[dict] = []
        self._content = content
        self.chat = SimpleNamespace(completions=SimpleNamespace(create=self._create))

    def _create(self, **arguments):
        self.calls.append(arguments)
        message = SimpleNamespace(content=self._content)
        return SimpleNamespace(choices=[SimpleNamespace(message=message)])


@pytest.fixture
def assist_on(monkeypatch):
    monkeypatch.setattr(config, "ASSIST_ENABLED", True)
    monkeypatch.setattr(config, "ASSIST_PROVIDER", "stub")


@pytest.fixture
def model(monkeypatch, assist_on):
    """model("...") installs a scripted model that answers so; the result records the calls."""

    def install(content: str) -> ScriptedClient:
        scripted = ScriptedClient(content)
        monkeypatch.setattr(assist, "make_client", lambda: scripted)
        return scripted

    return install


def ask(client, headers, note="buy milk"):
    return client.post("/api/assist", json={"note": note}, headers=headers)


def test_the_assistant_is_off_by_default(client, alice):
    assert ask(client, alice).status_code == 404


def test_the_assistant_needs_a_login(client, assist_on):
    assert client.post("/api/assist", json={"note": "buy milk"}).status_code == 401


def test_the_assistant_answers_with_a_title_and_a_description(client, alice, model):
    model(json.dumps({"title": "Buy milk", "description": "Two litres"}))
    response = ask(client, alice)
    assert response.status_code == 200
    assert response.json() == {"title": "Buy milk", "description": "Two litres"}


def test_the_stub_model_answers_without_a_key(client, alice, assist_on):
    client.post("/api/tasks", json={"title": "Pay rent"}, headers=alice)
    response = ask(client, alice)
    assert response.status_code == 200
    assert response.json()["title"]


@pytest.mark.parametrize(
    "content",
    [
        "Sure! Here is a task: buy milk",  # not JSON
        "[]",  # JSON, not an object
        json.dumps({"title": ""}),  # an empty title
        json.dumps({"title": "x" * 201, "description": ""}),  # a title too long
        json.dumps({"title": "x", "description": "y" * 1001}),  # a description too long
        json.dumps({"title": "x", "description": "y", "run": "rm -rf /"}),  # an extra field
        json.dumps({"title": 7, "description": "y"}),  # the wrong type
    ],
)
def test_an_answer_that_is_not_the_schema_is_refused(client, alice, model, content):
    model(content)
    response = ask(client, alice)
    assert response.status_code == 502
    assert content not in response.text  # nothing of the model's answer reaches the caller


def test_markup_in_a_suggestion_is_passed_on_as_text(client, alice, model):
    payload = '<img src=x onerror="alert(1)">'
    model(json.dumps({"title": payload, "description": ""}))
    # the page shows it as text: see AssistPanel.test.tsx
    assert ask(client, alice).json()["title"] == payload
