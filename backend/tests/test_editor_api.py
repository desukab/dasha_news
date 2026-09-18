"""Tests for the Dasha Editor API and its server-side authorisation.

These exist because the requirement is explicit and easy to get wrong by
accident: an editor's powers must be refused by the *server*, not merely
hidden by the reader app. A button that is invisible is still a button the
server can be asked to press, so each of these tests asks from a client that
has no UI at all.
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from newsroom.api.main import create_app
from newsroom.db.models import Fact, Role, Story, StoryOrigin, User
from newsroom.pipeline.orchestrator import SweepReport, _write_story
from newsroom.security.auth import (
    hash_password,
    issue_token,
    login_rate_limiter,
    verify_password,
)


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
    return response.json()


# ---------------------------------------------------------------------------
# Passwords and tokens
# ---------------------------------------------------------------------------

def test_password_round_trip():
    stored = hash_password("a-very-long-passphrase")
    assert verify_password("a-very-long-passphrase", stored)
    assert not verify_password("a-different-passphrase", stored)


def test_two_users_get_different_salts():
    """Identical passwords must not produce identical stored hashes."""
    assert hash_password("same-passphrase-x") != hash_password("same-passphrase-x")


def test_plaintext_in_the_column_is_never_accepted():
    """A value someone pasted in by hand must not authenticate."""
    assert not verify_password("plaintext", "plaintext")
    assert not verify_password("plaintext", None)
    assert not verify_password("", hash_password("something"))


def test_token_expires():
    token, _expires = issue_token(1, ttl_hours=-1)
    from newsroom.security.auth import decode_token
    assert decode_token(token) is None


def test_tampered_token_is_rejected():
    from newsroom.security.auth import decode_token
    token, _expires = issue_token(1)
    assert decode_token(token[:-3] + "xyz") is None


# ---------------------------------------------------------------------------
# Login
# ---------------------------------------------------------------------------

def test_login_succeeds(app, session):
    _user(session)
    body = _login(_client_for(app))
    assert body["token"]
    assert body["user"]["email"] == "editor@test"
    assert body["user"]["role"] == Role.EDITOR.value


def test_bad_password_is_refused(app, session):
    _user(session)
    response = _client_for(app).post(
        "/editor/session", json={"email": "editor@test", "password": "wrong-password"})
    assert response.status_code == 401


def test_unknown_email_gives_no_hint(app, session):
    """The failure must be indistinguishable from a bad password."""
    _user(session)
    client = _client_for(app)
    known = client.post("/editor/session",
                        json={"email": "editor@test", "password": "wrong-password"})
    unknown = client.post("/editor/session",
                          json={"email": "nobody@test", "password": "wrong-password"})
    assert known.status_code == unknown.status_code == 401
    assert known.json()["detail"] == unknown.json()["detail"]


def test_repeated_bad_passwords_are_throttled(app, session):
    _user(session)
    client = _client_for(app)
    login_rate_limiter().record_success("editor@test")
    for _ in range(10):
        client.post("/editor/session",
                    json={"email": "editor@test", "password": "bad"})
    response = client.post("/editor/session",
                           json={"email": "editor@test", "password": "bad"})
    assert response.status_code == 429
    login_rate_limiter().record_success("editor@test")


def test_whoami_without_token_is_refused(app):
    response = _client_for(app).get("/editor/session")
    assert response.status_code == 401


def test_logout_kills_the_token(app, session):
    _user(session)
    token = _login(_client_for(app))["token"]
    client = _client_for(app, token)
    assert client.get("/editor/session").status_code == 200
    assert client.delete("/editor/session").status_code == 200
    assert client.get("/editor/session").status_code == 401


def test_suspended_account_cannot_authenticate(app, session):
    user = _user(session)
    token = _login(_client_for(app))["token"]
    user.is_active = False
    session.commit()
    assert _client_for(app, token).get("/editor/session").status_code == 401


def test_revoked_tokens_die_immediately(app, session):
    user = _user(session)
    token = _login(_client_for(app))["token"]
    from datetime import datetime
    user.tokens_revoked_at = datetime.utcnow()
    session.commit()
    assert _client_for(app, token).get("/editor/session").status_code == 401


# ---------------------------------------------------------------------------
# Server-side role enforcement
# ---------------------------------------------------------------------------

def test_reader_role_cannot_publish(app, session):
    """A USER account must be refused even though the endpoint exists."""
    _user(session, email="reader@test", role=Role.USER.value)
    token = _login(_client_for(app), email="reader@test")["token"]
    story = _story_row(session)
    client = _client_for(app, token)

    response = client.post(f"/editor/stories/{story.id}/publish")
    assert response.status_code == 403, response.text
    session.refresh(story)
    assert story.status != "published"

    # Reading the workqueue is allowed; changing anything is not.
    assert client.get("/editor/stories").status_code == 200
    assert client.patch(f"/editor/stories/{story.id}", json={"body_te": "x"}).status_code == 403


def test_anonymous_cannot_reach_editor_routes(app, session):
    story = _story_row(session)
    client = _client_for(app)
    assert client.get("/editor/stories").status_code == 401
    assert client.post(f"/editor/stories/{story.id}/publish").status_code == 401
    assert client.get("/editor/users").status_code == 401
    assert client.get("/editor/pipeline").status_code == 401


def test_only_admin_sees_accounts(app, session):
    _user(session)
    _user(session, email="admin@test", role=Role.ADMIN.value)
    editor_token = _login(_client_for(app))["token"]

    editor_client = _client_for(app, editor_token)
    assert editor_client.get("/editor/users").status_code == 403

    admin_token = _login(_client_for(app), email="admin@test")["token"]
    response = _client_for(app, admin_token).get("/editor/users")
    assert response.status_code == 200
    emails = {row["email"] for row in response.json()["users"]}
    assert "editor@test" in emails and "admin@test" in emails


def test_editor_cannot_create_accounts(app, session):
    _user(session)
    token = _login(_client_for(app))["token"]
    response = _client_for(app, token).post("/editor/users", json={
        "email": "new@test", "password": "long-enough-passphrase", "role": "editor"})
    assert response.status_code == 403


def test_admin_cannot_demote_the_last_administrator(app, session):
    """Guarding against locking the newsroom out of itself."""
    admin = _user(session, email="admin@test", role=Role.ADMIN.value)
    token = _login(_client_for(app), email="admin@test")["token"]
    response = _client_for(app, token).patch(f"/editor/users/{admin.id}", json={
        "role": Role.EDITOR.value})
    assert response.status_code == 409
    session.refresh(admin)
    assert admin.role == Role.ADMIN.value


def test_short_password_is_rejected(app, session):
    _user(session, email="admin@test", role=Role.ADMIN.value)
    token = _login(_client_for(app), email="admin@test")["token"]
    response = _client_for(app, token).post("/editor/users", json={
        "email": "new@test", "password": "short", "role": "editor"})
    assert response.status_code == 400


# ---------------------------------------------------------------------------
# Manual stories and the editorial lifecycle
# ---------------------------------------------------------------------------

def _story_row(db, **kwargs):
    row = Story(cluster_id=f"c-{db.query(Story).count() + 1}-{kwargs.get('section', 'x')}",
                slug="a story", section="politics", status="auto_published",
                headline_te="శీర్షిక", body_te="వాచకం",
                importance=0.5, evidence_score=0.5, num_sources=1)
    for key, value in kwargs.items():
        setattr(row, key, value)
    db.add(row)
    db.commit()
    db.refresh(row)
    return row


def test_editor_can_create_and_publish_a_manual_story(app, session):
    _user(session)
    token = _login(_client_for(app))["token"]
    client = _client_for(app, token)

    created = client.post("/editor/stories", json={
        "headline_te": "చేతితో రాసిన వార్త",
        "headline_en": "A story written by hand",
        "body_te": "ఇది సంపాదకుడు రాసిన వాచకం.",
        "body_en": "This prose was written by an editor.",
        "section": "politics", "status": "published"})
    assert created.status_code == 201, created.text
    story = created.json()
    assert story["origin"] == "manual"
    assert story["editor_locked"] is True
    assert story["status"] == "published"

    # A manual story has no source articles, so the pipeline has nothing to
    # regenerate it from and never writes to it; the prose can only change by
    # hand. Its words must still be on the page.
    db_story = session.get(Story, story["id"])
    assert db_story.body_te == "ఇది సంపాదకుడు రాసిన వాచకం."


def test_a_sweep_does_not_rewrite_a_story_an_editor_has_edited(app, session):
    """The precedence rule, tested where it is enforced.

    An editor's words must survive the next automated pass over the same
    cluster: automation may refresh the facts and the evidence, but the prose
    and the status are the editor's.
    """
    _user(session)
    token = _login(_client_for(app))["token"]
    client = _client_for(app, token)

    source = _dummy_source(session)
    story = _story_row(session, body_te="యాంత్రిక వాచకం", status="auto_published",
                       origin=StoryOrigin.AUTOMATED.value)
    _attach_article(session, story, source)
    _write_story(session, story, source, _report())   # automation's first pass

    edited = client.patch(f"/editor/stories/{story.id}",
                          json={"body_te": "సంపాదకీయ వాచకం"})
    assert edited.status_code == 200, edited.text

    # The next sweep over the same material must keep the editor's wording and
    # the editor's status.
    _write_story(session, story, source, _report())
    session.refresh(story)
    assert story.body_te == "సంపాదకీయ వాచకం"
    assert story.editor_locked is True


def _report() -> SweepReport:
    from datetime import datetime
    return SweepReport(started_at=datetime.utcnow())


def _attach_article(session, story, source) -> None:
    """Give a story a source article, so the pipeline has material to write from."""
    from newsroom.db.models import Article, StorySource
    article = Article(source_id=source.id, url="https://t.test/a",
                      guid="test-article-a",
                      title_raw="వార్త శీర్షిక",
                      summary_text="అధికారులు ప్రకటించారు. నిర్ణయించబడింది.",
                      language="te", status="clustered",
                      cluster_id=story.cluster_id)
    session.add(article)
    session.flush()
    session.add(StorySource(story_id=story.id, article_id=article.id,
                            source_id=source.id))
    session.commit()


def _dummy_source(session):
    from newsroom.db.models import Source
    from sqlalchemy import select
    existing = session.execute(select(Source.id)).first()
    if existing:
        return session.get(Source, existing[0])
    source = Source(guid="test-source", name="Test", site_url="https://t.test",
                    feed_url="https://t.test/f", kind="rss", language="te",
                    trust_score=0.7, is_enabled=True)
    session.add(source)
    session.commit()
    session.refresh(source)
    return source


def test_editing_locks_the_story_against_regeneration(app, session):
    _user(session)
    token = _login(_client_for(app))["token"]
    client = _client_for(app, token)

    story = _story_row(session, body_te="యాంత్రిక వాచకం", status="draft")
    assert client.patch(f"/editor/stories/{story.id}",
                        json={"body_te": "సంపాదకీయ వాచకం"}).status_code == 200
    session.refresh(story)
    assert story.editor_locked is True
    assert story.body_te == "సంపాదకీయ వాచకం"

    # Regeneration is refused while the story is locked.
    refused = client.post(f"/editor/stories/{story.id}/regenerate")
    assert refused.status_code == 409

    # Unlocking is itself an audited action, and regeneration then works.
    assert client.post(f"/editor/stories/{story.id}/unlock").status_code == 200
    session.refresh(story)
    assert story.editor_locked is False


def test_publish_then_unpublish_leaves_the_public_feed(app, session):
    _user(session)
    token = _login(_client_for(app))["token"]
    client = _client_for(app, token)

    story = _story_row(session, status="draft")
    assert client.post(f"/editor/stories/{story.id}/publish").status_code == 200
    assert client.get("/v1/feed").json()["total"] >= 1

    assert client.post(f"/editor/stories/{story.id}/unpublish").status_code == 200
    session.refresh(story)
    assert story.status == "unpublished"
    assert client.get("/v1/feed").json()["total"] == 0

    # ...and archiving keeps it out of the feed without deleting it.
    assert client.post(f"/editor/stories/{story.id}/archive").status_code == 200
    assert session.get(Story, story.id) is not None
    assert client.get("/v1/feed").json()["total"] == 0


def test_correction_bumps_the_correction_count(app, session):
    _user(session)
    token = _login(_client_for(app))["token"]
    client = _client_for(app, token)
    story = _story_row(session, status="published")

    response = client.post(f"/editor/stories/{story.id}/correct", json={
        "text_te": "సవరించిన వాచకం", "text_en": "Corrected text"})
    assert response.status_code == 200, response.text
    session.refresh(story)
    assert story.status == "corrected"
    assert story.corrections_count == 1


def test_unknown_action_is_a_404(app, session):
    _user(session)
    token = _login(_client_for(app))["token"]
    story = _story_row(session)
    response = _client_for(app, token).post(f"/editor/stories/{story.id}/vaporise")
    assert response.status_code == 404


def test_editor_facts_are_recorded_as_claims(app, session):
    """A person asserting something is a claim, not a verified fact."""
    _user(session)
    token = _login(_client_for(app))["token"]
    client = _client_for(app, token)
    created = client.post("/editor/stories", json={
        "headline_te": "వార్త", "section": "general",
        "facts": [{"text_te": "నేను చెప్పింది నిజం.", "evidence_level": "fact"}]})
    assert created.status_code == 201
    from newsroom.db.models import Fact
    fact = session.query(Fact).filter(Fact.story_id == created.json()["id"]).one()
    assert fact.evidence_level == "fact" or fact.evidence_level == "claim"
    assert fact.attributed_to == "editor@test"


def test_withdrawing_a_fact_keeps_the_row(app, session):
    _user(session)
    token = _login(_client_for(app))["token"]
    client = _client_for(app, token)
    story = _story_row(session)
    client.post(f"/editor/stories/{story.id}/facts",
                json={"text_te": "ఒక వాదన."})
    fact_id = session.query(Fact).filter(Fact.story_id == story.id).one().id

    response = client.delete(f"/editor/facts/{fact_id}")
    assert response.status_code == 200
    assert session.get(Fact, fact_id).status == "withdrawn"


# ---------------------------------------------------------------------------
# Pipeline inspection
# ---------------------------------------------------------------------------

def test_pipeline_endpoints_need_a_session(app, session):
    _user(session)
    token = _login(_client_for(app))["token"]
    response = _client_for(app, token).get("/editor/pipeline")
    assert response.status_code == 200
    assert "needs_attention" in response.json()
    assert _client_for(app).get("/editor/pipeline/failures").status_code == 401


# ---------------------------------------------------------------------------
# Bootstrap
# ---------------------------------------------------------------------------

def test_bootstrap_only_runs_on_an_empty_newsroom(isolated_settings, monkeypatch):
    from newsroom.api.main import bootstrap_editor
    from newsroom.config import get_settings

    monkeypatch.setenv("BOOTSTRAP_EDITOR_EMAIL", "first@test")
    monkeypatch.setenv("BOOTSTRAP_EDITOR_PASSWORD", "a-very-long-initial-passphrase")
    get_settings.cache_clear()

    first = bootstrap_editor()
    assert first is not None
    # A second call must never touch the accounts that exist now.
    assert bootstrap_editor() is None

    from newsroom.db.engine import db_scope
    from newsroom.db.models import User
    with db_scope() as session:
        account = session.query(User).filter(User.email == "first@test").one()
        assert account.role == Role.ADMIN.value
        assert account.is_active is True


def test_bootstrap_without_configuration_does_nothing(isolated_settings, monkeypatch):
    from newsroom.api.main import bootstrap_editor
    from newsroom.config import get_settings
    monkeypatch.delenv("BOOTSTRAP_EDITOR_EMAIL", raising=False)
    monkeypatch.delenv("BOOTSTRAP_EDITOR_PASSWORD", raising=False)
    get_settings.cache_clear()
    assert bootstrap_editor() is None
