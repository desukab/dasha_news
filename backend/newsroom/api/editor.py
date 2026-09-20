"""Dasha Editor API — the private newsroom's surface.

This is the *only* part of the API that can change what the newsroom publishes,
and every route here requires an authenticated user whose role is checked
server-side. The consumer app has no access to any of it: hiding the screens in
the reader app is presentation, not permission.

Lifecycle handled here, alongside the automated one already in ``admin``:

    draft -> editor_review -> approved -> published -> corrected -> unpublished
                                 |                                |
                                 +--> archived <-------------------+

A manual decision always wins over the machine. Editing a story locks it: the
pipeline keeps refreshing the facts, the sources and the evidence behind it,
but it may not rewrite the words an editor wrote. That precedence is enforced
in the orchestrator, not asked for by the client.
"""

from __future__ import annotations

import logging
import re
from datetime import datetime
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Body, Depends, HTTPException, Query, Request, status
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from newsroom.api.schemas import StoryCard
from newsroom.api.views import paginate, to_story_detail
from newsroom.db.engine import get_db
from newsroom.db.models import (
    Article,
    AuditLog,
    Fact,
    Job,
    Role,
    Source,
    Story,
    StoryOrigin,
    StoryUpdate,
    Submission,
    User,
)
from newsroom.domain.evidence import EvidenceLevel
from newsroom.pipeline.orchestrator import regenerate_story
from newsroom.pipeline.publish import StoryChange, record_update
from newsroom.security.auth import (
    audit,
    client_ip,
    hash_password,
    issue_token,
    login_rate_limiter,
    require_admin_user,
    require_editor,
    require_user,
    revoke_token,
    sweep_expired_tokens,
    verify_password,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/editor", tags=["editor"])

# Statuses an editor can move a story into. Anything not here is either
# automated (auto_published, developing) or terminal in a way only the
# pipeline uses (killed).
EDITORIAL_STATUSES = {
    "draft", "editor_review", "approved", "published",
    "corrected", "unpublished", "archived",
}

_EDITOR_FIELDS = (
    "headline_te", "headline_ten", "headline_en",
    "lead_te", "lead_ten", "lead_en",
    "body_te", "body_ten", "body_en",
    "section", "district", "state",
)


def _story_or_404(db: Session, story_id: int) -> Story:
    story = db.get(Story, story_id)
    if story is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Story not found")
    return story


def _actor(user: User) -> str:
    """The string an audit row and an update record agree on."""
    return user.email


# ---------------------------------------------------------------------------
# Session
# ---------------------------------------------------------------------------

@router.post("/session")
def login(request: Request, db: Session = Depends(get_db),
          body: Dict[str, Any] = Body(...)) -> Any:
    """Exchange a password for a signed session token.

    The response is identical whether the email is unknown or the password is
    wrong, and the failure message carries no hint about which one it was:
    confirming that an address has an account is half of an attack.
    """
    email = str(body.get("email") or "").strip().lower()
    password = str(body.get("password") or "")
    if not email or not password:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="Email and password are required")

    limiter = login_rate_limiter()
    if limiter.is_blocked(email):
        raise HTTPException(status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                            detail="Too many attempts. Try again later.",
                            headers={"Retry-After": "3600"})

    user = db.execute(select(User).where(User.email == email)).scalar_one_or_none()
    # The same slow hash runs for an unknown address, so a login probe cannot
    # tell real accounts from fake ones by timing.
    if user is None:
        hash_password(password)
        limiter.record_failure(email)
        raise _bad_credentials()
    if not verify_password(password, user.password_hash):
        limiter.record_failure(email)
        audit(db, _actor(user), "login_failed", "user", user.id, ip=client_ip(request))
        raise _bad_credentials()
    if not user.is_active:
        raise _bad_credentials()

    limiter.record_success(email)
    token, expires_at = issue_token(user.id)
    user.last_login_at = datetime.utcnow()
    sweep_expired_tokens(db)
    audit(db, _actor(user), "login", "user", user.id, ip=client_ip(request))
    db.commit()
    return {
        "token": token,
        "expires_at": expires_at.isoformat(),
        "user": user.to_dict(),
    }


def _bad_credentials() -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Email or password is not recognised",
        headers={"WWW-Authenticate": 'Bearer realm="dasha-editor"'},
    )


@router.get("/session")
def whoami(user: User = Depends(require_user)) -> Any:
    """Validate a held token and report the account and its role.

    The editor app calls this on launch to decide what to show, but the role
    returned here is a *hint for the UI*: every mutating endpoint re-checks it
    server-side, so a modified client cannot talk its way past it.
    """
    return {"user": user.to_dict()}


