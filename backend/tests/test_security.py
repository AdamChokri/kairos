"""SV-05: passwords are stored as Argon2id hashes, salted, with a work factor."""

import hashlib

from sqlalchemy import select

from app import security
from app.db import SessionLocal
from app.models import User


def stored_hash(username):
    with SessionLocal() as session:
        return session.scalar(select(User.password_hash).where(User.username == username))


def test_the_stored_hash_is_argon2id(client):
    client.post("/api/auth/register", json={"username": "carol", "password": "correct-horse-1"})
    assert stored_hash("carol").startswith("$argon2id$")


def test_the_same_password_gives_two_different_hashes():
    first = security.hash_password("correct-horse-1")
    second = security.hash_password("correct-horse-1")
    assert first != second
    assert first.startswith("$argon2id$")


def test_verify_accepts_the_password_and_nothing_else():
    hashed = security.hash_password("correct-horse-1")
    assert security.verify_password("correct-horse-1", hashed) is True
    assert security.verify_password("wrong-horse-1", hashed) is False
    assert security.verify_password("", hashed) is False


def test_an_old_md5_hash_is_refused_not_a_crash(client):
    # What the as-is version stored: 32 hexadecimal characters, the unsalted MD5 of the password.
    old = hashlib.md5(b"correct-horse-1", usedforsecurity=False).hexdigest()
    assert security.verify_password("correct-horse-1", old) is False
    with SessionLocal() as session:
        session.add(User(username="legacy", password_hash=old))
        session.commit()
    response = client.post(
        "/api/auth/login", json={"username": "legacy", "password": "correct-horse-1"}
    )
    assert response.status_code == 401


def test_a_hash_with_weaker_parameters_is_upgraded_at_login(client):
    from argon2 import PasswordHasher  # the same library, with a cheaper work factor

    weak = PasswordHasher(time_cost=1, memory_cost=8, parallelism=1).hash("correct-horse-1")
    with SessionLocal() as session:
        session.add(User(username="weak", password_hash=weak))
        session.commit()
    login = client.post("/api/auth/login", json={"username": "weak", "password": "correct-horse-1"})
    assert login.status_code == 200
    upgraded = stored_hash("weak")
    assert upgraded != weak
    assert upgraded.startswith("$argon2id$")
    assert security.verify_password("correct-horse-1", upgraded) is True


def test_unknown_user_and_wrong_password_look_the_same(client, alice):
    unknown = client.post("/api/auth/login", json={"username": "nobody", "password": "x" * 12})
    wrong = client.post("/api/auth/login", json={"username": "alice", "password": "x" * 12})
    assert unknown.status_code == wrong.status_code == 401
    assert unknown.json() == wrong.json() == {"detail": "Invalid credentials"}
