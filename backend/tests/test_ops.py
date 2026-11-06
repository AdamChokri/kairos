def test_healthz(client):
    assert client.get("/healthz").json() == {"status": "ok"}


def test_version_defaults_to_dev(client):
    assert client.get("/api/version").json() == {"version": "dev"}
