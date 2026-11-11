"""Not an assistant file: no model client is imported here, so an unscoped query is not this rule's business."""

from sqlalchemy import select

from app.models import Task


def admin_report(db):
    # ok: kairos.llm-context-unscoped
    return db.scalars(select(Task)).all()