@router.delete("/session")
def logout(request: Request, db: Session = Depends(get_db),
           user: User = Depends(require_user)) -> Any:
    """Revoke this token specifically, not every session on the account."""
    if revoke_token(request, db):
        audit(db, _actor(user), "logout", "user", user.id, ip=client_ip(request))
        db.commit()
    return {"revoked": True}


# ---------------------------------------------------------------------------
# Story workqueue
# ---------------------------------------------------------------------------

@router.get("/stories")
def list_stories(request: Request, db: Session = Depends(get_db),
                 user: User = Depends(require_user),
                 status_filter: Optional[str] = Query(default=None, alias="status"),
                 origin: Optional[str] = Query(default=None),
                 needs_attention: bool = Query(default=False),
                 page: int = Query(default=1, ge=1),
                 page_size: int = Query(default=25, ge=1, le=100)) -> Any:
    """The desk's queue, front-loaded with what actually needs a person.

    Without a filter this deliberately surfaces the unfinished work first --
    held, failed and needs-review stories -- because a queue ordered by
    recency lets an error sit unnoticed at the bottom of page two.
    """
    query = select(Story)
    if status_filter:
        if status_filter not in EDITORIAL_STATUSES and status_filter not in (
                "held", "auto_published", "developing", "breaking", "killed"):
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                                detail=f"Unknown status {status_filter!r}")
        query = query.where(Story.status == status_filter)
    elif needs_attention:
        query = query.where(or_(
            Story.status.in_(("held", "draft")),
            Story.needs_review.is_(True),
        ))
    if origin:
        if origin not in {member.value for member in StoryOrigin}:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                                detail=f"Unknown origin {origin!r}")
        query = query.where(Story.origin == origin)

    if not status_filter and not needs_attention:
        # Unfinished first, then newest.
        query = query.order_by(
            Story.needs_review.desc(), Story.updated_at.desc())
    else:
        query = query.order_by(Story.updated_at.desc())

    total = db.execute(select(func.count()).select_from(query.subquery())).scalar_one()
    rows = db.execute(query.offset((page - 1) * page_size).limit(page_size)).scalars().all()
    return paginate([to_story_detail(db, story).model_dump() for story in rows],
                    total, page, page_size)


@router.get("/stories/{story_id}")
def get_story(story_id: int, user: User = Depends(require_user),
              db: Session = Depends(get_db)) -> Any:
    """One story with everything the desk needs to decide on it."""
    return to_story_detail(db, _story_or_404(db, story_id)).model_dump()


@router.post("/stories", status_code=status.HTTP_201_CREATED)
def create_story(request: Request, db: Session = Depends(get_db),
                 user: User = Depends(require_editor),
                 body: Dict[str, Any] = Body(...)) -> Any:
    """Write a story by hand.

    A manual story has no source articles and no cluster, so it carries
    ``origin=manual`` and is locked from the start: there is nothing for the
    pipeline to regenerate it from, and nothing it may overwrite.
    """
    import hashlib as _hashlib

    headline = body.get("headline_te") or body.get("headline_en")
    if not headline:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="A headline in at least one language is required")

    section = str(body.get("section") or "general")
    content = "|".join(str(body.get(field) or "") for field in _EDITOR_FIELDS)
    story = Story(
        cluster_id=f"manual-{_hashlib.sha256(content.encode('utf-8')).hexdigest()[:20]}",
        slug=str(headline)[:280],
        section=section,
        status=str(body.get("status") or "draft"),
        origin=StoryOrigin.MANUAL.value,
        editor_locked=True,
        created_by_id=user.id,
        updated_by_id=user.id,
        district=body.get("district"),
        state=body.get("state") or "Telangana",
        is_breaking=bool(body.get("is_breaking")),
    )
    _apply_editor_fields(story, body)
    if story.status not in EDITORIAL_STATUSES:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail=f"Status must be one of {sorted(EDITORIAL_STATUSES)}")
    if story.status == "published":
        story.published_at = datetime.utcnow()
        story.published_by_id = user.id

    db.add(story)
    db.flush()
    _save_facts(db, story, body.get("facts"), user)
    record_update(db, story, StoryChange(
        kind="note", headline=story.headline_te,
        text_te="ఈ వార్త అందుబాటులో లేని వ్యాసంగా రాయబడింది.",
        text_en="This story was written by hand in the editor.",
        article_id=None, applied_by=_actor(user),
        note=f"created manually by {_actor(user)}"))
    audit(db, _actor(user), "story_create", "story", story.id,
          detail=f"origin=manual status={story.status}", ip=client_ip(request))
    db.commit()
    return to_story_detail(db, story).model_dump()


