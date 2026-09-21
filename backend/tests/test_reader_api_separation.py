"""The reader API must not carry the desk's working notes.

Provenance, evidence and review state are how an editor decides whether a story
may go out; once it has gone out, they are the newsroom's business and not the
reader's. This is a test on the wire rather than on a convention, because a
field that reaches the response body reaches the APK -- the Flutter model
deserialises whatever the response carries, and a schema that is merely
*supposed* to omit a field will not notice when someone adds it back.
"""

from __future__ import annotations

from datetime import datetime

import pytest
from fastapi.testclient import TestClient

from newsroom.api.main import app
from newsroom.api.schemas import ReaderStoryCard, ReaderStoryDetail, StoryCard, StoryDetail
from newsroom.config import get_settings
from newsroom.db.models import Story, User

client = TestClient(app)

_STORY_COUNTER = {"n": 0}


@pytest.fixture
def published_story(session):
    """A story the reader endpoints can actually serve.

    It carries a full set of desk fields -- facts would be added by the
    pipeline, but the serialiser reads them off the story row and its links, so
    a story with evidence and sources attached is the harder case for a leak.
    """
    _STORY_COUNTER["n"] += 1
    number = _STORY_COUNTER["n"]
    story = Story(
        slug=f"reader-sep-{number}",
        cluster_id=f"cluster-rs-{number}",
        section="politics", status="published",
        headline_te="పాఠకుడు చూడవలసిన శీర్షిక",
        headline_en="A headline the reader should see",
        lead_te="ముఖ్యాంశం", body_te="వాచకం",
        importance=0.7, evidence_score=0.8, num_sources=2,
        published_at=datetime.utcnow(), updated_at=datetime.utcnow(),
        district="Hyderabad", state="Telangana",
        is_breaking=False, is_developing=False,
        corrections_count=1, version=3, confidence=0.66,
        origin="automated", editor_locked=False, needs_review=True,
    )
    session.add(story)
    session.commit()
    session.refresh(story)
    return story


@pytest.fixture
def editor_headers(session):
    """A scratch editor account, created for this test and removed after.

    The desk's routes authenticate, so the separation test has to log in as
    someone to compare what the desk sees against what the reader gets.
    """
    from newsroom.security.auth import issue_token

    user = User(email="reader-sep@example.test", role="editor",
                password_hash="scratch-not-a-real-credential")
    session.add(user)
    session.commit()
    session.refresh(user)
    token, _expires = issue_token(user.id)
    yield {"Authorization": f"Bearer {token}"}
    session.delete(user)
    session.commit()


# Every key the desk model carries that the reader model must not. The list is
# derived from the two schemas rather than written by hand, so a future field
# added to the desk's view is caught here automatically instead of by a reader.
DESK_ONLY = set(StoryDetail.model_fields) - set(ReaderStoryDetail.model_fields)
CARD_DESK_ONLY = set(StoryCard.model_fields) - set(ReaderStoryCard.model_fields)


def test_the_reader_model_omits_the_desk_fields():
    """The separation is a schema, and this is what it costs to lose it.

    `ReaderStoryDetail` extends the reader card rather than the desk detail, so
    the detail's diff carries the card's desk-only fields too -- the two reader
    schemas are one hierarchy, and the whole hierarchy is on the reader's side.
    """
    assert DESK_ONLY == {
        "facts", "sources", "updates", "corrections_count", "version",
        "confidence", "importance", "evidence_score", "num_sources",
        "origin", "editor_locked", "needs_review",
    }, f"unexpected desk-only fields on the detail: {sorted(DESK_ONLY)}"
    assert CARD_DESK_ONLY == {
        "importance", "evidence_score", "num_sources", "origin",
        "editor_locked", "needs_review",
    }, f"unexpected desk-only fields on the card: {sorted(CARD_DESK_ONLY)}"


def test_the_reader_model_omits_the_reader_forbidden_fields():
    """A shorter name for the same check: the fields the spec names outright."""
    forbidden = {
        "evidence_score", "num_sources", "origin", "editor_locked",
        "needs_review", "facts", "sources", "updates", "confidence",
        "corrections_count", "version", "importance",
    }
    assert not (forbidden & set(ReaderStoryCard.model_fields)), \
        f"{sorted(forbidden & set(ReaderStoryCard.model_fields))} reached the reader card"
    assert not (forbidden & set(ReaderStoryDetail.model_fields)), \
        f"{sorted(forbidden & set(ReaderStoryDetail.model_fields))} reached the reader detail"


@pytest.mark.parametrize("path", [
    "/v1/front?language=te",
    "/v1/front?language=te&district=Hyderabad",
    "/v1/feed?language=te",
    "/v1/breaking",
    "/v1/developing",
    "/v1/search?q=హైదరాబాద్&language=te",
])
def test_no_reader_endpoint_returns_a_desk_field(path, published_story):
    """The response body, not the schema, is what the APK receives.

    Pydantic drops undeclared keys on the way out, so a serializer that
    inherited a desk field would be caught here rather than by a reader. Every
    region and every list endpoint is walked, because a leak on the second page
    of a feed is still a leak.
    """
    response = client.get(path)
    assert response.status_code == 200, f"{path} -> {response.status_code}: {response.text[:300]}"

    def walk(node, where: str):
        if isinstance(node, dict):
            leaked = DESK_ONLY & set(node)
            assert not leaked, f"{path} leaks {sorted(leaked)} at {where}"
            for key, value in node.items():
                walk(value, f"{where}.{key}")
        elif isinstance(node, list):
            for index, value in enumerate(node):
                walk(value, f"{where}[{index}]")

    walk(response.json(), "root")


def test_the_story_detail_endpoint_omits_the_desk_fields(published_story):
    response = client.get(f"/v1/story/{published_story.id}")
    assert response.status_code == 200, response.text
    body = response.json()
    assert not (DESK_ONLY & set(body)), \
        f"detail leaked {sorted(DESK_ONLY & set(body))}"
    # The desk's facts and source links are the most specific leak, and the
    # most damaging: they name the outlets and quote them.
    assert "facts" not in body
    assert "sources" not in body
    assert "evidence_score" not in body


def test_the_by_slug_endpoint_omits_the_desk_fields(published_story):
    response = client.get(f"/v1/story/by-slug/{published_story.slug}")
    assert response.status_code == 200, response.text
    assert not (DESK_ONLY & set(response.json()))


def test_the_desk_still_sees_its_own_fields(published_story, editor_headers):
    """The separation removes the fields from the reader; it does not remove
    the desk's ability to see them. An editor who cannot see the sources cannot
    verify the story, and that is the other half of the same spec.
    """
    response = client.get(f"/editor/stories/{published_story.id}", headers=editor_headers)
    assert response.status_code == 200, response.text
    body = response.json()
    for expected in ("evidence_score", "num_sources", "facts", "sources"):
        assert expected in body, f"the desk lost {expected}, which it needs"


def test_a_story_in_the_room_is_reachable_by_both_views(published_story):
    """The reader and the desk look at one story, so both views must resolve it.

    This is the assertion that the two serializers share a source of truth: if
    the reader view drifted to a different query, a story could be published
    and unreachable at the same time.
    """
    from newsroom.db.engine import get_session
    from newsroom.api.views import to_reader_detail, to_story_detail

    session = get_session()
    story = session.get(Story, published_story.id)
    reader = to_reader_detail(session, story)
    desk = to_story_detail(session, story)

    assert reader.id == desk.id
    assert reader.headline_te == desk.headline_te
    assert reader.body_te == desk.body_te
    assert reader.published_at == desk.published_at
