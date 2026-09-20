"""Reader submissions: the tip reaches the desk, and never the feed directly.

A reader tip is a lead, not evidence. These tests pin the two sides of that
rule: an editor must be able to see and triage what readers sent, and no path
in the API may turn an unverified submission into a published story on its own.
"""

from __future__ import annotations

from datetime import datetime, timedelta

import pytest
from fastapi.testclient import TestClient

from newsroom.api.main import create_app
from newsroom.db.models import (
    AuditLog,
    Fact,
    Job,
    Role,
    Source,
    Story,
    Submission,
    User,
)
from newsroom.domain.evidence import EvidenceLevel
from newsroom.security.auth import hash_password

TIP_TE = (
    "కాజీపేటలో వాహనాల తనిఖీల సందర్భంగా రద్దు చేసిన పాత కరెన్సీ భారీగా "
    "పట్టుబడింది. ఎనిమిది మందిని పోలీసులు అరెస్ట్ చేశారు. దర్యాప్తు కొనసాగుతోంది."
)
TIP_EN = "Old currency seized in Kazipet; eight arrested, police said."


@pytest.fixture
def app(isolated_settings):
    return create_app(init_datastore=False)


def _user(db, email="editor@test", role=Role.EDITOR.value, password="secret-password"):
    user = User(email=email, display_name=email.split("@")[0],
                password_hash=hash_password(password), role=role, is_active=True)
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


def _client_for(app, token=None):
    headers = {}
    if token:
        headers["X-Dasha-Token"] = token
    return TestClient(app, headers=headers)


def _login(client, email="editor@test", password="secret-password"):
    response = client.post("/editor/session", json={"email": email, "password": password})
    assert response.status_code == 200, response.text
    return response.json()["token"]


def _submission(db, *, body=TIP_TE, status="new", contact="శేఖర్ రెడ్డి",
                location_text="వరంగల్", created_at=None, category=None):
    submission = Submission(
        device_id="dasha-test-device",
        body=body, category=category, location_text=location_text,
        contact=contact, status=status, created_at=created_at or datetime.utcnow())
    db.add(submission)
    db.commit()
    db.refresh(submission)
    return submission


def _editor_client(app, db):
    _user(db)
    return _client_for(app, _login(_client_for(app)))


# ---------------------------------------------------------------------------
# Visibility: the desk can see what readers sent
# ---------------------------------------------------------------------------

def test_editor_can_list_submissions(app, session):
    older = _submission(session, body="మొదటి సమాచారం.",
                         created_at=datetime.utcnow() - timedelta(hours=2))
    newer = _submission(session, body="రెండవ సమాచారం.",
                        created_at=datetime.utcnow())
    response = _editor_client(app, session).get("/editor/submissions")
    assert response.status_code == 200, response.text
    payload = response.json()
    ids = [item["id"] for item in payload["items"]]
    assert ids == sorted(ids, reverse=True), "the queue must be newest first"
    assert ids.index(newer.id) < ids.index(older.id)
    assert payload["new_count"] == 2

    # Every field the desk's queue needs is present on the row.
    item = payload["items"][0]
    for field in ("id", "headline", "body", "category", "location_text", "contact",
                  "media_path", "status", "triage_note", "story_id", "created_at"):
        assert field in item, f"{field} missing from the submission payload"


def test_the_queue_headline_is_the_submitters_first_line(app, session):
    submission = _submission(session, body=(
        f"{TIP_TE}\n\nఇది రెండవ పేరా, దీన్ని క్యూలో చూపించకూడదు."))
    item = _editor_client(app, session).get("/editor/submissions").json()["items"][0]
    assert item["id"] == submission.id
    # The label is the reader's own opening sentence, nothing invented and
    # nothing from further down the tip.
    assert item["headline"].startswith("కాజీపేటలో")
    assert item["headline"].endswith("పట్టుబడింది")
    assert "రెండవ పేరా" not in item["headline"]
    assert "అరెస్ట్" not in item["headline"]
    # The raw text is still carried in full for the detail view.
    assert item["body"] == submission.body


def test_detail_endpoint_shows_the_whole_submission_untouched(app, session):
    submission = _submission(session)
    response = _editor_client(app, session).get(f"/editor/submissions/{submission.id}")
    assert response.status_code == 200, response.text
    assert response.json()["body"] == submission.body, (
        "the desk must judge the tip on what was actually typed")


def test_unknown_submission_is_a_404(app, session):
    response = _editor_client(app, session).get("/editor/submissions/9999")
    assert response.status_code == 404


# ---------------------------------------------------------------------------
# Authorisation: submissions carry a submitter's contact details
# ---------------------------------------------------------------------------