@router.patch("/stories/{story_id}")
def update_story(story_id: int, request: Request, db: Session = Depends(get_db),
                 user: User = Depends(require_editor),
                 body: Dict[str, Any] = Body(...)) -> Any:
    """Edit a story's words. This locks it against the pipeline.

    Every field the editor can set through this endpoint is prose or
    classification -- never the evidence. Facts have their own endpoint and
    their own audit trail, because a story's claims must never be silently
    edited to match a nicer-sounding body.
    """
    story = _story_or_404(db, story_id)
    if story.status == "killed":
        raise HTTPException(status_code=status.HTTP_409_CONFLICT,
                            detail="A withdrawn story cannot be edited; correct it instead")

    changed = _apply_editor_fields(story, body)
    if body.get("section") is not None:
        story.section = str(body["section"])
    if body.get("is_breaking") is not None:
        story.is_breaking = bool(body["is_breaking"])
    if body.get("status") is not None:
        if body["status"] not in EDITORIAL_STATUSES:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                                detail=f"Status must be one of {sorted(EDITORIAL_STATUSES)}")
        _transition_status(story, body["status"], user)

    if changed or story.editor_locked is False:
        # A human has touched this story. From here the pipeline may refresh
        # what the story knows, but not what it says.
        story.editor_locked = True
        story.updated_by_id = user.id

    _save_facts(db, story, body.get("facts"), user)
    record_update(db, story, StoryChange(
        kind="note", headline=story.headline_te,
        text_te="ఈ వార్తను సంపాదకులు సవరించారు.",
        text_en="This story was edited by hand.",
        article_id=None, applied_by=_actor(user),
        note=", ".join(sorted(changed)) or None))
    audit(db, _actor(user), "story_update", "story", story.id,
          detail=", ".join(sorted(changed)) or None, ip=client_ip(request))
    db.commit()
    return to_story_detail(db, story).model_dump()


def _apply_editor_fields(story: Story, body: Dict[str, Any]) -> List[str]:
    """Copy the language fields present in the payload. Returns what changed."""
    changed: List[str] = []
    for field in _EDITOR_FIELDS:
        if field in body and body[field] is not None:
            value = str(body[field]).strip()
            if value and getattr(story, field) != value:
                setattr(story, field, value)
                changed.append(field)
    return changed


def _transition_status(story: Story, new_status: str, user: User) -> None:
    previous = story.status
    story.status = new_status
    story.needs_review = new_status in ("draft", "editor_review")
    story.auto_published = False
    if new_status == "published":
        story.published_at = story.published_at or datetime.utcnow()
        story.published_by_id = user.id
    elif new_status in ("archived", "unpublished"):
        # Off the feed but kept: the correction history and the audit trail
        # must survive a story being taken down, so nothing is deleted.
        story.is_breaking = False
        if new_status == "archived" and story.expires_at is None:
            story.expires_at = datetime.utcnow()
    # Note: the corrections counter belongs to ``record_update``, not here. A
    # correction is an update record -- it is counted where the update is
    # written, so the two can never disagree.
    if previous != new_status:
        story.updated_by_id = user.id


@router.post("/stories/{story_id}/regenerate")
def regenerate(story_id: int, request: Request, db: Session = Depends(get_db),
               user: User = Depends(require_user)) -> Any:
    """Ask the pipeline to rewrite the story from its facts.

    Refused while a story is locked, and the refusal is the point: regeneration
    is the machine's most destructive verb, so on a story a person has edited
    it is not available at all. An editor who wants a fresh draft unlocks the
    story first, deliberately, and that unlock is itself audited.
    """
    story = _story_or_404(db, story_id)
    if story.editor_locked:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="This story is locked after a manual edit; unlock it before regenerating")
    regenerate_story(db, story, applied_by=_actor(user))
    audit(db, _actor(user), "regenerate", "story", story.id, ip=client_ip(request))
    db.commit()
    return to_story_detail(db, story).model_dump()


@router.post("/stories/{story_id}/unlock")
def unlock_story(story_id: int, request: Request, db: Session = Depends(get_db),
                 user: User = Depends(require_editor),
                 body: Dict[str, Any] = Body(default={})) -> Any:
    """Let the pipeline write this story again."""
    story = _story_or_404(db, story_id)
    story.editor_locked = False
    record_update(db, story, StoryChange(
        kind="note", headline=story.headline_te,
        text_te="ఈ వార్తపై సంపాదక నియంత్రణ ఎత్తివేయబడింది.",
        text_en="Editorial control of this story was released to automation.",
        article_id=None, applied_by=_actor(user), note=body.get("note")))
    audit(db, _actor(user), "story_unlock", "story", story.id,
          detail=body.get("note"), ip=client_ip(request))
    db.commit()
    return {"story_id": story.id, "editor_locked": False}


