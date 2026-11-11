"""Password hashing and access tokens.

Passwords are hashed with Argon2id (SV-05, fixed in WP4.5): salted, memory-hard, with the
parameters inside the stored string. A hash made with weaker parameters is replaced at the next
login. The unsalted MD5 of Kairos v0 is not accepted any more: the databases of the as-is stacks
are not carried over.
"""

from datetime import UTC, datetime, timedelta

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError

from app import config

# argon2-cffi's defaults: the low-memory profile of RFC 9106 (Argon2id, 64 MiB, 3 passes, 4 lanes).
_hasher = PasswordHasher()

# Checked when the username is unknown: an unknown user costs the same time as a wrong password.
DUMMY_HASH = _hasher.hash("kairos-unknown-user")


def hash_password(password: str) -> str:
    return _hasher.hash(password)


def verify_password(password: str, stored_hash: str) -> bool:
    try:
        return _hasher.verify(stored_hash, password)
    except (VerificationError, InvalidHashError):  # a wrong password, or a hash that is not Argon2
        return False


def needs_rehash(stored_hash: str) -> bool:
    return _hasher.check_needs_rehash(stored_hash)


def create_token(user_id: int) -> str:
    expires = datetime.now(UTC) + timedelta(minutes=config.ACCESS_TOKEN_MINUTES)
    claims = {"sub": str(user_id), "exp": expires}
    return jwt.encode(claims, config.JWT_SECRET_KEY, algorithm=config.JWT_ALGORITHM)


def read_token(token: str) -> int | None:
    try:
        claims = jwt.decode(token, config.JWT_SECRET_KEY, algorithms=[config.JWT_ALGORITHM])
        return int(claims["sub"])
    except (jwt.PyJWTError, KeyError, ValueError):
        return None