def test_anonymous_cannot_list_submissions(app, session):
    _submission(session)
    assert _client_for(app).get("/editor/submissions").status_code == 401
    assert _client_for(app).get("/editor/submissions/1").status_code == 401


def test_a_reader_account_cannot_list_submissions(app, session):
    """Contact details are PII; the queue is editor-only, not any-login."""
    _user(session, email="reader@test", role=Role.USER.value)
    token = _login(_client_for(app), email="reader@test")
    client = _client_for(app, token)
    assert client.get("/editor/submissions").status_code == 403
    assert client.post("/editor/submissions/1/triage", json={"status": "verified"}).status_code == 403
    assert client.post("/editor/submissions/1/story").status_code == 403


def test_triage_needs_an_editor(app, session):
    _user(session, email="reader@test", role=Role.USER.value)
    token = _login(_client_for(app), email="reader@test")
    response = _client_for(app, token).post(
        "/editor/submissions/1/triage", json={"status": "verified"})
    assert response.status_code in (403, 404)


# ---------------------------------------------------------------------------
# Triage
# ---------------------------------------------------------------------------

def test_triage_records_the_status_and_a_note(app, session):
    submission = _submission(session)
    client = _editor_client(app, session)
    response = client.post(f"/editor/submissions/{submission.id}/triage",
                           json={"status": "verified",
                                 "note": "Confirmed with the SHO by phone."})
    assert response.status_code == 200, response.text
    session.refresh(submission)
    assert submission.status == "verified"
    assert submission.triage_note == "Confirmed with the SHO by phone."


def test_triage_rejects_a_status_that_would_publish(app, session):
    """No editor action relabels a submission 'published'.

    Taking a tip to the feed is a story action. Keeping 'published' out of the
    allowed set is what makes the triage endpoint unable to imply the tip went
    out, even if a client asks for it directly.
    """
    submission = _submission(session)
    response = _editor_client(app, session).post(
        f"/editor/submissions/{submission.id}/triage",
        json={"status": "published"})
    assert response.status_code == 400, response.text
    session.refresh(submission)
    assert submission.status == "new", "a rejected status must not be written"


def test_triage_writes_an_audit_row(app, session):
    submission = _submission(session)
    _editor_client(app, session).post(
        f"/editor/submissions/{submission.id}/triage",
        json={"status": "rejected", "note": "Duplicate of a story already out."})
    rows = session.query(AuditLog).filter(
        AuditLog.target_type == "submission",
        AuditLog.target_id == str(submission.id)).all()
    assert any(r.action == "submission_triage" for r in rows)
    assert any(r.detail == "rejected" for r in rows)


def test_status_filter_narrows_the_queue(app, session):
    _submission(session, body="కొత్తది.", status="new")
    _submission(session, body="చూసినది.", status="triaged")
    client = _editor_client(app, session)
    assert {i["status"] for i in client.get(
        "/editor/submissions?status=new").json()["items"]} == {"new"}
    assert {i["status"] for i in client.get(
        "/editor/submissions?status=triaged").json()["items"]} == {"triaged"}


def test_unknown_status_filter_is_rejected(app, session):
    client = _editor_client(app, session)
    assert client.get("/editor/submissions?status=published").status_code == 400
    assert client.get("/editor/submissions?status=nonsense").status_code == 400


# ---------------------------------------------------------------------------
# Conversion to a story: provenance preserved, evidence honest
# ---------------------------------------------------------------------------

def test_conversion_creates_an_unpublished_draft_linked_back(app, session):
    submission = _submission(session)
    response = _editor_client(app, session).post(
        f"/editor/submissions/{submission.id}/story",
        json={"headline_te": "కాజీపేట్‌లో పాత కరెన్సీ పట్టుబడింది"})
    assert response.status_code == 201, response.text
    story_id = response.json()["id"]

    story = session.get(Story, story_id)
    assert story.status == "draft", "a tip becomes a draft, never a published story"
    assert story.origin == "manual"
    session.refresh(submission)
    assert submission.story_id == story.id, "the submission must point at what it became"


def test_conversion_carries_the_tip_as_unverified_not_as_fact(app, session):
    """The one rule the whole workflow exists to keep.

    A reader's say-so lands on the story at UNVERIFIED evidence and is
    attributed to the submitter by name. It must not be recorded as a verified
    fact, and it must not carry enough weight to clear the auto-publish gate
    on its own.
    """
    submission = _submission(session, contact="శేఖర్ రెడ్డి")
    client = _editor_client(app, session)
    story_id = client.post(f"/editor/submissions/{submission.id}/story").json()["id"]

    facts = session.query(Fact).filter(Fact.story_id == story_id).all()
    assert facts, "the submission's text must travel onto the story"
    for fact in facts:
        assert fact.evidence_level == EvidenceLevel.UNVERIFIED.value
        assert fact.attributed_to == "శేఖర్ రెడ్డి"
        assert fact.text_te == submission.body


