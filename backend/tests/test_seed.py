"""Tests for the zero-config source seed.

This suite exists because the seed list once shipped thirteen feeds of which
only three still answered. Every one of them counted as a healthy source in
the dashboard while acquisition ingested nothing, and nothing in the test
suite noticed -- a quiet failure is worse than a loud one, so the list is now
tested rather than trusted.
"""

from __future__ import annotations

import os

import pytest
from sqlalchemy import select

from newsroom.db.models import Source
from newsroom.db.seed import BREAKING_CAPABLE, SEED_SOURCES, seed_sources


@pytest.fixture
def seeded(session):
    """Seed into the isolated test datastore and return the session."""
    seed_sources()
    session.commit()
    return session


def test_seed_creates_every_shipped_source(seeded):
    rows = seeded.execute(select(Source).where(Source.guid.like("seed:%"))).scalars().all()
    assert {row.guid for row in rows} == {f"seed:{entry['site_slug']}" for entry in SEED_SOURCES}


def test_seed_is_idempotent(seeded):
    before = seeded.query(Source).count()
    assert seed_sources() == 0
    assert seeded.query(Source).count() == before


def test_every_seed_entry_declares_a_kind_and_language():
    """``kind`` defaulted silently to rss once, which broke HTML sources."""
    for entry in SEED_SOURCES:
        assert entry.get("kind") in ("rss", "html"), entry["site_slug"]
        assert entry["lang"] in ("te", "en"), entry["site_slug"]


def test_breaking_capable_is_a_subset_of_the_shipped_list():
    assert BREAKING_CAPABLE <= {entry["site_slug"] for entry in SEED_SOURCES}


def test_seed_retires_sources_it_no_longer_ships(session):
    """A feed removed from the list must be disabled, not fetched forever."""
    session.add(Source(guid="seed:retired-outlet", name="Gone Daily",
                       site_url="https://gone.test", feed_url="https://gone.test/feed",
                       kind="rss", language="te", trust_score=0.7, is_enabled=True))
    session.commit()

    seed_sources()
    session.commit()

    retired = session.execute(
        select(Source).where(Source.guid == "seed:retired-outlet")
    ).scalar_one()
    assert retired.is_enabled is False, \
        "a retired seed should be disabled, not deleted -- its history is still cited"


def test_seed_never_touches_sources_added_by_an_editor(session):
    """Hand-added sources are a person's decision, not ours to disable."""
    session.add(Source(guid="editor:my-outlet", name="My Outlet",
                       site_url="https://mine.test", feed_url="https://mine.test/feed",
                       kind="rss", language="te", trust_score=0.7, is_enabled=True))
    session.commit()

    seed_sources()
    session.commit()

    kept = session.execute(
        select(Source).where(Source.guid == "editor:my-outlet")
    ).scalar_one()
    assert kept.is_enabled is True


# ---------------------------------------------------------------------------
# Live verification -- opt in, because it fetches the real internet.
# ---------------------------------------------------------------------------

_LIVE = pytest.mark.skipif(
    not os.environ.get("DASHA_LIVE_TESTS"),
    reason="set DASHA_LIVE_TESTS=1 to fetch the seeded feeds for real",
)


@_LIVE
@pytest.mark.parametrize("entry", SEED_SOURCES, ids=[e["site_slug"] for e in SEED_SOURCES])
def test_shipped_feed_is_reachable_and_permitted(entry, session):
    """Every shipped feed must answer with items, and robots must allow it.

    This is the guard that keeps the list honest. Publishers retire feeds
    without notice, so when this fails the fix is to re-verify the outlet and
    either correct the URL or drop the source -- not to loosen the assertion.
    """
    from newsroom.acquisition.context import context_for_source
    from newsroom.acquisition.registry import adapter_for_kind

    source = Source(guid=f"live:{entry['site_slug']}", name=str(entry["name"]),
                    site_url=str(entry["site"]), feed_url=str(entry["feed"]),
                    kind=str(entry.get("kind") or "rss"),
                    language=str(entry["lang"]), trust_score=0.7, is_enabled=True)
    session.add(source)
    session.commit()

    ctx = context_for_source(source, session=session)
    adapter = adapter_for_kind(source.kind)
    items = adapter.discover(source, ctx)

    assert items, f"{entry['site_slug']} returned no items"
    for item in items:
        assert item.title and item.url, f"{entry['site_slug']} produced an item with no title or URL"
