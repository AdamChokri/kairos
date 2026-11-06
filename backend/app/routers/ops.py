"""Operations: GET /healthz and GET /api/version."""

from fastapi import APIRouter

from app import config

router = APIRouter(tags=["ops"])


@router.get("/healthz")
def healthz() -> dict[str, str]:
    return {"status": "ok"}


@router.get("/api/version")
def version() -> dict[str, str]:
    return {"version": config.GIT_SHA}
