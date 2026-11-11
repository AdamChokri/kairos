"""POST /api/assist: a note in, a task suggestion out (D-20, WP4.7). Off unless ASSIST_ENABLED."""

from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel

from app import assist, config
from app.db import DbSession
from app.deps import CurrentUser
from app.schemas import AssistSuggestion

router = APIRouter(prefix="/api/assist", tags=["assist"])


class AssistIn(BaseModel):
    note: str


@router.post("")
def ask(body: AssistIn, user: CurrentUser, db: DbSession) -> AssistSuggestion:
    if not config.ASSIST_ENABLED:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Kairos Assist is switched off")
    try:
        return assist.suggest(db, user, body.note)
    except assist.AssistError as problem:
        raise HTTPException(status.HTTP_502_BAD_GATEWAY, str(problem)) from problem
