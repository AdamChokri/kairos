"""Fixture for kairos.hardcoded-jwt-secret. Every value below is fake and protects nothing."""

import os

import jwt

# ruleid: kairos.hardcoded-jwt-secret
JWT_SECRET_KEY = "not-a-real-key-0123456789abcdef"

# ruleid: kairos.hardcoded-jwt-secret
SIGNING_KEY: str = "another-fake-signing-key-for-tests"

# ruleid: kairos.hardcoded-jwt-secret
token = jwt.encode({"sub": "1"}, "inline-fake-key-0123456789", algorithm="HS256")

# ruleid: kairos.hardcoded-jwt-secret
claims = jwt.decode(token, "inline-fake-key-0123456789", algorithms=["HS256"])

# ok: kairos.hardcoded-jwt-secret
JWT_SECRET_KEY_FROM_ENV = os.environ["JWT_SECRET_KEY"]

# ok: kairos.hardcoded-jwt-secret
with open(os.environ["JWT_SECRET_KEY_FILE"], encoding="utf-8") as handle:
    key = handle.read().strip()

# ok: kairos.hardcoded-jwt-secret
JWT_ALGORITHM = "HS256"

# ok: kairos.hardcoded-jwt-secret
ACCESS_TOKEN_KEY = ""

# ok: kairos.hardcoded-jwt-secret
SHORT_SECRET = "dev"

# ok: kairos.hardcoded-jwt-secret
signed = jwt.encode({"sub": "1"}, key, algorithm="HS256")