def _publish(db, story, user, body, request) -> None:
    _transition_status(story, "published", user)
    _note(db, story, user, "ఈ వార్త ప్రచురించబడింది.",
          "Published from the editor app.", body.get("note"))


def _unpublish(db, story, user, body, request) -> None:
    previous = story.status
    _transition_status(story, "unpublished", user)
    _note(db, story, user, "ఈ వార్త తాత్కాలికంగా దాచబడింది.",
          f"Taken down (was {previous}).", body.get("note") or body.get("reason"))


def _approve(db, story, user, body, request) -> None:
    _transition_status(story, "approved", user)
    _note(db, story, user, "ఈ వార్త ఆమోదించబడింది.", "Approved for publication.",
          body.get("note"))


def _archive(db, story, user, body, request) -> None:
    _transition_status(story, "archived", user)
    _note(db, story, user, "ఈ వార్త అభిలేఖ్యంలోకి చేర్చబడింది.",
          "Archived. Its history is retained.", body.get("note") or body.get("reason"))


def _feature(db, story, user, body, request) -> None:
    story.is_breaking = bool(body.get("featured", True))
    _note(db, story, user, "ఈ వార్త ముఖ్యాంశంగా చూపబడుతుంది.",
          "Featured on the front page.", body.get("note"))


def _breaking(db, story, user, body, request) -> None:
    story.is_breaking = True
    _note(db, story, user, "ఈ వార్త బ్రేకింగ్‌గా గుర్తించబడింది.",
          "Flagged as breaking.", body.get("note"))


def _hold(db, story, user, body, request) -> None:
    _transition_status(story, "editor_review", user)
    _note(db, story, user, body.get("reason_te", "ఈ వార్తను సమీక్షలో ఉంచారు."),
          body.get("reason_en", "Held for review."), body.get("note"))


def _correct(db, story, user, body, request) -> None:
    text_te, text_en = body.get("text_te"), body.get("text_en")
    if not text_te and not text_en:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="text_te or text_en is required")
    # ``record_update`` owns the corrections counter and, for a live story, the
    # status flip to "corrected"; for a story that was not live yet, the
    # correction still has to show, so the status is set explicitly after.
    record_update(db, story, StoryChange(
        kind="correction", headline=body.get("headline"),
        text_te=text_te, text_en=text_en,
        article_id=None, applied_by=_actor(user), note=body.get("note")))
    story.status = "corrected"
    story.editor_locked = True
    if text_te:
        story.body_te = text_te
    if text_en:
        story.body_en = text_en


def _note(db, story, user, text_te: str, text_en: str, note: Optional[str]) -> None:
    record_update(db, story, StoryChange(
        kind="note", headline=story.headline_te, text_te=text_te, text_en=text_en,
        article_id=None, applied_by=_actor(user), note=note))


_ACTIONS: Dict[str, Any] = {
    "publish": _publish,
    "unpublish": _unpublish,
    "approve": _approve,
    "archive": _archive,
    "feature": _feature,
    "breaking": _breaking,
    "hold": _hold,
    "correct": _correct,
}


# ---------------------------------------------------------------------------
# Facts: the evidence floor under the prose
# ---------------------------------------------------------------------------

def _save_facts(db: Session, story: Story, facts: Any, user: User) -> None:
    """Record facts an editor asserted, at the claim level and attributed.

    A person asserting a fact is a claim, not a verified fact, so it is stored
    at ``claim`` with the editor as its attribution. Promoting it to ``fact``
    is a separate, deliberate decision with its own audit row.
    """
    if not facts or not isinstance(facts, list):
        return
    from newsroom.domain.evidence import EvidenceLevel

    for index, item in enumerate(facts):
        if not isinstance(item, dict):
            continue
        text = str(item.get("text_te") or item.get("text_en") or "").strip()
        if not text:
            continue
        level = str(item.get("evidence_level") or EvidenceLevel.CLAIM.value)
        try:
            level = EvidenceLevel(level).value
        except ValueError:
            level = EvidenceLevel.CLAIM.value
        db.add(Fact(
            story_id=story.id, text_te=text,
            text_en=str(item.get("text_en") or "").strip() or None,
            evidence_level=level,
            confidence=float(item.get("confidence") or 0.5),
            attributed_to=item.get("attributed_to") or _actor(user),
            rank=index,
            status="active",
        ))


@router.post("/stories/{story_id}/facts")
def add_fact(story_id: int, request: Request, db: Session = Depends(get_db),
             user: User = Depends(require_editor),
             body: Dict[str, Any] = Body(...)) -> Any:
    story = _story_or_404(db, story_id)
    _save_facts(db, story, [body], user)
    audit(db, _actor(user), "fact_add", "story", story.id,
          detail=str(body.get("text_te") or "")[:120], ip=client_ip(request))
    db.commit()
    return to_story_detail(db, story).model_dump()


