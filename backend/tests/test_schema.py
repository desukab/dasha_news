"""Regression tests for datastore schema migration.

``Base.metadata.create_all()`` only creates missing *tables*: it will not add
a column a later release introduced to a table that already exists. An
upgraded deployment therefore crashed with "no such column" on its first
query. These tests pin the additive migration that brings an existing
datastore forward instead.
"""

from __future__ import annotations

from sqlalchemy import inspect, text

from newsroom.db.engine import get_engine, init_db

# The column set the first release shipped for `sources`. Anything added since
# must be backfilled by the migration, never assumed present.
_LEGACY_SOURCE_COLUMNS = (
    "id", "guid", "name", "site_url", "feed_url", "kind", "language",
    "trust_score", "default_section", "is_enabled", "is_breaking_capable",
    "last_fetched_at", "fetch_error_count", "created_at",
)

_LEGACY_SOURCE_DEFS = (
    "id INTEGER PRIMARY KEY",
    "guid TEXT NOT NULL",
    "name TEXT NOT NULL",
    "site_url TEXT",
    "feed_url TEXT",
    "kind TEXT",
    "language TEXT",
    "trust_score FLOAT",
    "default_section TEXT",
    "is_enabled BOOLEAN",
    "is_breaking_capable BOOLEAN",
    "last_fetched_at DATETIME",
    "fetch_error_count INTEGER",
    "created_at DATETIME",
)


def _columns(engine, table: str) -> set:
    inspector = inspect(engine)
    return {column["name"] for column in inspector.get_columns(table)}


def _revert_sources_to_legacy(engine) -> None:
    """Rebuild `sources` with the original column set and one real row.

    This stands in for a datastore created by an older release that was never
    recreated -- the exact state an operator upgrades from.
    """
    with engine.begin() as connection:
        connection.execute(text("DROP TABLE sources"))
        connection.execute(text(f"CREATE TABLE sources ({', '.join(_LEGACY_SOURCE_DEFS)})"))
        connection.execute(
            text(
                "INSERT INTO sources (id, guid, name, site_url, feed_url, kind, "
                "language, trust_score, is_enabled, is_breaking_capable, "
                "fetch_error_count, created_at) "
                "VALUES (1, 'seed:demo', 'డెమో దినపత్రిక', 'https://demo.test', "
                "'https://demo.test/rss', 'rss', 'te', 0.7, 1, 0, 0, CURRENT_TIMESTAMP)"
            )
        )


def test_missing_columns_are_added_without_losing_data(isolated_settings):
    engine = get_engine()
    full = _columns(engine, "sources")

    _revert_sources_to_legacy(engine)
    # The datastore is now exactly what the first release would have built.
    assert _columns(engine, "sources") == set(_LEGACY_SOURCE_COLUMNS)

    added = init_db(drop=False)

    assert added >= 1
    assert _columns(engine, "sources") == full
    with engine.connect() as connection:
        row = connection.execute(
            text("SELECT guid, fetch_backend, requires_js, politeness_seconds FROM sources")
        ).fetchone()
    # The pre-existing row survives and is backfilled, not discarded.
    assert row.guid == "seed:demo"
    assert row.fetch_backend == "httpx"
    assert bool(row.requires_js) is False


def test_migrated_table_is_queryable_through_the_orm(isolated_settings):
    """The point of the migration is that normal newsroom code works again."""
    engine = get_engine()
    _revert_sources_to_legacy(engine)
    init_db(drop=False)

    from newsroom.db.engine import get_session
    from newsroom.db.models import Source

    with get_session() as session:
        sources = session.query(Source).all()
    assert len(sources) == 1
    assert sources[0].fetch_backend == "httpx"
    assert sources[0].requires_js is False


def test_migration_is_idempotent(isolated_settings):
    """Booting twice on an up-to-date datastore must be a no-op."""
    engine = get_engine()
    before = _columns(engine, "sources")
    init_db(drop=False)
    second_pass = init_db(drop=False)
    assert second_pass == 0
    assert _columns(engine, "sources") == before
