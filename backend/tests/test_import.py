def test_import_creates_the_tasks(client, alice):
    document = "tasks:\n  - title: First\n    description: one\n  - title: Second\n"
    response = client.post(
        "/api/tasks/import",
        content=document,
        headers={**alice, "Content-Type": "application/yaml"},
    )
    assert response.status_code == 201
    assert response.json() == {"imported": 2}
    titles = [t["title"] for t in client.get("/api/tasks", headers=alice).json()]
    assert titles == ["First", "Second"]


def test_import_needs_a_token(client):
    assert client.post("/api/tasks/import", content="tasks: []").status_code == 401