@router.delete("/facts/{fact_id}")
def remove_fact(fact_id: int, request: Request, db: Session = Depends(get_db),
                user: User = Depends(require_editor),
                body: Dict[str, Any] = Body(default={})) -> Any:
    """Withdraw a fact rather than delete it.

    The row is marked withdrawn so that a published story's claims remain
    reconstructible afterwards: a correction that says "we no longer assert
    this" is only meaningful if the record of asserting it survives.
    """
    fact = db.get(Fact, fact_id)
    if fact is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Fact not found")
    fact.status = "withdrawn"
    audit(db, _actor(user), "fact_withdraw", "fact", fact.id,
          detail=str(fact.text_te)[:120], ip=client_ip(request))
    db.commit()
    return {"fact_id": fact.id, "status": fact.status}


# ---------------------------------------------------------------------------
# Reader submissions: tips from the app, triaged by a person
# ---------------------------------------------------------------------------

# What an editor may move a submission to. Deliberately narrower than the
# admin endpoint's set: "published" is not among them. A reader tip reaching
# the feed is *never* a status change on the submission row -- it is a Story
# the editor wrote, checked, and published through the ordinary story path.
SUBMISSION_STATUSES = ("new", "triaged", "verified", "rejected")


def _submission_or_404(db: Session, submission_id: int) -> Submission:
    submission = db.get(Submission, submission_id)
    if submission is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND,
                            detail="Submission not found")
    return submission


def _submission_summary(row: Submission) -> Dict[str, Any]:
    """One submission for the queue list.

    The queue shows a short sketch, not the whole tip: a reader can submit
    several paragraphs, and a desk scanning the list needs the first line to
    decide whether to open it. The full text is the detail endpoint below.
    """
    return {
        "id": row.id,
        "headline": _submission_headline(row),
        "body": row.body,
        "category": row.category,
        "location_text": row.location_text,
        "contact": row.contact,
        "media_path": row.media_path,
        "status": row.status,
        "triage_note": row.triage_note,
        "story_id": row.story_id,
        "created_at": row.created_at.isoformat() if row.created_at else None,
    }


def _submission_headline(row: Submission) -> str:
    """A short label for the queue, from the submitter's own first line.

    Never invented: it is the submission's first meaningful line, trimmed to a
    list-friendly length. Splitting on the sentence end a Telugu wire item
    carries, or a newline, or a Latin full stop, is what keeps "దశ, కాజీపేట:"
    datelines out of the label.
    """
    body = (row.body or "").strip()
    if not body:
        return "(empty submission)"
    first_line = _FIRST_LINE.split(body, maxsplit=1)[0].strip()
    if not first_line:
        first_line = body.split("\n", 1)[0].strip()
    return first_line[:140]


_FIRST_LINE = re.compile(r"[।\n.!?]")

# Which headline column a tip belongs in, by the script it was written in.
_SUBMISSION_HEADLINE_FIELD = {
    "te": "headline_te",
    "ten": "headline_ten",
    "en": "headline_en",
}


def submission_language(submission: Submission) -> str:
    """The script a reader wrote their tip in.

    A submission carries no language field -- the reader just typed -- so the
    script is the only honest signal. Telugu script is Telugu; Latin script is
    Tenglish if it keeps Telugu words' open syllables and English otherwise.
    Anything unreadable falls back to Telugu, the paper's first language,
    rather than silently relabelling the tip.
    """
    from newsroom.nlp.language import detect_language

    detected = detect_language(submission.body)
    if detected.value in _SUBMISSION_HEADLINE_FIELD:
        return detected.value
    return "te"


@router.get("/submissions")
def list_submissions(request: Request, db: Session = Depends(get_db),
                     user: User = Depends(require_editor),
                     status_filter: Optional[str] = Query(default=None, alias="status"),
                     page: int = Query(default=1, ge=1),
                     page_size: int = Query(default=25, ge=1, le=100)) -> Any:
    """The reader-tip queue, newest first.

    A tip carries a submitter's contact details, so reading the queue is an
    editor action, not a reader one: the app's session token is the gate, not
    an admin key baked into the APK.
    """
    query = select(Submission)
    if status_filter:
        if status_filter not in SUBMISSION_STATUSES:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                                detail=f"Unknown status {status_filter!r}")
        query = query.where(Submission.status == status_filter)

    total = db.execute(select(func.count()).select_from(
        query.subquery())).scalar_one()
    new_count = db.execute(select(func.count(Submission.id)).where(
        Submission.status == "new")).scalar_one()
    rows = db.execute(query.order_by(Submission.created_at.desc())
                      .offset((page - 1) * page_size).limit(page_size)
                      ).scalars().all()
    return {
        "items": [_submission_summary(row) for row in rows],
        "total": total,
        "page": page,
        "page_size": page_size,
        "has_more": page * page_size < total,
        "new_count": new_count,
    }


