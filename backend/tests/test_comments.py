def test_comments_on_a_task(client, alice):
    task = client.post("/api/tasks", json={"title": "Plan"}, headers=alice).json()
    url = f"/api/tasks/{task['id']}/comments"

    assert client.get(url, headers=alice).json() == []
    created = client.post(url, json={"body": "Looks good"}, headers=alice)
    assert created.status_code == 201

    listed = client.get(url, headers=alice).json()
    assert [c["body"] for c in listed] == ["Looks good"]
    assert listed[0]["author_id"] == task["owner_id"]


def test_comment_on_a_missing_task_is_404(client, alice):
    assert (
        client.post("/api/tasks/999/comments", json={"body": "x"}, headers=alice).status_code == 404
    )


def test_deleting_a_task_removes_its_comments(client, alice):
    task = client.post("/api/tasks", json={"title": "Plan"}, headers=alice).json()
    client.post(f"/api/tasks/{task['id']}/comments", json={"body": "bye"}, headers=alice)
    assert client.delete(f"/api/tasks/{task['id']}", headers=alice).status_code == 204
