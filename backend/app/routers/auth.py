"""POST /api/auth/register and POST /api/auth/login."""

from fastapi import APIRouter, HTTPException, status
from sqlalchemy import select

from app import security
from app.db import DbSession
from app.models import User
from app.schemas import Credentials, TokenOut, UserOut

router = APIRouter(prefix="/api/auth", tags=["auth"])


@router.post("/register", response_model=UserOut, status_code=status.HTTP_201_CREATED)
def register(body: Credentials, db: DbSession) -> User:
    if db.scalar(select(User).where(User.username == body.username)):
        raise HTTPException(status.HTTP_409_CONFLICT, "Username already taken")
    user = User(username=body.username, password_hash=security.hash_password(body.password))
    db.add(user)
    db.commit()
    return user


@router.post("/login", response_model=TokenOut)
def login(body: Credentials, db: DbSession) -> TokenOut:
    user = db.scalar(select(User).where(User.username == body.username))
    stored = user.password_hash if user else security.DUMMY_HASH
    if not security.verify_password(body.password, stored) or user is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid credentials")
    if security.needs_rehash(user.password_hash):
        user.password_hash = security.hash_password(body.password)  # weaker parameters: upgrade now
        db.commit()
    return TokenOut(access_token=security.create_token(user.id))
