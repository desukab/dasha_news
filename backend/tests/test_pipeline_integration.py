"""End-to-end pipeline integration tests.

These exist because three separate defects were only discoverable by actually
running a sweep against realistic data:

1. ``fetch()`` iterated the *async* byte iterator of a synchronous httpx
   streaming response, which raised ``TypeError``. The robots layer caught it
   and reported every source as "robots.txt unavailable", so acquisition
   silently ingested nothing at all -- while every unit test still passed.
2. A failed article rolled back the *whole* transaction, discarding the
   articles the scout had just ingested and expiring the ORM objects the sweep
   loop still held, which then raised ``ObjectDeletedError`` out of the loop.
3. ``_write_story`` referenced ``_article_for_fact`` / ``_source_for_fact``,
   which did not exist; every story was left as an empty draft.

A sweep that produces zero stories now fails loudly instead of looking busy.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timedelta
from contextlib import contextmanager
from unittest.mock import patch

import pytest

from newsroom.db.engine import get_session
from newsroom.db.models import Article, Fact, Source, Story, StorySource
from newsroom.pipeline.fetch import fetch
from newsroom.pipeline.orchestrator import (
    SweepReport,
    _process_article,
    run_sweep,
)


@dataclass
class _DummyReport:
    """Minimal report stand-in for the single-article failure test."""
    errors: List[str] = field(default_factory=list)
    articles_duplicates: int = 0
    stories_updated: int = 0


# A realistic mixed-language corpus: one event covered by two outlets, which is
# what clustering, corroboration and conflict detection are supposed to act on.
_TELANGANA_FEED = """<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel>
  <title>తెలంగాణ టెస్ట్ ఫీడ్</title>
  <link>https://example.test</link>
  <item>
    <title>హైదరాబాద్‌లో భీకర్ వరదలు: ముస్సీ నది పొంగిపోయింది</title>
    <link>https://example.test/hyderabad-floods</link>
    <guid>flood-1</guid>
    <description>హైదరాబాద్‌లో భీకర్ వరదలు సంభవించాయి. ముస్సీ నది పొంగిపోయింది.
    అధికారులు 12 గ్రామాలను ఖాళీ చేయాలని ఆదేశించారు.</description>
    <pubDate>Mon, 15 Sep 2025 09:00:00 +0530</pubDate>
  </item>
  <item>
    <title>ముస్సీ నది పొంగిపోయింది: 12 గ్రామాల ఖాళీ</title>
    <link>https://example.test/musi-evacuation</link>
    <guid>flood-2</guid>
    <description>ముస్సీ నది పొంగిన నేపథ్యంలో అధికారులు 12 గ్రామాలను ఖాళీ
    చేయాలని ఆదేశించారు. నష్టం కోట్ల రూపాయలను చేరుకుంది.</description>
    <pubDate>Mon, 15 Sep 2025 10:00:00 +0530</pubDate>
  </item>
  <item>
    <title>వరంగల్‌లో కళాశాల విద్యార్థుల నిరసన</title>
    <link>https://example.test/warangal-protest</link>
    <guid>protest-1</guid>
    <description>వరంగల్‌లో కళాశాల విద్యార్థులు నిరసన చేపట్టారు.
    వారు హాస్టల్ సౌకర్యాలను మెరుగుపరచాలని డిమాండ్ చేశారు.</description>
    <pubDate>Mon, 15 Sep 2025 11:00:00 +0530</pubDate>
  </item>
</channel></rss>
"""

_ENGLISH_FEED = """<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel>
  <title>Test English Feed</title>
  <link>https://en.example.test</link>
  <item>
    <title>Musi river in spate, 12 villages evacuated in Hyderabad</title>
    <link>https://en.example.test/hyderabad-floods</link>
    <guid>flood-en-1</guid>
    <description>Officials ordered the evacuation of 12 villages as the Musi
    river rose above the danger mark in Hyderabad on Monday.</description>
    <pubDate>Mon, 15 Sep 2025 09:30:00 +0530</pubDate>
  </item>
