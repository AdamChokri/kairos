#!/usr/bin/env bash
# ci/tools/hooks-demo.sh secret|sql|clean - writes the demo files that prove the hooks (plan WP3.2
# done-when), and removes them again. The files are never meant to be committed for real:
#   secret  demo/fake-secret.py: a fresh RANDOM fake token in a variable that looks like a key. It is
#           generated here, now, so no secret-shaped value is stored in the repository or in the guide.
#   sql     backend/app/hooks_demo_sql.py: a function that builds SQL with an f-string (SV-02's pattern).
#   clean   removes both files and takes them out of the index.
#   bash ci/tools/hooks-demo.sh secret
set -Eeuo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
case "${1:-}" in
  secret)
    mkdir -p demo
    # Random, and re-drawn in the rare case that its entropy is low enough for a scanner to doubt it.
    token="$(python3 -c '
import math, secrets
while True:
    value = secrets.token_hex(24)
    if -sum(value.count(c) / len(value) * math.log2(value.count(c) / len(value)) for c in set(value)) >= 3.7:
        print(value)
        break
')"
    printf '"""Demo only: a random fake token, made now. The commit must be blocked."""\n\nAPI_TOKEN = "%s"\n' "$token" > demo/fake-secret.py
    unset token
    echo "wrote demo/fake-secret.py (a random fake token). Next: git add demo/fake-secret.py && git commit -S -m 'demo: fake secret'"
    ;;
  sql)
    cat > backend/app/hooks_demo_sql.py <<'PY'
"""Demo only: SQL built with an f-string, the pattern of SV-02. The push must be blocked."""

from sqlalchemy import text
from sqlalchemy.orm import Session


def find_by_title(db: Session, title: str):
    return db.execute(text(f"SELECT id, title FROM tasks WHERE title = '{title}'")).all()
PY
    echo "wrote backend/app/hooks_demo_sql.py. Next: git switch -c demo/hooks-check, then git add, git commit, git push"
    ;;
  clean)
    git rm -q --cached --ignore-unmatch demo/fake-secret.py backend/app/hooks_demo_sql.py
    rm -f demo/fake-secret.py backend/app/hooks_demo_sql.py
    rmdir demo 2>/dev/null || true
    echo "demo files removed"
    ;;
  *)
    echo "usage: bash ci/tools/hooks-demo.sh secret|sql|clean" >&2
    exit 2
    ;;
esac
