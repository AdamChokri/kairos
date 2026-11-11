"""POST /api/assist: a note in, a task suggestion out (D-20, WP4.7). Off unless ASSIST_ENABLED."""

from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel

from app import assist, config
from app.db import DbSession
from app.deps import CurrentUser

router = APIRouter(prefix="/api/assist", tags=["assist"])


class AssistIn(BaseModel):
    note: str


@router.post("")
def ask(body: AssistIn, user: CurrentUser, db: DbSession) -> dict[str, str]:
    if not config.ASSIST_ENABLED:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Kairos Assist is switched off")
    return {"suggestion": assist.suggest(db, user, body.note)}