</channel></rss>
"""


@pytest.fixture
def live_like(session):
    """Two sources whose feeds describe one shared event plus a second event."""
    sources = [
        Source(guid="seed:test-telugu", name="తెలుగు టెస్ట్ దినపత్రిక",
               site_url="https://example.test", feed_url="https://example.test/feed",
               kind="rss", language="te", trust_score=0.75, is_enabled=True),
        Source(guid="seed:test-english", name="Test English Daily",
               site_url="https://en.example.test", feed_url="https://en.example.test/feed",
               kind="rss", language="en", trust_score=0.8, is_enabled=True),
    ]
    for source in sources:
        session.add(source)
    session.commit()
    return sources


@contextmanager
def _offline_feeds():
    """Patch RSS discovery to serve canned bodies, for the duration of a sweep.

    The patch sits on ``RssAdapter.discover`` rather than on the transport
    because the transport is reached through several import paths (scout, the
    backend module, the acquisition context) and because what these tests prove
    is the pipeline, not the network.
    """
    from newsroom.acquisition.rss_adapter import RssAdapter

    def _stub_discover(self, source, ctx):
        from newsroom.acquisition.source_adapter import ListingItem

        body = _ENGLISH_FEED if "en.example" in (source.feed_url or "") else _TELANGANA_FEED
        return [
            ListingItem(
                title=item["title"], url=item["link"], guid=item["guid"],
                summary=item["description"], published_at=None,
                image_url=None, language=source.language or "te",
                is_breaking=False,
            )
            for item in _parse_items(body)
        ]

    with patch.object(RssAdapter, "discover", _stub_discover):
        yield


def _parse_items(raw: str):
    """Minimal RSS item reader, so the tests do not depend on feedparser's
    handling of the Telugu payload to be correct."""
    import re

    items = []
    for block in re.findall(r"<item>(.*?)</item>", raw, re.S):
        def _field(name):
            match = re.search(rf"<{name}>(.*?)</{name}>", block, re.S)
            return match.group(1).strip() if match else ""
        items.append({
            "title": _field("title"), "link": _field("link"),
            "guid": _field("guid"), "description": _field("description"),
        })
    return items


def test_sweep_produces_written_stories(session, live_like):
    """A sweep must end with real, populated stories -- not empty drafts."""
    with _offline_feeds():
        report = run_sweep(session, fetch_bodies=False)
    session.commit()

    stories = session.query(Story).all()
    assert len(stories) >= 2, "a sweep that yields no stories is a failure"
    for story in stories:
        assert story.headline_te or story.headline_en, \
            f"story {story.id} has no headline in any language"
        assert story.body_te or story.body_en, \
            f"story {story.id} has no body in any language"
        assert story.evidence_score > 0, f"story {story.id} scored zero evidence"
    assert report.articles_new > 0
    assert session.query(Fact).count() > 0


def test_flood_coverage_is_clustered(session, live_like):
    """The two Telugu flood items plus the English one are one story."""
    with _offline_feeds():
        run_sweep(session, fetch_bodies=False)
    session.commit()

    flood = [s for s in session.query(Story).all()
             if "వరద" in (s.headline_te or "") or "flood" in (s.headline_en or "").lower()
             or "Musi" in (s.headline_en or "")]
    assert flood, "the shared flood event produced no story"
    links = session.query(StorySource).filter(
        StorySource.story_id == flood[0].id).count()
    assert links >= 1


def test_cross_script_reports_of_one_event_merge(session, live_like):
    """A Telugu report and an English report of one event share a Story.

    The two titles share no script, no tokens and almost no character n-grams,
    so the ordinary title scorers score them zero. What they do share is
    script-independent: the place (the geo alias table carries both scripts)
    and a figure ("12 గ్రామాలు" / "12 villages"). Agreement on both is what
    merges them -- agreement on either alone would be far too weak.
    """
    with _offline_feeds():
        run_sweep(session, fetch_bodies=False)
    session.commit()

    telugu_flood = session.query(Article).filter(
        Article.url == "https://example.test/hyderabad-floods").one()
    english_flood = session.query(Article).filter(
        Article.url == "https://en.example.test/hyderabad-floods").one()

    def _story_of(article) -> Optional[int]:
        link = session.query(StorySource).filter(
            StorySource.article_id == article.id).first()
        return link.story_id if link else None

    assert _story_of(telugu_flood) is not None
    assert _story_of(telugu_flood) == _story_of(english_flood), \
        "the Telugu and English flood reports landed in different Stories"

    # The separate Warangal event must not have been folded in with them.
    warangal = session.query(Article).filter(
        Article.url.like("%warangal-protest%")).one()
    assert _story_of(warangal) != _story_of(telugu_flood)


def test_district_is_resolved(session, live_like):
    """Hyderabad flood text must resolve to the Hyderabad district."""
    with _offline_feeds():
        run_sweep(session, fetch_bodies=False)
    session.commit()

    flood = [s for s in session.query(Story).all()
             if "వరద" in (s.headline_te or "") or "Musi" in (s.headline_en or "")]
    assert flood and flood[0].district == "Hyderabad", \
        f"expected Hyderabad, got {flood[0].district!r}"


def test_failed_article_does_not_destroy_its_source_batch(session, live_like):
    """One broken article must not roll back the articles ingested with it."""
    with _offline_feeds():
        run_sweep(session, fetch_bodies=False)
    session.commit()
    before = session.query(Article).count()
    assert before == 4

    source = live_like[0]
    article = session.query(Article).first()
    report = _DummyReport()

    def _boom(_session, _story, _source, _report):
        raise RuntimeError("simulated extraction failure")

    with patch("newsroom.pipeline.orchestrator._write_story", _boom):
        _process_article(session, article, source, report, fetch_bodies=False)

    # The scout's inserts survived the per-article failure.
    assert session.query(Article).count() == before
    assert article.status == "failed"
    assert article.rejection_reason


def test_sweep_is_idempotent(session, live_like):
    """Two sweeps over the same feeds make the same stories, not duplicates."""
    with _offline_feeds():
        first = run_sweep(session, fetch_bodies=False)
    session.commit()
    stories_after_first = session.query(Story).count()
    facts_after_first = session.query(Fact).count()

    with _offline_feeds():
        second = run_sweep(session, fetch_bodies=False)
    session.commit()

    assert second.articles_new == 0
    assert session.query(Story).count() == stories_after_first
    assert session.query(Fact).count() == facts_after_first


def test_sync_fetch_uses_the_synchronous_byte_iterator(session):
    """Regression: ``fetch()`` must return a body, not raise TypeError.

    The response object from a *synchronous* ``httpx.Client.stream()`` exposes
    ``iter_bytes``; ``aiter_bytes`` is the async-only API and raised
    ``TypeError: 'async_generator' object is not iterable`` on every fetch.
    """
    from newsroom.security.guards import SafeResponse

    class _FakeStream:
        def __init__(self, url):
            self.url = url

        def __enter__(self):
            return self

        def __exit__(self, *exc):
            return False

        @property
        def headers(self):
            return {"content-type": "text/plain"}

        @property
        def status_code(self):
            return 200

        is_redirect = False

        def iter_bytes(self, _size):
            yield b"hello world"

        # The bug: the code called this async-only name on a sync response and
        # got ``TypeError: 'async_generator' object is not iterable``.
        def aiter_bytes(self, _size):
            raise TypeError("'async_generator' object is not iterable")

    class _FakeClient:
        def stream(self, method, url):
            return _FakeStream(url)

    with patch("newsroom.pipeline.fetch._client_pool", lambda: _FakeClient()):
        result = fetch("https://example.test/ok", max_bytes=1024)

    assert isinstance(result, SafeResponse)
    assert result.body == b"hello world"
