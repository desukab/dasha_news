"""End-to-end API tests: public reader routes and the newsroom console."""

from __future__ import annotations

from datetime import datetime

from newsroom.config import get_settings
from newsroom.db.models import Story, Submission

_STORY_COUNTER = {"n": 0}


def _story(db, **kwargs):
    _STORY_COUNTER["n"] += 1
    number = _STORY_COUNTER["n"]
    base = dict(slug=f"test-story-{number}", section="politics", status="published",
                headline_te="పరీక్ష శీర్షిక", headline_en="Test headline",
                lead_te="పరీక్ష ముఖ్యాంశం", body_te="పరీక్ష వాచకం",
                importance=0.7, evidence_score=0.8, num_sources=2,
                published_at=datetime.utcnow(), updated_at=datetime.utcnow(),
                district="Hyderabad", state="Telangana",
                cluster_id=f"cluster-{number}",
                is_breaking=False, is_developing=False, corrections_count=0,
                version=1, confidence=0.8)
    base.update(kwargs)
    story = Story(**base)
    db.add(story)
    db.commit()
    db.refresh(story)
    return story


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def test_health(client):
    response = client.get("/v1/health")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert body["datastore"] == "ok"


def test_feed_empty(client):
    response = client.get("/v1/feed")
    assert response.status_code == 200
    body = response.json()
    assert body["items"] == []
    assert body["total"] == 0
    assert body["has_more"] is False


def test_feed_returns_published_story(session, client):
    _story(session, headline_te="ఫీడ్ కథ")
    response = client.get("/v1/feed")
    assert response.status_code == 200
    items = response.json()["items"]
    assert len(items) == 1
    assert items[0]["headline_te"] == "ఫీడ్ కథ"
    assert items[0]["section"] == "politics"
    assert items[0]["section_label_te"]


def test_feed_excludes_drafts(session, client):
    _story(session, status="draft")
    assert client.get("/v1/feed").json()["total"] == 0


def test_feed_excludes_killed(session, client):
    _story(session, status="killed")
    assert client.get("/v1/feed").json()["total"] == 0


def test_feed_breaking_first(session, client):
    _story(session, headline_te="సాధారణ కథ", importance=0.4)
    _story(session, headline_te="బ్రేకింగ్ కథ", importance=0.4,
           is_breaking=True, status="breaking")
    items = client.get("/v1/feed").json()["items"]
    assert items[0]["headline_te"] == "బ్రేకింగ్ కథ"
    assert items[0]["is_breaking"] is True


def test_feed_section_filter(session, client):
    _story(session, section="sports")
    _story(session, section="politics")
    items = client.get("/v1/feed?section=sports").json()["items"]
    assert len(items) == 1
    assert items[0]["section"] == "sports"


def test_feed_district_filter(session, client):
    _story(session, district="Warangal")
    _story(session, district="Hyderabad")
    items = client.get("/v1/feed?district=Warangal").json()["items"]
    assert len(items) == 1
    assert items[0]["district"] == "Warangal"


def test_feed_pagination(session, client):
    for index in range(5):
        _story(session)
    first = client.get("/v1/feed?page=1&page_size=2").json()
    assert len(first["items"]) == 2
    assert first["total"] == 5
    assert first["has_more"] is True
    second = client.get("/v1/feed?page=3&page_size=2").json()
    assert second["has_more"] is False


def test_feed_rejects_invalid_page(client):
    assert client.get("/v1/feed?page=0").status_code == 422


def test_breaking_feed(session, client):
    _story(session, is_breaking=True, status="breaking")
    _story(session, is_breaking=False)
    body = client.get("/v1/breaking").json()
    assert body["total"] == 1
    assert body["items"][0]["is_breaking"] is True


def test_developing_feed(session, client):
    _story(session, is_developing=True, status="developing")
    body = client.get("/v1/developing").json()
    assert body["total"] == 1


