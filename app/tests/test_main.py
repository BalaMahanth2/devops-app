import psycopg
import pytest

import main


@pytest.fixture
def client():
    main.app.config["TESTING"] = True
    with main.app.test_client() as client:
        yield client


def database_down(*args, **kwargs):
    raise psycopg.OperationalError("database is down")


def test_health_does_not_touch_database(client, monkeypatch):
    monkeypatch.setattr(main, "get_connection", database_down)
    response = client.get("/health")
    assert response.status_code == 200
    assert response.get_json() == {"status": "ok"}


def test_ready_returns_503_when_database_down(client, monkeypatch):
    monkeypatch.setattr(main, "get_connection", database_down)
    response = client.get("/ready")
    assert response.status_code == 503


def test_index_shows_visit_count(client, monkeypatch):
    monkeypatch.setattr(main, "record_visit", lambda hostname: 42)
    response = client.get("/")
    assert response.status_code == 200
    assert b"42" in response.data


def test_index_renders_when_database_down(client, monkeypatch):
    monkeypatch.setattr(main, "record_visit", database_down)
    response = client.get("/")
    assert response.status_code == 200
    assert b"unavailable" in response.data


def test_unknown_route_returns_404(client):
    response = client.get("/does-not-exist")
    assert response.status_code == 404
