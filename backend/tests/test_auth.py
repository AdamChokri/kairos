import jwt

from app import config


def test_register_then_login_returns_a_token(client):
    created = client.post(
        "/api/auth/register", json={"username": "alice", "password": "correct-horse-1"}
    )
    assert created.status_code == 201
    assert created.json()["username"] == "alice"

    login = client.post(
        "/api/auth/login", json={"username": "alice", "password": "correct-horse-1"}
    )
    assert login.status_code == 200
    claims = jwt.decode(
        login.json()["access_token"], config.JWT_SECRET_KEY, algorithms=[config.JWT_ALGORITHM]
    )
    assert claims["sub"] == str(created.json()["id"])


def test_duplicate_username_is_refused(client):
    body = {"username": "alice", "password": "correct-horse-1"}
    assert client.post("/api/auth/register", json=body).status_code == 201
    assert client.post("/api/auth/register", json=body).status_code == 409


def test_wrong_password_and_unknown_user_get_the_same_answer(client):
    client.post("/api/auth/register", json={"username": "alice", "password": "correct-horse-1"})
    wrong = client.post("/api/auth/login", json={"username": "alice", "password": "wrong-pass-99"})
    unknown = client.post(
        "/api/auth/login", json={"username": "nobody", "password": "wrong-pass-99"}
    )
    assert wrong.status_code == unknown.status_code == 401
    assert wrong.json() == unknown.json()


def test_short_password_is_refused(client):
    response = client.post("/api/auth/register", json={"username": "alice", "password": "short"})
    assert response.status_code == 422


def test_tasks_need_a_token(client):
    assert client.get("/api/tasks").status_code == 401
    assert client.get("/api/tasks", headers={"Authorization": "Bearer nonsense"}).status_code == 401