def test_sections(client):
    body = client.get("/v1/sections").json()
    assert body["primary"]
    assert len(body["all"]) > 20
    slugs = {s["slug"] for s in body["all"]}
    assert {"politics", "sports", "hyderabad"} <= slugs
    for section in body["all"]:
        assert section["te"] and section["en"]


def test_districts(client):
    body = client.get("/v1/districts").json()
    assert body["state"] == "Telangana"
    assert "Hyderabad" in body["districts"]
    assert len(body["districts"]) >= 33


def test_story_detail(session, client):
    story = _story(session)
    body = client.get(f"/v1/story/{story.id}").json()
    assert body["id"] == story.id
    assert body["body_te"] == "పరీక్ష వాచకం"
    assert body["facts"] == []
    assert body["sources"] == []
    assert body["version"] == 1


def test_story_detail_404(session, client):
    assert client.get("/v1/story/99999").status_code == 404


def test_story_detail_hides_draft(session, client):
    story = _story(session, status="draft")
    assert client.get(f"/v1/story/{story.id}").status_code == 404


def test_story_by_slug(session, client):
    story = _story(session, slug="unique-slug")
    body = client.get("/v1/story/by-slug/unique-slug").json()
    assert body["id"] == story.id
    assert client.get("/v1/story/by-slug/missing").status_code == 404


def test_search(session, client):
    _story(session, headline_te="హైదరాబాద్ మెట్రో వార్త")
    _story(session, headline_te="క్రికెట్ మ్యాచ్")
    body = client.get("/v1/search?q=మెట్రో").json()
    assert body["total"] >= 1
    assert "మెట్రో" in body["items"][0]["headline_te"]


def test_search_requires_query(client):
    assert client.get("/v1/search").status_code == 422


def test_search_empty_result(client):
    body = client.get("/v1/search?q=zzzznothing").json()
    assert body["total"] == 0


def test_device_registration(client):
    body = {"device_id": "device-abc-123", "locale": "te", "theme": "dark"}
    response = client.post("/v1/device", json=body)
    assert response.status_code == 200
    assert response.json()["device_id"] == "device-abc-123"
    assert response.json()["theme"] == "dark"


def test_device_registration_validates(client):
    response = client.post("/v1/device", json={"device_id": "short"})
    assert response.status_code == 422


def test_bookmark_roundtrip(session, client):
    story = _story(session)
    device = "device-bookmark-1"
    assert client.post(f"/v1/bookmarks/{story.id}?device_id={device}").json()["bookmarked"] is True
    assert client.get(f"/v1/bookmarks?device_id={device}").json()["total"] == 1
    assert client.delete(f"/v1/bookmarks/{story.id}?device_id={device}").json()["bookmarked"] is False
    assert client.get(f"/v1/bookmarks?device_id={device}").json()["total"] == 0


def test_bookmark_unknown_story(client):
    response = client.post("/v1/bookmarks/99999?device_id=device-bookmark-2")
    assert response.status_code == 404


def test_bookmark_is_idempotent(session, client):
    story = _story(session)
    device = "device-bookmark-3"
    client.post(f"/v1/bookmarks/{story.id}?device_id={device}")
    client.post(f"/v1/bookmarks/{story.id}?device_id={device}")
    assert client.get(f"/v1/bookmarks?device_id={device}").json()["total"] == 1


def test_history_accumulates(session, client):
    story = _story(session)
    device = "device-history-1"
    client.post(f"/v1/history/{story.id}?device_id={device}&read_seconds=30&completed=false")
    client.post(f"/v1/history/{story.id}?device_id={device}&read_seconds=45&completed=true")
    from newsroom.db.models import ReadingHistory
    from sqlalchemy import select

    rows = session.execute(select(ReadingHistory).where(
        ReadingHistory.device_id == device)).scalars().all()
    assert len(rows) == 1
    assert rows[0].read_seconds == 75
    assert rows[0].completed is True