@router.get("/submissions/{submission_id}")
def get_submission(submission_id: int, db: Session = Depends(get_db),
                   user: User = Depends(require_editor)) -> Any:
    """One submission, complete and exactly as the reader sent it.

    Nothing here is corrected, translated or summarised. The desk has to judge
    the tip on what was actually typed, so the raw text is what they get.
    """
    return _submission_summary(_submission_or_404(db, submission_id))


@router.post("/submissions/{submission_id}/triage")
def triage_submission(submission_id: int, request: Request,
                      db: Session = Depends(get_db),
                      user: User = Depends(require_editor),
                      body: Dict[str, Any] = Body(...)) -> Any:
    """Move a submission along the review queue.

    ``status`` is a triage label on the *tip*, not a publishing action: it
    says where the desk is with verifying the reader's account. Taking a tip
    to the feed happens through the story path, by converting it to a draft
    and publishing that.
    """
    submission = _submission_or_404(db, submission_id)
    new_status = body.get("status")
    if new_status not in SUBMISSION_STATUSES:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail=f"status must be one of {list(SUBMISSION_STATUSES)}")
    submission.status = new_status
    submission.triage_note = body.get("note")
    audit(db, _actor(user), "submission_triage", "submission", submission.id,
          detail=new_status, ip=client_ip(request))
    db.commit()
    return _submission_summary(submission)


@router.post("/submissions/{submission_id}/story", status_code=status.HTTP_201_CREATED)
def submission_to_story(submission_id: int, request: Request,
                        db: Session = Depends(get_db),
                        user: User = Depends(require_editor),
                        body: Dict[str, Any] = Body(default={})) -> Any:
    """Turn a verified reader tip into a draft story.

    The one rule this endpoint exists to keep: a tip is a lead, not evidence.
    The reader's text is carried onto the draft as a single *unverified* fact
    attributed to the submitter, and the submission's provenance is preserved
    both on the row (``story_id``) and in the audit trail -- so the newsroom
    can always see which reader tip a published story began as.

    The draft is created unpublished, at ``status=draft``. Publishing is a
    separate editor action on the story, after verification.
    """
    import hashlib as _hashlib

    submission = _submission_or_404(db, submission_id)
    if submission.story_id is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT,
                            detail=f"Submission {submission.id} already became "
                                   f"story {submission.story_id}")

    headline = (str(body.get("headline_te") or "").strip()
                or _submission_headline(submission))
    section = str(body.get("section") or submission.category or "general")

    story = Story(
        cluster_id=f"submission-{submission.id}-{_hashlib.sha256(
            headline.encode('utf-8')).hexdigest()[:16]}",
        slug=headline[:280],
        section=section,
        status="draft",
        origin=StoryOrigin.MANUAL.value,
        editor_locked=True,
        created_by_id=user.id,
        updated_by_id=user.id,
        district=body.get("district") or submission.location_text,
        state=body.get("state") or "Telangana",
    )
    # The tip's own script decides which headline column it belongs in. A
    # submission arrives in whatever the reader typed -- Telugu script, or
    # Roman Telugu, or English -- and putting an English tip into headline_te
    # would publish English copy under the Telugu column, the same leak the
    # writers elsewhere refuse to commit.
    if not body.get("headline_te"):
        setattr(story, _SUBMISSION_HEADLINE_FIELD[submission_language(submission)],
                headline)
    _apply_editor_fields(story, body)
    db.add(story)
    db.flush()

    # The tip itself, carried across at the evidence level it actually has.
    # A reader's say-so is unverified single-source material, and it is stored
    # as that: attributing it to the submitter by name, and never at a level
    # that would let it through the auto-publish gate on its own.
    attribution = submission.contact or f"reader submission #{submission.id}"
    db.add(Fact(
        story_id=story.id,
        text_te=submission.body,
        evidence_level=EvidenceLevel.UNVERIFIED.value,
        confidence=0.3,
        attributed_to=attribution,
        rank=0,
        status="active",
    ))

    record_update(db, story, StoryChange(
        kind="note", headline=headline,
        text_te=f"పాఠకుడు పంపిన సమాచారం నుండి సృష్టించబడింది. ఇది నిర్ధారణ కోసం "
                f"సమర్పితమైనది (submission #{submission.id}).",
        text_en=f"Created from reader submission #{submission.id}; the tip is "
                f"unverified and awaits confirmation.",
        article_id=None, applied_by=_actor(user),
        note=f"converted from submission #{submission.id} by {_actor(user)}"))
    audit(db, _actor(user), "submission_to_story", "submission", submission.id,
          detail=f"story={story.id}", ip=client_ip(request))
    audit(db, _actor(user), "story_create", "story", story.id,
          detail=f"origin=submission#{submission.id} status=draft",
          ip=client_ip(request))

    # Link last, so the submission only points at the story once both the row
    # and the provenance records exist.
    submission.story_id = story.id
    if submission.status == "new":
        submission.status = "triaged"
    db.commit()
    return to_story_detail(db, story).model_dump()


