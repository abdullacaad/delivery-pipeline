import pytest

from app.main import app


@pytest.fixture()
def client():
    app.config.update(TESTING=True)
    return app.test_client()


def test_index(client):
    r = client.get("/")
    assert r.status_code == 200
    assert r.get_json()["service"] == "delivery-demo"


def test_health_ok(client, monkeypatch):
    monkeypatch.setenv("APP_VERSION", "sha-abc1234")
    r = client.get("/health")
    assert r.status_code == 200
    assert r.get_json() == {"status": "ok", "version": "sha-abc1234"}


def test_health_simulated_failure(client, monkeypatch):
    monkeypatch.setenv("SIMULATE_UNHEALTHY", "1")
    r = client.get("/health")
    assert r.status_code == 503
    assert r.get_json()["status"] == "unhealthy"


def test_version(client, monkeypatch):
    monkeypatch.setenv("APP_VERSION", "v9")
    assert client.get("/version").get_json() == {"version": "v9"}


@pytest.mark.parametrize(
    "query,expected",
    [("?name=Saad", "Hello, Saad!"), ("", "Hello, world!"), ("?name=%20", "Hello, world!")],
)
def test_greet(client, query, expected):
    assert client.get(f"/api/greet{query}").get_json()["message"] == expected


def test_add(client):
    assert client.get("/api/add?a=2&b=3.5").get_json() == {"result": 5.5}


@pytest.mark.parametrize("query", ["", "?a=1", "?a=x&b=2"])
def test_add_bad_input(client, query):
    assert client.get(f"/api/add{query}").status_code == 400
