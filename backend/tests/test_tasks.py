def make_task(client, headers, title, description=""):
    response = client.post(
        "/api/tasks", json={"title": title, "description": description}, headers=headers
    )
    assert response.status_code == 201
    return response.json()


def test_create_list_update_delete(client, alice):
    task = make_task(client, alice, "Write the report", "first draft")
    assert task["done"] is False

    listed = client.get("/api/tasks", headers=alice).json()
    assert [item["title"] for item in listed] == ["Write the report"]

    updated = client.put(
        f"/api/tasks/{task['id']}",
        json={"title": "Write the final report", "description": "", "done": True},
        headers=alice,
    )
    assert updated.status_code == 200
    assert updated.json()["done"] is True

    assert client.delete(f"/api/tasks/{task['id']}", headers=alice).status_code == 204
    assert client.get(f"/api/tasks/{task['id']}", headers=alice).status_code == 404


def test_list_shows_only_my_tasks(client, alice, bob):
    make_task(client, alice, "Alice's task")
    make_task(client, bob, "Bob's task")
    assert [t["title"] for t in client.get("/api/tasks", headers=alice).json()] == ["Alice's task"]
    assert [t["title"] for t in client.get("/api/tasks", headers=bob).json()] == ["Bob's task"]


def test_search_finds_a_title_ignoring_case(client, alice):
    make_task(client, alice, "Buy Milk")
    make_task(client, alice, "Call the bank")
    found = client.get("/api/tasks", params={"search": "milk"}, headers=alice).json()
    assert [t["title"] for t in found] == ["Buy Milk"]


def test_search_of_nothing_returns_an_empty_list(client, alice):
    make_task(client, alice, "Buy Milk")
    assert client.get("/api/tasks", params={"search": "zzz"}, headers=alice).json() == []


def test_unknown_task_is_404(client, alice):
    assert client.get("/api/tasks/999", headers=alice).status_code == 404


def test_empty_title_is_refused(client, alice):
    assert client.post("/api/tasks", json={"title": ""}, headers=alice).status_code == 422
