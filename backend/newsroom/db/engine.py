"""Database engine, sessions and schema lifecycle."""

from __future__ import annotations

import logging
from contextlib import contextmanager
from typing import Iterator, Optional

from sqlalchemy import create_engine, event
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.schema import ColumnDefault

from newsroom.config import get_settings
from newsroom.db.models import Base

logger = logging.getLogger(__name__)

_engine: Optional[Engine] = None
_SessionLocal: Optional[sessionmaker] = None


def _build_engine(database_url: str) -> Engine:
    connect_args: dict = {}
    if database_url.startswith("sqlite"):
        connect_args["check_same_thread"] = False
    engine = create_engine(
        database_url,
        connect_args=connect_args,
        pool_pre_ping=True,
        future=True,
    )

    @event.listens_for(engine, "connect")
    def _set_sqlite_pragmas(dbapi_connection, _record) -> None:  # pragma: no cover
        if database_url.startswith("sqlite"):
            cursor = dbapi_connection.cursor()
            cursor.execute("PRAGMA journal_mode=WAL")
            cursor.execute("PRAGMA foreign_keys=ON")
            cursor.execute("PRAGMA synchronous=NORMAL")
            cursor.close()

    return engine


def get_engine() -> Engine:
    global _engine, _SessionLocal
    if _engine is None:
        settings = get_settings()
        url = settings.effective_database_url
        logger.info("Connecting to datastore: %s", _redact(url))
        _engine = _build_engine(url)
        _SessionLocal = sessionmaker(bind=_engine, autoflush=False, autocommit=False)
    return _engine


def get_db() -> Iterator[Session]:
    """FastAPI dependency."""
    session = get_session()
    try:
        yield session
    finally:
        session.close()


def get_session() -> Session:
    if _SessionLocal is None:
        get_engine()
    assert _SessionLocal is not None
    return _SessionLocal()


@contextmanager
def db_scope() -> Iterator[Session]:
    """Context manager that commits on success and rolls back on error."""
    session = get_session()
    try:
        yield session
        session.commit()
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()


def init_db(drop: bool = False) -> None:
    """Create all tables. `drop=True` is used by tests for isolation."""
    engine = get_engine()
    if drop:
        Base.metadata.drop_all(engine)
    Base.metadata.create_all(engine)
    # create_all() only creates missing *tables*: it will not add a column a
    # later release introduced to a table that already exists, so an upgraded
    # deployment would crash with "no such column" on its first query. Bring
    # the datastore forward instead.
    return _sync_columns(engine)


def _sync_columns(engine: Engine) -> int:
    """Additive-only migration: add columns the models declare but the
    datastore lacks.

    It deliberately never drops, renames or retypes anything, so it is safe to
    run on every boot and never loses data. A column added this way carries a
    server-side DEFAULT when the model defines a literal one, which
    backfills existing rows -- without it, ``ADD COLUMN ... NOT NULL`` is
    rejected on a non-empty table.
    """
    from sqlalchemy import inspect, text

    inspector = inspect(engine)
    preparer = engine.dialect.identifier_preparer
    applied = 0
    for table_name, table in Base.metadata.tables.items():
        if not inspector.has_table(table_name):
            continue
        existing = {column["name"] for column in inspector.get_columns(table_name)}
        for column in table.columns:
            if column.name in existing:
                continue
            # Keys and constraint-backed columns need a table rewrite, not an
            # additive ALTER; the fresh-table path already handles them.
            if column.primary_key or column.foreign_keys or column.server_default is not None:
                logger.warning(
                    "schema: %s.%s exists in the model but not the datastore and "
                    "cannot be added by an additive ALTER; it will be NULL until "
                    "the table is recreated",
                    table_name, column.name,
                )
                continue
            value = _column_default_value(column)
            type_ddl = column.type.compile(dialect=engine.dialect)
            ddl = (
                f"ALTER TABLE {preparer.quote(table_name)} "
                f"ADD COLUMN {preparer.quote(column.name)} {type_ddl}"
            )
            if value is not None:
                # Backfill existing rows so the NOT NULL below is accepted.
                processor = column.type.literal_processor(engine.dialect)
                if processor is None:
                    literal = str(value)
                else:
                    # 2.0 returns the coercion callable directly; 1.4 returned
                    # an object exposing ``process``.
                    literal = processor(value) if callable(processor) else processor.process(value)
                ddl += f" NOT NULL DEFAULT {literal}"
            elif not column.nullable:
                # Adding a NOT NULL column with no default to a non-empty table
                # is impossible; keep the boot working and let the ORM apply
                # its Python-level default on the next write.
                logger.warning(
                    "schema: %s.%s is NOT NULL with no default; adding it nullable",
                    table_name, column.name,
                )
            with engine.begin() as connection:
                connection.execute(text(ddl))
            applied += 1
            logger.info("schema: added column %s.%s", table_name, column.name)
    return applied


def _column_default_value(column):
    """The literal a column's Python-level default resolves to, or ``None``.

    ``None`` covers "no default" and "a default too dynamic to render as a
    literal" (a callable that is not a plain constant), both of which are
    handled by letting the column be nullable.
    """
    default = column.default
    if not isinstance(default, ColumnDefault):
        return None
    arg = default.arg
    if default.is_callable:
        return None
    return arg


def _redact(url: str) -> str:
    if "@" in url and "://" in url:
        scheme, rest = url.split("://", 1)
        if "@" in rest:
            creds, host = rest.split("@", 1)
            return f"{scheme}://***@{host}"
    return url


def dispose() -> None:
    global _engine, _SessionLocal
    if _engine is not None:
        _engine.dispose()
    _engine = None
    _SessionLocal = None