def test_submissions(session, client):
    body = {"device_id": "device-sub-1", "body": "నా ఊరిలో రోడ్డు పనులు లేవు",
            "category": "civic-issues", "location_text": "హైదరాబాద్"}
    response = client.post("/v1/submissions", json=body)
    assert response.status_code == 200
    assert response.json()["status"] == "new"

    from sqlalchemy import select
    rows = session.execute(select(Submission)).scalars().all()
    assert len(rows) == 1
    # Reader tips are never auto-published, and are always untrusted.
    assert rows[0].status == "new"
    assert rows[0].body == "నా ఊరిలో రోడ్డు పనులు లేవు"


def test_submission_rejects_short_body(client):
    response = client.post("/v1/submissions", json={"device_id": "device-sub-2",
                                                    "body": "చిన్నది"})
    assert response.status_code == 422


# ---------------------------------------------------------------------------
# Admin API: auth boundary
# ---------------------------------------------------------------------------

def test_admin_rejects_missing_key(session, client):
    # An explicit empty header overrides the client's default key.
    response = client.get("/admin/status", headers={"X-Dasha-Key": ""})
    assert response.status_code in (401, 403)


def test_admin_rejects_wrong_key(session, client):
    response = client.get("/admin/status", headers={"X-Dasha-Key": "wrong"})
    assert response.status_code in (401, 403)


def test_admin_rejects_bearer_of_wrong_secret(session, client):
    response = client.get("/admin/status",
                          headers={"X-Dasha-Key": "", "Authorization": "Bearer nope"})
    assert response.status_code in (401, 403)


def test_admin_accepts_bearer_token(session, client, monkeypatch):
    from newsroom.security.auth import sign_token

    monkeypatch.setattr("newsroom.security.auth.get_settings",
                        lambda: get_settings())
    token = sign_token("admin")
    response = client.get("/admin/status",
                          headers={"X-Dasha-Key": "", "Authorization": f"Bearer {token}"})
    assert response.status_code == 200


def test_admin_status_works_with_key(client):
    response = client.get("/admin/status")
    assert response.status_code == 200
    body = response.json()
    assert "counts" in body
    assert body["ai_provider"] == "heuristic"


def test_admin_refuses_the_shipped_placeholder_key(client, monkeypatch):
    # The shipped default is published in the source tree, so it is not a
    # secret at all. Anyone who reads this repo must not become an admin by
    # sending it back to us -- even when the operator left it in place.
    from newsroom.config import Settings

    shipped = Settings(admin_api_key="change-me-admin-key",
                       newsroom_secret="test-secret-long-enough-for-hmac")
    monkeypatch.setattr("newsroom.security.auth.get_settings", lambda: shipped)
    monkeypatch.setattr("newsroom.config.get_settings", lambda: shipped)

    response = client.get("/admin/status", headers={"X-Dasha-Key": "change-me-admin-key"})
    assert response.status_code == 503
    # And the refused request must not be a coin-flip with the wrong-key path:
    # the operator has to change the config, not just retry.
    assert response.json()["detail"] == "The newsroom is not configured for admin access."


def test_admin_refuses_a_token_forged_with_the_shipped_secret(client, monkeypatch):
    # The HMAC secret is what makes a signed token unforgeable. Left at the
    # shipped value, an attacker who never touches the newsroom can mint a
    # valid-looking admin token from the source alone.
    from newsroom.config import Settings
    from newsroom.security.auth import sign_token

    shipped = Settings(admin_api_key="test-admin-key",
                       newsroom_secret="change-me-to-a-long-random-string")
    monkeypatch.setattr("newsroom.security.auth.get_settings", lambda: shipped)

    forged = sign_token("admin")  # signed with the placeholder secret
    response = client.get("/admin/status",
                          headers={"X-Dasha-Key": "", "Authorization": f"Bearer {forged}"})
    assert response.status_code == 503


