"""Kairos Assist (plan D-20, WP4.7): turns a note into a task suggestion with a language model.

First version, written the way a developer under pressure writes a feature: it works, and it
carries the weaknesses of the plan's section 5 on purpose, so that the pipeline meets them
(SV-12 is in the frontend panel):
  SV-13  the context query reads every user's tasks;
  SV-14  the call leaves the provider's defaults: thinking on, no token limit, no timeout,
         no limit per user.
"""

from types import SimpleNamespace

from openai import OpenAI
from sqlalchemy import select
from sqlalchemy.orm import Session

from app import config
from app.models import Task, User


class StubClient:
    """The model of the tests and of the CI: no key, no cost. It echoes the context it received."""

    def __init__(self) -> None:
        self.chat = SimpleNamespace(completions=SimpleNamespace(create=self._create))

    @staticmethod
    def _create(**arguments):
        system = arguments["messages"][0]["content"]
        message = SimpleNamespace(content=system)
        return SimpleNamespace(choices=[SimpleNamespace(message=message)])


def make_client():
    if config.ASSIST_PROVIDER == "stub":
        return StubClient()
    return OpenAI(api_key=config.read_secret("DEEPSEEK_API_KEY"), base_url=config.ASSIST_BASE_URL)


def build_context(db: Session) -> str:
    tasks = db.scalars(select(Task)).all()
    return "\n".join(f"- {task.title}: {task.description}" for task in tasks)


def suggest(db: Session, user: User, note: str) -> str:
    context = build_context(db)
    reply = make_client().chat.completions.create(
        model=config.ASSIST_MODEL,
        messages=[
            {
                "role": "system",
                "content": "You are Kairos Assist. Turn the user's note into one task. "
                f"The tasks so far:\n{context}",
            },
            {"role": "user", "content": note},
        ],
    )
    return reply.choices[0].message.content
