"""Shared pytest fixtures.

Every test runs against its own throwaway SQLite file so the suite is
hermetic: no network, no shared state, no production data.
"""

from __future__ import annotations

import os
import tempfile
from pathlib import Path

import pytest

os.environ.setdefault("DASHA_SKIP_INIT", "1")
os.environ.setdefault("AI_PROVIDER", "heuristic")
os.environ.setdefault("DASHA_DISABLE_SCHEDULER", "1")

from newsroom.config import get_settings  # noqa: E402
from newsroom.db import engine as db_engine  # noqa: E402
from newsroom.db.engine import init_db  # noqa: E402
from newsroom.security.auth import reset_limiter  # noqa: E402


@pytest.fixture(autouse=True)
def isolated_settings(tmp_path, monkeypatch):
    """Point the datastore and media at a per-test scratch directory."""
    db_file = tmp_path / "dasha_test.db"
    media_dir = tmp_path / "media"

    get_settings.cache_clear()
    # A deployment's real backend/.env (admin key, bootstrap password) must
    # never leak into the suite. Pydantic reads the env file as well as the
    # environment, so deleting an env var alone does not isolate a test; point
    # the file away too. Env vars set below still win over the empty file.
    from newsroom.config import Settings

    monkeypatch.setitem(
        Settings.model_config, "env_file", str(tmp_path / "no-such-file.env")
    )
    monkeypatch.setenv("DATABASE_KIND", "sqlite")
    monkeypatch.setenv("DATABASE_URL", f"sqlite:///{db_file}")
    monkeypatch.setenv("MEDIA_DIR", str(media_dir))
    monkeypatch.setenv("AI_PROVIDER", "heuristic")
    monkeypatch.setenv("NEWSROOM_SECRET", "test-secret-long-enough-for-hmac")
    monkeypatch.setenv("ADMIN_API_KEY", "test-admin-key")
    monkeypatch.setenv("PUBLIC_BASE_URL", "http://test.local")
    monkeypatch.setenv("CORS_ORIGINS", "http://test.local")
    monkeypatch.setenv("AUTO_PUBLISH_ENABLED", "true")
    monkeypatch.setenv("AUTO_PUBLISH_MIN_EVIDENCE", "0.5")
    # The acquisition layer never reaches the network from the test suite:
    # robots is off (no robots.txt to fetch), pacing is zero (no sleeping) and
    # browser automation is off regardless of what a fixture asks for.
    monkeypatch.setenv("RESPECT_ROBOTS_TXT", "false")
    monkeypatch.setenv("POLITENESS_MIN_INTERVAL_SECONDS", "0")
    monkeypatch.setenv("BROWSER_FETCH_ENABLED", "false")
    get_settings.cache_clear()

    db_engine.dispose()
    init_db(drop=True)

    yield get_settings()

    db_engine.dispose()
    get_settings.cache_clear()
    reset_limiter()


@pytest.fixture
def session(isolated_settings):
    from newsroom.db.engine import get_session

    sess = get_session()
    try:
        yield sess
    finally:
        sess.close()


@pytest.fixture
def admin_key():
    return "test-admin-key"


@pytest.fixture
def client(isolated_settings, admin_key, monkeypatch):
    from fastapi.testclient import TestClient

    from newsroom.api.main import create_app

    monkeypatch.setenv("DASHA_DISABLE_SCHEDULER", "1")
    app = create_app(init_datastore=False)
    return TestClient(app, headers={"X-Dasha-Key": admin_key})
