"""Fixture for kairos.llm-context-unscoped."""

from openai import OpenAI
from sqlalchemy import select

from app.models import Task

client = OpenAI(api_key="k", base_url="https://api.deepseek.com")


def build_context(db, user):
    # ruleid: kairos.llm-context-unscoped
    everything = db.scalars(select(Task)).all()

    # ruleid: kairos.llm-context-unscoped
    rows = db.query(Task).all()

    # ruleid: kairos.llm-context-unscoped
    newest = db.scalars(select(Task).order_by(Task.id.desc()).limit(20)).all()

    # ruleid: kairos.llm-context-unscoped
    open_tasks = db.scalars(select(Task).where(Task.done.is_(False))).all()

    # ok: kairos.llm-context-unscoped
    mine = db.scalars(select(Task).where(Task.owner_id == user.id)).all()

    # ok: kairos.llm-context-unscoped
    mine_too = db.scalars(select(Task).where(Task.done.is_(False), Task.owner_id == user.id)).all()

    # ok: kairos.llm-context-unscoped
    mine_orm = db.query(Task).filter(Task.owner_id == user.id).all()

    # ok: kairos.llm-context-unscoped
    mine_limited = db.scalars(
        select(Task).where(Task.owner_id == user.id).order_by(Task.id.desc()).limit(20)
    ).all()

    return everything, rows, newest, open_tasks, mine, mine_too, mine_orm, mine_limited
