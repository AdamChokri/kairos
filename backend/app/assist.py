"""Kairos Assist (plan D-20, WP4.7): turns a note into a task suggestion with a language model.

The model's answer is untrusted input, like a form field: it must be one JSON object of the
schema `AssistSuggestion` and nothing else (SV-12). The weaknesses of the first version that
remain are SV-13 (the context query reads every user's tasks) and SV-14 (the call leaves the
provider's defaults: thinking on, no token limit, no timeout, no limit per user).
"""

import json
from types import SimpleNamespace

from openai import OpenAI
from pydantic import ValidationError
from sqlalchemy import select
from sqlalchemy.orm import Session

from app import config
from app.models import Task, User
from app.schemas import AssistSuggestion


class AssistError(Exception):
    """The assistant could not give a usable answer. The message is safe to show to the caller."""


class StubClient:
    """The model of the tests and of the CI: no key, no cost. It echoes the context it received."""

    def __init__(self) -> None:
        self.chat = SimpleNamespace(completions=SimpleNamespace(create=self._create))

    @staticmethod
    def _create(**arguments):
        system = arguments["messages"][0]["content"]
        answer = {"title": "Suggested task", "description": system[:1000]}
        message = SimpleNamespace(content=json.dumps(answer))
        return SimpleNamespace(choices=[SimpleNamespace(message=message)])


def make_client():
    if config.ASSIST_PROVIDER == "stub":
        return StubClient()
    return OpenAI(api_key=config.read_secret("DEEPSEEK_API_KEY"), base_url=config.ASSIST_BASE_URL)


def build_context(db: Session) -> str:
    tasks = db.scalars(select(Task)).all()
    return "\n".join(f"- {task.title}: {task.description}" for task in tasks)


def suggest(db: Session, user: User, note: str) -> AssistSuggestion:
    context = build_context(db)
    reply = make_client().chat.completions.create(
        model=config.ASSIST_MODEL,
        response_format={"type": "json_object"},
        messages=[
            {
                "role": "system",
                "content": "You are Kairos Assist. Turn the user's note into one task. "
                'Answer with one JSON object and nothing else: {"title": a short title, '
                '"description": a longer text}. '
                f"The tasks so far:\n{context}",
            },
            {"role": "user", "content": note},
        ],
    )
    try:
        return AssistSuggestion.model_validate_json(reply.choices[0].message.content or "")
    except ValidationError as problem:
        # Say what was wrong with the shape, never what the model said.
        raise AssistError("Kairos Assist gave an answer that could not be used") from problem
