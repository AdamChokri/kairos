#!/usr/bin/env bash
# ci/as-is/smoke.sh - does the stack work? Registers two throwaway users and walks every
# endpoint of the API (plan section 3.2). It proves the application, not its security:
# security/check-seeded.sh proves the seeded weaknesses.
#   bash ci/as-is/smoke.sh [BASE_URL]     default http://localhost:8000 (Compose on the Legion)
#   bash ci/as-is/smoke.sh http://staging.kairos.lab:8000
# Needs bash, curl and python3. Exit code 0: everything answered as expected.
set -Eeuo pipefail

BASE="${1:-http://localhost:8000}"
BASE="${BASE%/}"
RUN="$(date +%s)$RANDOM"
FAKE_PW="correct-horse-1"   # throwaway account, deleted with the staging database

pass() { printf '  PASS  %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1" >&2; exit 1; }

# json FIELD - prints one top-level field of the JSON on stdin.
json() { python3 -c 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]])' "$1"; }

# api METHOD PATH [TOKEN] [BODY] [CONTENT-TYPE] - prints "status body".
api() {
  local method="$1" path="$2" token="${3:-}" body="${4:-}" ctype="${5:-application/json}"
  local args=(-sS -m 20 -X "$method" -w '\n%{http_code}' -H "Content-Type: $ctype")
  [[ -n "$token" ]] && args+=(-H "Authorization: Bearer $token")
  [[ -n "$body" ]] && args+=(--data-binary "$body")
  local out
  out="$(curl "${args[@]}" "$BASE$path")"
  printf '%s %s\n' "${out##*$'\n'}" "${out%$'\n'*}"
}
status() { printf '%s' "${1%% *}"; }
body() { printf '%s' "${1#* }"; }

printf 'Smoke test of %s\n' "$BASE"

for _ in $(seq 1 30); do
  [[ "$(curl -s -m 3 -o /dev/null -w '%{http_code}' "$BASE/healthz" || true)" == "200" ]] && break
  sleep 2
done
r="$(api GET /healthz)";                [[ "$(status "$r")" == 200 ]] || fail "GET /healthz did not answer 200"
pass "GET /healthz"
r="$(api GET /api/version)";            [[ "$(status "$r")" == 200 ]] || fail "GET /api/version"
pass "GET /api/version -> $(body "$r" | json version)"

r="$(api POST /api/auth/register "" "{\"username\":\"smoke$RUN\",\"password\":\"$FAKE_PW\"}")"
[[ "$(status "$r")" == 201 ]] || fail "register: $r"
pass "POST /api/auth/register"
r="$(api POST /api/auth/login "" "{\"username\":\"smoke$RUN\",\"password\":\"$FAKE_PW\"}")"
[[ "$(status "$r")" == 200 ]] || fail "login: $r"
TOKEN="$(body "$r" | json access_token)"
pass "POST /api/auth/login"
r="$(api POST /api/auth/login "" "{\"username\":\"smoke$RUN\",\"password\":\"wrong-pass-99\"}")"
[[ "$(status "$r")" == 401 ]] || fail "a wrong password must be refused"
pass "a wrong password is refused (401)"
r="$(api GET /api/tasks)";              [[ "$(status "$r")" == 401 ]] || fail "tasks without a token must be 401"
pass "a request without a token is refused (401)"

r="$(api POST /api/tasks "$TOKEN" "{\"title\":\"Buy Milk $RUN\",\"description\":\"smoke\"}")"
[[ "$(status "$r")" == 201 ]] || fail "create task: $r"
ID="$(body "$r" | json id)"
pass "POST /api/tasks (id $ID)"
r="$(api GET /api/tasks "$TOKEN")"
[[ "$(status "$r")" == 200 && "$(body "$r")" == *"Buy Milk $RUN"* ]] || fail "list tasks: $r"
pass "GET /api/tasks"
r="$(api GET "/api/tasks?search=buy%20milk%20$RUN" "$TOKEN")"
[[ "$(status "$r")" == 200 && "$(body "$r")" == *"Buy Milk $RUN"* ]] || fail "search: $r"
pass "GET /api/tasks?search= finds the task, ignoring case"
r="$(api GET "/api/tasks?search=no-such-title-$RUN" "$TOKEN")"
[[ "$(status "$r")" == 200 && "$(body "$r")" == "[]" ]] || fail "empty search: $r"
pass "GET /api/tasks?search= with no match returns []"

r="$(api GET "/api/tasks/$ID" "$TOKEN")"; [[ "$(status "$r")" == 200 ]] || fail "read task: $r"
pass "GET /api/tasks/$ID"
r="$(api PUT "/api/tasks/$ID" "$TOKEN" "{\"title\":\"Buy Milk $RUN\",\"description\":\"smoke\",\"done\":true}")"
[[ "$(status "$r")" == 200 && "$(body "$r" | json "done")" == True ]] || fail "update task: $r"
pass "PUT /api/tasks/$ID"

r="$(api POST "/api/tasks/$ID/comments" "$TOKEN" '{"body":"Looks good"}')"
[[ "$(status "$r")" == 201 ]] || fail "add comment: $r"
r="$(api GET "/api/tasks/$ID/comments" "$TOKEN")"
[[ "$(status "$r")" == 200 && "$(body "$r")" == *"Looks good"* ]] || fail "list comments: $r"
pass "POST and GET /api/tasks/$ID/comments"

YAML=$'tasks:\n  - title: Imported one\n    description: first\n  - title: Imported two\n'
r="$(api POST /api/tasks/import "$TOKEN" "$YAML" application/yaml)"
[[ "$(status "$r")" == 201 && "$(body "$r" | json imported)" == 2 ]] || fail "import: $r"
pass "POST /api/tasks/import (2 tasks)"

r="$(api DELETE "/api/tasks/$ID" "$TOKEN")"; [[ "$(status "$r")" == 204 ]] || fail "delete task: $r"
r="$(api GET "/api/tasks/$ID" "$TOKEN")";    [[ "$(status "$r")" == 404 ]] || fail "deleted task must be 404"
pass "DELETE /api/tasks/$ID"

printf 'Smoke test passed.\n'