def test_conversion_writes_auditable_provenance(app, session):
    submission = _submission(session)
    story_id = _editor_client(app, session).post(
        f"/editor/submissions/{submission.id}/story").json()["id"]

    actions = {(r.action, r.target_type) for r in session.query(AuditLog).all()}
    assert ("submission_to_story", "submission") in actions
    assert ("story_create", "story") in actions

    # The update timeline records where the story came from, in both languages.
    story = session.get(Story, story_id)
    notes = [(u.kind, u.text_te, u.text_en) for u in story.updates]
    assert any(f"{submission.id}" in (n[1] or "") for n in notes)
    assert any(f"{submission.id}" in (n[2] or "") for n in notes)


def test_a_submission_can_only_become_a_story_once(app, session):
    submission = _submission(session)
    client = _editor_client(app, session)
    first = client.post(f"/editor/submissions/{submission.id}/story")
    assert first.status_code == 201
    second = client.post(f"/editor/submissions/{submission.id}/story")
    assert second.status_code == 409, "converting twice would orphan the audit trail"
    assert session.query(Story).filter(Story.origin == "manual").count() == 1


def test_the_story_carries_the_submission_location(app, session):
    submission = _submission(session, location_text="వరంగల్")
    story_id = _editor_client(app, session).post(
        f"/editor/submissions/{submission.id}/story").json()["id"]
    assert session.get(Story, story_id).district == "వరంగల్"


def test_an_english_tip_is_not_silently_telugu(app, session):
    """The tip is stored in whatever script the reader typed it in.

    Nothing in the conversion path translates, so an English tip must not be
    relabelled as Telugu content on the story.
    """
    submission = _submission(session, body=TIP_EN, contact="A Reader")
    story_id = _editor_client(app, session).post(
        f"/editor/submissions/{submission.id}/story").json()["id"]
    story = session.get(Story, story_id)
    assert story.headline_te in (None, "")
    fact = session.query(Fact).filter(Fact.story_id == story_id).one()
    assert fact.text_te == TIP_EN
    assert fact.text_en is None


def test_conversion_never_publishes_even_if_asked(app, session):
    """A client cannot smuggle a status past the conversion endpoint."""
    submission = _submission(session)
    story_id = _editor_client(app, session).post(
        f"/editor/submissions/{submission.id}/story",
        json={"status": "published"}).json()["id"]
    assert session.get(Story, story_id).status == "draft"
    assert session.get(Story, story_id).published_at is None


# ---------------------------------------------------------------------------
# The two editor 500s, pinned so they cannot return
# ---------------------------------------------------------------------------

def test_the_manual_origin_filter_works(app, session):
    """origin=manual was a 500: StoryOrigin has no allowed() classmethod."""
    _user(session)
    token = _login(_client_for(app))
    client = _client_for(app, token)
    assert client.get("/editor/stories?origin=manual").status_code == 200
    assert client.get("/editor/stories?origin=automated").status_code == 200
    assert client.get("/editor/stories?origin=bogus").status_code == 400


def test_the_failure_queue_works(app, session):
    """pipeline/failures was a 500: Job has no updated_at, kind or last_error."""
    from newsroom.db.models import Article

    source = Source(guid="test-feed", name="A feed",
                    site_url="https://example.test",
                    feed_url="https://example.test/rss", language="te")
    session.add(source)
    session.commit()
    session.add(Article(source_id=source.id, guid="https://example.test/a",
                        url="https://example.test/a",
                        title_raw="ఒక వైఫల్యం", status="failed",
                        rejection_reason="boom"))
    session.add(Job(stage="sweep", status="failed", attempts=2, error="boom"))
    session.commit()

    _user(session)
    client = _client_for(app, _login(_client_for(app)))
    response = client.get("/editor/pipeline/failures")
    assert response.status_code == 200, response.text
    payload = response.json()
    assert payload["articles"][0]["reason"] == "boom"
    assert payload["jobs"][0]["kind"] == "sweep"
    assert payload["jobs"][0]["error"] == "boom"


# ---------------------------------------------------------------------------
# The admin-key path stays open for existing tooling
# ---------------------------------------------------------------------------

def test_the_admin_submission_endpoint_still_exists(app, session):
    from newsroom.config import get_settings

    _submission(session)
    key = get_settings().admin_api_key
    response = _client_for(app).get("/admin/submissions",
                                    headers={"X-Dasha-Key": key})
    assert response.status_code == 200, response.text
    assert response.json()["submissions"], (
        "tooling that already uses the admin path must keep working")
