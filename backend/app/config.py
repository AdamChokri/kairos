"""Kairos settings.

Seeded weakness SV-01 (security/seeded-vulns.md): the token signing key is written in the
source. It is a FAKE value that protects nothing; WP4.5 reads it from a secret file instead.
"""

import os

JWT_SECRET_KEY = "066c75a9a194a9f0eef67f26bb1684779b920206fb0a74a5"
JWT_ALGORITHM = "HS256"
ACCESS_TOKEN_MINUTES = 60

DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./kairos.db")
GIT_SHA = os.getenv("GIT_SHA", "dev")