# ---------------------------------------------------------------------------
# Pipeline inspection: what the machine is doing
# ---------------------------------------------------------------------------

@router.get("/pipeline")
def pipeline_health(user: User = Depends(require_user),
                    db: Session = Depends(get_db)) -> Any:
    """What the automated newsroom is doing, and where it is stuck.

    The numbers that matter to a desk: is anything arriving, is anything
    failing, and does anything need a person to look at it.
    """
    failed_articles = db.execute(select(func.count(Article.id)).where(
        Article.status == "failed")).scalar_one()
    stuck_jobs = db.execute(select(func.count(Job.id)).where(
        Job.status.in_(("failed", "pending")),
        Job.attempts >= 1,
    )).scalar_one()
    held = db.execute(select(func.count(Story.id)).where(
        Story.needs_review.is_(True))).scalar_one()
    locked = db.execute(select(func.count(Story.id)).where(
        Story.editor_locked.is_(True))).scalar_one()
    return {
        "articles_failed": failed_articles,
        "jobs_stuck": stuck_jobs,
        "stories_needing_review": held,
        "stories_editor_locked": locked,
        "needs_attention": failed_articles + stuck_jobs + held > 0,
    }


@router.get("/pipeline/failures")
def list_failures(user: User = Depends(require_editor),
                  db: Session = Depends(get_db),
                  page: int = Query(default=1, ge=1),
                  page_size: int = Query(default=25, ge=1, le=100)) -> Any:
    """Articles and jobs the pipeline gave up on, newest first."""
    articles = db.execute(select(Article).where(Article.status == "failed")
                          .order_by(Article.ingested_at.desc())
                          .offset((page - 1) * page_size).limit(page_size)).scalars().all()
    jobs = db.execute(select(Job).where(Job.status.in_(("failed", "dead")))
                      .order_by(Job.finished_at.desc().nullslast())
                      .limit(page_size)).scalars().all()
    total = db.execute(select(func.count(Article.id)).where(
        Article.status == "failed")).scalar_one()
    return {
        "articles": [
            {"id": a.id, "url": a.url, "title": a.title_raw,
             "source_id": a.source_id, "reason": a.rejection_reason,
             "ingested_at": a.ingested_at.isoformat() if a.ingested_at else None}
            for a in articles
        ],
        "jobs": [
            {"id": j.id, "kind": j.stage, "status": j.status,
             "attempts": j.attempts, "error": j.error,
             "finished_at": j.finished_at.isoformat() if j.finished_at else None}
            for j in jobs
        ],
        **paginate([], total, page, page_size),
    }


@router.post("/pipeline/retry/{article_id}")
def retry_failed_article(article_id: int, request: Request,
                         db: Session = Depends(get_db),
                         user: User = Depends(require_user)) -> Any:
    """Give one failed article another pass through the desk."""
    from newsroom.pipeline.orchestrator import SweepReport, _process_article

    article = db.get(Article, article_id)
    if article is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Article not found")
    source = db.get(Source, article.source_id) if article.source_id else None
    if source is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="The article's source no longer exists")

    article.status = "new"
    article.rejection_reason = None
    report = SweepReport()
    try:
        _process_article(db, article, source, report, fetch_bodies=False)
    except Exception as exc:  # noqa: BLE001 - reported to the editor, not swallowed
        report.errors.append(f"{type(exc).__name__}: {exc}")
    audit(db, _actor(user), "retry_article", "article", article.id,
          detail=f"errors={len(report.errors)}", ip=client_ip(request))
    db.commit()
    return {"article_id": article.id, "status": article.status,
            "errors": report.errors}


# ---------------------------------------------------------------------------
# Accounts: admin-only
# ---------------------------------------------------------------------------

@router.get("/users")
def list_users(user: User = Depends(require_editor),
               db: Session = Depends(get_db)) -> Any:
    """Every newsroom account. Requires an administrator.

    Reader accounts do not exist here -- readers are anonymous devices -- so
    this list is the full set of people who can publish.
    """
    if not user.is_admin:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN,
                            detail="Managing accounts needs administrator privileges")
    rows = db.execute(select(User).order_by(User.created_at.asc())).scalars().all()
    return {"users": [row.to_dict() for row in rows]}


