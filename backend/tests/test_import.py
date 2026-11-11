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


# SV-04: the body is data. It is parsed with the safe loader and checked against a schema.
def post_yaml(client, headers, document):
    return client.post(
        "/api/tasks/import",
        content=document,
        headers={**headers, "Content-Type": "application/yaml"},
    )


def titles(client, headers):
    return [t["title"] for t in client.get("/api/tasks", headers=headers).json()]


def test_a_python_object_tag_is_rejected_and_nothing_runs(client, alice):
    document = "tasks:\n  - title: !!python/object/apply:os.getcwd []\n"
    response = post_yaml(client, alice, document)
    assert response.status_code == 422
    assert titles(client, alice) == []


def test_a_command_running_tag_is_rejected(client, alice):
    document = "tasks:\n  - title: !!python/object/apply:subprocess.check_output [[id]]\n"
    response = post_yaml(client, alice, document)
    assert response.status_code == 422
    assert "uid=" not in response.text
    assert titles(client, alice) == []


def test_the_error_does_not_show_the_server(client, alice):
    response = post_yaml(client, alice, "tasks:\n  - title: !!python/name:os.system\n")
    assert response.status_code == 422
    for leak in ("Traceback", "site-packages", "constructor", "/app/"):
        assert leak not in response.text


def test_a_document_with_an_unknown_field_is_rejected(client, alice):
    response = post_yaml(client, alice, "tasks:\n  - title: First\n    owner_id: 99\n")
    assert response.status_code == 422
    assert titles(client, alice) == []


def test_a_task_without_a_title_is_rejected(client, alice):
    assert post_yaml(client, alice, "tasks:\n  - description: no title\n").status_code == 422
    assert post_yaml(client, alice, "tasks:\n  - title: ''\n").status_code == 422


def test_the_shape_of_the_document_is_checked(client, alice):
    for document in (
        "",
        "- just\n- a list\n",
        "tasks: not-a-list\n",
        "tasks:\n  - 42\n",
        "a: [b\n",
    ):
        assert post_yaml(client, alice, document).status_code == 422, document


def test_too_many_tasks_are_rejected(client, alice):
    document = "tasks:\n" + "  - title: t\n" * 201
    assert post_yaml(client, alice, document).status_code == 422
    assert titles(client, alice) == []


def test_an_oversized_body_is_rejected(client, alice):
    document = "tasks:\n  - title: t\n    description: " + "x" * 150_000 + "\n"
    assert post_yaml(client, alice, document).status_code == 413


def test_yaml_aliases_are_rejected(client, alice):
    # A few hundred bytes of aliases expand to gigabytes when loaded ("billion laughs").
    bomb = "a: &a [x, x, x, x, x, x, x, x, x]\nb: &b [*a, *a, *a, *a, *a, *a, *a, *a, *a]\n"
    bomb += "tasks:\n  - title: t\n    description: *b\n"
    response = post_yaml(client, alice, bomb)
    assert response.status_code == 422
    assert titles(client, alice) == []


def test_a_valid_document_is_still_imported(client, alice):
    response = post_yaml(client, alice, "tasks:\n  - title: First\n    description: one\n")
    assert response.status_code == 201
    assert titles(client, alice) == ["First"]
