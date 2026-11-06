"""Password hashing and access tokens.

Seeded weakness SV-05 (security/seeded-vulns.md): passwords are hashed with plain MD5 - no salt,
no work factor. WP4.5 replaces it with Argon2id.
"""

import hashlib
import hmac
from datetime import UTC, datetime, timedelta

import jwt

from app import config


def hash_password(password: str) -> str:
    return hashlib.md5(password.encode()).hexdigest()


def verify_password(password: str, stored_hash: str) -> bool:
    return hmac.compare_digest(hash_password(password), stored_hash)


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
