"""Database engine, session factory and the declarative base."""

from collections.abc import Iterator
from typing import Annotated

from fastapi import Depends
from sqlalchemy import create_engine
from sqlalchemy.engine import URL, make_url
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app import config


class Base(DeclarativeBase):
    pass


def make_engine(url: str | URL):
    parsed = make_url(url)
    if parsed.get_backend_name() == "sqlite":
        options: dict = {"connect_args": {"check_same_thread": False}}
        if parsed.database in (None, "", ":memory:"):
            options["poolclass"] = StaticPool  # one shared in-memory database (tests)
        return create_engine(url, **options)
    return create_engine(url, pool_pre_ping=True)


engine = make_engine(config.DATABASE_URL)
SessionLocal = sessionmaker(bind=engine, expire_on_commit=False)


def get_db() -> Iterator[Session]:
    with SessionLocal() as session:
        yield session


DbSession = Annotated[Session, Depends(get_db)]