def test_admin_works_once_real_credentials_are_set(client, monkeypatch):
    # The guard is about placeholders, not about the operator's choice of key:
    # a real key over the same boundary still authenticates.
    from newsroom.config import Settings

    real = Settings(admin_api_key="a-real-operators-key",
                    newsroom_secret="test-secret-long-enough-for-hmac")
    monkeypatch.setattr("newsroom.security.auth.get_settings", lambda: real)

    response = client.get("/admin/status", headers={"X-Dasha-Key": "a-real-operators-key"})
    assert response.status_code == 200


def test_admin_stories_list(session, client):
    _story(session, status="draft")
    response = client.get("/admin/stories")
    assert response.status_code == 200
    body = response.json()
    # The console sees drafts; readers must not.
    assert body["total"] >= 1


def test_admin_publish_draft(session, client):
    story = _story(session, status="draft")
    response = client.post(f"/admin/stories/{story.id}/publish")
    assert response.status_code == 200
    session.expire_all()
    assert session.get(Story, story.id).status == "published"


def test_admin_hold_story(session, client):
    story = _story(session, status="auto_published")
    response = client.post(f"/admin/stories/{story.id}/hold")
    assert response.status_code == 200
    session.expire_all()
    assert session.get(Story, story.id).status == "held"


def test_admin_breaking_toggle(session, client):
    story = _story(session)
    response = client.post(f"/admin/stories/{story.id}/breaking")
    assert response.status_code == 200
    session.expire_all()
    assert session.get(Story, story.id).is_breaking is True


def test_admin_kill_story(session, client):
    story = _story(session)
    response = client.post(f"/admin/stories/{story.id}/kill")
    assert response.status_code == 200
    session.expire_all()
    assert session.get(Story, story.id).status == "killed"
    # Killed stories disappear from the reader API.
    assert client.get("/v1/feed").json()["total"] == 0


def test_admin_correction_bumps_version(session, client):
    story = _story(session)
    response = client.post(f"/admin/stories/{story.id}/correct",
                           json={"text_te": "సవరణ: పేరు తప్పు", "text_en": "Correction"})
    assert response.status_code == 200
    session.expire_all()
    refreshed = session.get(Story, story.id)
    assert refreshed.corrections_count == 1
    assert refreshed.version == 2


def test_admin_sources_list(client):
    response = client.get("/admin/sources")
    assert response.status_code == 200
    assert response.json()["total"] >= 0


def test_admin_audit_records_mutations(session, client):
    story = _story(session)
    client.post(f"/admin/stories/{story.id}/hold")
    from newsroom.db.models import AuditLog
    from sqlalchemy import select

    rows = session.execute(select(AuditLog)).scalars().all()
    assert len(rows) >= 1
    assert any("hold" in (row.action or "") for row in rows)


def test_admin_submissions_triage(session, client):
    submission = Submission(device_id="device-triage-1",
                            body="ఫిర్యాదు వివరాలు ఇక్కడ", status="new")
    session.add(submission)
    session.commit()
    response = client.post(f"/admin/submissions/{submission.id}/triage",
                           json={"status": "verified", "note": "సమీక్షలో"})
    assert response.status_code == 200


def test_admin_submissions_triage_rejects_bad_status(session, client):
    submission = Submission(device_id="device-triage-2",
                            body="ఫిర్యాదు వివరాలు", status="new")
    session.add(submission)
    session.commit()
    response = client.post(f"/admin/submissions/{submission.id}/triage",
                           json={"status": "published-directly"})
    assert response.status_code == 400


def test_media_path_traversal_blocked(client):
    # The media route must refuse to escape its mount point.
    assert client.get("/media/audio/../../etc/passwd").status_code == 404
    assert client.get("/media/audio/..%2f..%2fetc%2fpasswd").status_code == 404
    # Unknown media kind is rejected, not served from a sibling directory.
    assert client.get("/media/secrets/../../etc/passwd").status_code == 404
    # A missing file in a valid kind is a plain 404.
    assert client.get("/media/audio/does-not-exist.mp3").status_code == 404