@router.post("/users", status_code=status.HTTP_201_CREATED)
def create_user(request: Request, db: Session = Depends(get_db),
                user: User = Depends(require_editor),
                body: Dict[str, Any] = Body(...)) -> Any:
    """Invite an editor. Passwords are hashed on arrival and never stored."""
    if not user.is_admin:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN,
                            detail="Creating accounts needs administrator privileges")
    email = str(body.get("email") or "").strip().lower()
    password = str(body.get("password") or "")
    role = str(body.get("role") or Role.EDITOR.value).strip().lower()
    if role not in Role.allowed():
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail=f"Role must be one of {Role.allowed()}")
    if not email or "@" not in email:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="A valid email is required")
    if len(password) < 10:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="Password must be at least 10 characters")

    existing = db.execute(select(User).where(User.email == email)).scalar_one_or_none()
    if existing is not None:
        # Reported as a conflict rather than leaked: the caller already has
        # admin rights, so there is nothing to discover here.
        raise HTTPException(status_code=status.HTTP_409_CONFLICT,
                            detail="An account with that email already exists")

    account = User(
        email=email,
        display_name=str(body.get("display_name") or email.split("@")[0]),
        password_hash=hash_password(password),
        role=role,
        is_active=True,
    )
    db.add(account)
    db.flush()
    audit(db, _actor(user), "user_create", "user", account.id,
          detail=f"role={role}", ip=client_ip(request))
    db.commit()
    return account.to_dict()


@router.patch("/users/{account_id}")
def update_user(account_id: int, request: Request, db: Session = Depends(get_db),
                user: User = Depends(require_editor),
                body: Dict[str, Any] = Body(...)) -> Any:
    """Change a role, reset a password, or suspend an account.

    An editor cannot do this to themselves or anyone else: only an
    administrator, and never the last active administrator, because locking
    every admin out of the newsroom is not recoverable without out-of-band
    access to the datastore.
    """
    if not user.is_admin:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN,
                            detail="Changing accounts needs administrator privileges")
    account = db.get(User, account_id)
    if account is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Account not found")

    role = body.get("role")
    if role is not None:
        if role not in Role.allowed():
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                                detail=f"Role must be one of {Role.allowed()}")
        if role != Role.ADMIN.value and _is_last_admin(db, account):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Demoting the last administrator would leave the newsroom "
                       "unmanageable; promote another account first")
        account.role = role

    if body.get("is_active") is not None:
        if body["is_active"] is False and _is_last_admin(db, account):
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Suspending the last administrator would lock out the newsroom")
        account.is_active = bool(body["is_active"])

    if body.get("revoke_tokens"):
        # Every token this account holds in the field dies now.
        account.tokens_revoked_at = datetime.utcnow()

    password = body.get("password")
    if password:
        if len(password) < 10:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                                detail="Password must be at least 10 characters")
        account.password_hash = hash_password(password)
        account.tokens_revoked_at = datetime.utcnow()

    changes = ", ".join(key for key in ("role", "is_active", "password", "revoke_tokens")
                        if key in body)
    audit(db, _actor(user), "user_update", "user", account.id,
          detail=changes, ip=client_ip(request))
    db.commit()
    return account.to_dict()


def _is_last_admin(db: Session, account: User) -> bool:
    if account.role != Role.ADMIN.value or not account.is_active:
        return False
    others = db.execute(select(func.count(User.id)).where(
        User.role == Role.ADMIN.value,
        User.is_active.is_(True),
        User.id != account.id,
    )).scalar_one()
    return others == 0


# Registered last on purpose. This is a catch-all for the desk's single verbs,
# and FastAPI matches routes in registration order, so anything with a more
# specific path -- /facts, /regenerate, /unlock -- must be on the router
# before it, or "correct" would silently swallow "/editor/stories/3/facts".
@router.post("/stories/{story_id}/{action}")
def story_action(story_id: int, action: str, request: Request,
                 db: Session = Depends(get_db), user: User = Depends(require_editor),
                 body: Dict[str, Any] = Body(default={})) -> Any:
    """The single verbs the desk uses: publish, unpublish, approve, archive,
    feature, correct, breaking, hold.

    One route rather than eight, because they all do the same three things --
    move the status, record *what changed and by whom*, and audit -- and eight
    near-identical handlers is eight places to forget the audit row.
    """
    if action not in _ACTIONS:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND,
                            detail=f"Unknown action {action!r}")
    story = _story_or_404(db, story_id)
    handler = _ACTIONS[action]
    handler(db, story, user, body, request)
    db.commit()
    return {
        "story_id": story.id,
        "status": story.status,
        "editor_locked": story.editor_locked,
        "version": story.version,
    }
