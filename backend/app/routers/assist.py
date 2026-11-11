"""POST /api/assist: a note in, a task suggestion out (D-20, WP4.7). Off unless ASSIST_ENABLED."""

import math

from fastapi import APIRouter, HTTPException, Request, status

from app import assist, config
from app.db import DbSession
from app.deps import CurrentUser
from app.schemas import AssistIn, AssistSuggestion

router = APIRouter(prefix="/api/assist", tags=["assist"])


@router.post("")
def ask(body: AssistIn, user: CurrentUser, db: DbSession, request: Request) -> AssistSuggestion:
    if not config.ASSIST_ENABLED:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Kairos Assist is switched off")
    wait = request.app.state.assist_limiter.hit(user.id)
    if wait > 0:
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS,
            f"Kairos Assist answers {assist.CALLS_PER_MINUTE} times a minute: try again shortly",
            headers={"Retry-After": str(max(1, math.ceil(wait)))},
        )
    try:
        return assist.suggest(db, user, body.note)
    except assist.AssistError as problem:
        raise HTTPException(status.HTTP_502_BAD_GATEWAY, str(problem)) from problem
