"""Public reader API. Anonymous, rate-limited, read-only."""

from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from newsroom.api.schemas import DeviceIn, DeviceOut, Page, SubmissionIn, SubmissionOut
from newsroom.api.views import (
    paginate,
    serves_language,
    story_language,
    to_story_card,
    to_story_detail,
)
from newsroom.db.engine import get_db
from newsroom.db.models import Bookmark, Device, ReadingHistory, Story, Submission
from newsroom.domain.geo import ALL_DISTRICTS
from newsroom.domain.sections import ALL_SLUGS, PRIMARY_SLUGS, BY_SLUG
from newsroom.nlp.similarity import rank_by_similarity
from newsroom.security.auth import client_ip, rate_limit

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/v1", tags=["public"])

PUBLISHED = ("published", "auto_published", "developing", "breaking", "corrected")


def _published_query():
    return select(Story).where(Story.status.in_(PUBLISHED))


@router.get("/feed", response_model=Page, dependencies=[Depends(rate_limit)])
def feed(request: Request, db: Session = Depends(get_db),
         language: str = Query("te", pattern="^(te|ten|en)$"),
         section: Optional[str] = None, district: Optional[str] = None,
         page: int = Query(1, ge=1), page_size: int = Query(20, ge=1, le=50)) -> Any:
    """The personalised home feed, most important first.

    `language` is a promise, not a hint: a story is served in that language only
    if it has a headline actually written in it. A story whose Telugu column
    holds English wire copy is not a Telugu story, whatever the column says, so
    it stays out of the Telugu feed rather than being served as a translation it
    never had. It is still reachable in a language it really is in.
    """
    query = _published_query()
    if section and section in ALL_SLUGS:
        query = query.where(Story.section == section)
    if district:
        query = query.where(Story.district == district)

    # Coverage is a property of the rendered text, not of any stored column, so
    # it cannot be expressed in the where clause. The candidate set is bounded
    # and small (the published room is hundreds, not millions), which makes a
    # Python pass cheaper than a denormalised coverage column maintained on
    # every write -- and it stays correct the moment a sweep rewrites a field,
    # which a stored flag would not.
    candidates = db.execute(
        query.order_by(Story.is_breaking.desc(), Story.importance.desc(),
                       Story.published_at.desc())
        .limit(_FEED_LANGUAGE_CANDIDATES)
    ).scalars().all()

    rendered = {story.id: story_language(story) for story in candidates}
    served = [story for story in candidates
              if serves_language(rendered[story.id], language)]

    start = (page - 1) * page_size
    rows = served[start:start + page_size]
    items = [to_story_card(db, story, language=language, rendered=rendered[story.id])
             .model_dump() for story in rows]
    return paginate(items, len(served), page, page_size)


@router.get("/breaking", response_model=Page, dependencies=[Depends(rate_limit)])
def breaking(db: Session = Depends(get_db),
             page: int = Query(1, ge=1), page_size: int = Query(20, ge=1, le=50)) -> Any:
    query = _published_query().where(Story.is_breaking.is_(True))
    total = db.execute(select(func.count()).select_from(query.subquery())).scalar_one()
    rows = db.execute(query.order_by(Story.published_at.desc())
                      .offset((page - 1) * page_size).limit(page_size)).scalars().all()
    return paginate([to_story_card(db, s).model_dump() for s in rows], total, page, page_size)


@router.get("/developing", response_model=Page, dependencies=[Depends(rate_limit)])
def developing(db: Session = Depends(get_db),
               page: int = Query(1, ge=1), page_size: int = Query(20, ge=1, le=50)) -> Any:
    query = _published_query().where(Story.is_developing.is_(True))
    total = db.execute(select(func.count()).select_from(query.subquery())).scalar_one()
    rows = db.execute(query.order_by(Story.updated_at.desc())
                      .offset((page - 1) * page_size).limit(page_size)).scalars().all()
    return paginate([to_story_card(db, s).model_dump() for s in rows], total, page, page_size)


@router.get("/sections", dependencies=[Depends(rate_limit)])
def sections() -> Any:
    """Section taxonomy for navigation."""
    return {
        "primary": [
            {"slug": s.slug, "te": s.te, "ten": s.ten, "en": s.en}
            for s in (BY_SLUG[slug] for slug in PRIMARY_SLUGS)
        ],
        "all": [
            {"slug": s.slug, "te": s.te, "ten": s.ten, "en": s.en,
             "sensitive": s.sensitive, "telangana_local": s.telangana_local}
            for s in BY_SLUG.values()
        ],
    }


@router.get("/districts", dependencies=[Depends(rate_limit)])
def districts() -> Any:
    return {"state": "Telangana", "districts": ALL_DISTRICTS}


@router.get("/story/{story_id}", dependencies=[Depends(rate_limit)])
def story_detail(story_id: int, db: Session = Depends(get_db)) -> Any:
    story = db.get(Story, story_id)
    if story is None or story.status not in PUBLISHED:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Story not found")
    return to_story_detail(db, story).model_dump()


@router.get("/story/by-slug/{slug}", dependencies=[Depends(rate_limit)])
def story_by_slug(slug: str, db: Session = Depends(get_db)) -> Any:
    story = db.execute(
        select(Story).where(Story.slug == slug).limit(1)
    ).scalar_one_or_none()
    if story is None or story.status not in PUBLISHED:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Story not found")
    return to_story_detail(db, story).model_dump()


@router.get("/search", response_model=Page, dependencies=[Depends(rate_limit)])
def search(request: Request, db: Session = Depends(get_db),
           q: str = Query(..., min_length=1, max_length=200),
           language: str = Query("te", pattern="^(te|ten|en)$"),
           limit: int = Query(20, ge=1, le=50)) -> Any:
    """Free-text search across published stories.

    Query terms are untrusted input: they are only ever used as SQL bind
    parameters and as tokens for similarity scoring, never interpolated.
    """
    base = _published_query()
    rows = db.execute(
        base.order_by(Story.published_at.desc()).limit(200)
    ).scalars().all()

    candidates = [story.headline_te or story.headline_en or story.slug for story in rows]
    ranked = rank_by_similarity(q, candidates)
    matched = [rows[index] for index, score in ranked if score > 0.08][:limit]
    items = [to_story_card(db, story, language=language).model_dump() for story in matched]
    return paginate(items, len(items), 1, limit)


# The widest window the feed's language pass will read. Generous on purpose:
# withholding a wrong-script story shrinks the served set, and a reader paging
# deep must still reach the stories further down the importance order rather
# than hitting an artificial early end.
_FEED_LANGUAGE_CANDIDATES = 400


# ---------------------------------------------------------------------------
# Bookmarks, history and device preferences
# ---------------------------------------------------------------------------

def _device_id(request: Request, db: Session, supplied: Optional[str]) -> str:
    device_id = (supplied or "").strip()
    if not device_id:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="device_id is required")
    return device_id


@router.post("/device", response_model=DeviceOut, dependencies=[Depends(rate_limit)])
def register_device(payload: DeviceIn, request: Request,
                    db: Session = Depends(get_db)) -> Any:
    device = db.execute(
        select(Device).where(Device.device_id == payload.device_id)
    ).scalar_one_or_none()
    if device is None:
        device = Device(device_id=payload.device_id, locale=payload.locale,
                        theme=payload.theme, breaking_alerts=payload.breaking_alerts,
                        daily_digest=payload.daily_digest)
        db.add(device)
    else:
        device.locale = payload.locale
        device.theme = payload.theme
        device.breaking_alerts = payload.breaking_alerts
        device.daily_digest = payload.daily_digest
    device.last_seen_at = func.now()
    db.commit()
    db.refresh(device)
    return DeviceOut(device_id=device.device_id, locale=device.locale, theme=device.theme,
                     breaking_alerts=device.breaking_alerts, daily_digest=device.daily_digest)


@router.post("/bookmarks/{story_id}", dependencies=[Depends(rate_limit)])
def add_bookmark(story_id: int, request: Request,
                 device_id: str = Query(..., min_length=6, max_length=120),
                 db: Session = Depends(get_db)) -> Any:
    story = db.get(Story, story_id)
    if story is None or story.status not in PUBLISHED:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Story not found")
    existing = db.execute(
        select(Bookmark.id).where(Bookmark.device_id == device_id,
                                  Bookmark.story_id == story_id)
    ).first()
    if not existing:
        db.add(Bookmark(device_id=device_id, story_id=story_id))
        db.commit()
    return {"bookmarked": True, "story_id": story_id}


@router.delete("/bookmarks/{story_id}", dependencies=[Depends(rate_limit)])
def remove_bookmark(story_id: int,
                    device_id: str = Query(..., min_length=6, max_length=120),
                    db: Session = Depends(get_db)) -> Any:
    db.execute(
        Bookmark.__table__.delete().where(
            Bookmark.device_id == device_id, Bookmark.story_id == story_id)
    )
    db.commit()
    return {"bookmarked": False, "story_id": story_id}


@router.get("/bookmarks", response_model=Page, dependencies=[Depends(rate_limit)])
def list_bookmarks(device_id: str = Query(..., min_length=6, max_length=120),
                   db: Session = Depends(get_db),
                   page: int = Query(1, ge=1), page_size: int = Query(20, ge=1, le=50)) -> Any:
    query = select(Story).join(Bookmark, Bookmark.story_id == Story.id).where(
        Bookmark.device_id == device_id, Story.status.in_(PUBLISHED))
    total = db.execute(select(func.count()).select_from(query.subquery())).scalar_one()
    rows = db.execute(query.order_by(Bookmark.created_at.desc())
                      .offset((page - 1) * page_size).limit(page_size)).scalars().all()
    items = [to_story_card(db, story).model_dump() for story in rows]
    return paginate(items, total, page, page_size)


@router.post("/history/{story_id}", dependencies=[Depends(rate_limit)])
def record_history(story_id: int, read_seconds: int = Query(0, ge=0, le=7200),
                   completed: bool = False,
                   device_id: str = Query(..., min_length=6, max_length=120),
                   db: Session = Depends(get_db)) -> Any:
    row = db.execute(
        select(ReadingHistory).where(ReadingHistory.device_id == device_id,
                                     ReadingHistory.story_id == story_id)
    ).scalar_one_or_none()
    if row is None:
        db.add(ReadingHistory(device_id=device_id, story_id=story_id,
                              read_seconds=read_seconds, completed=completed))
    else:
        row.read_seconds = (row.read_seconds or 0) + read_seconds
        row.completed = completed or row.completed
    db.commit()
    return {"recorded": True, "story_id": story_id}


@router.post("/submissions", response_model=SubmissionOut, dependencies=[Depends(rate_limit)])
def submit_tip(payload: SubmissionIn, request: Request,
               db: Session = Depends(get_db)) -> Any:
    """Reader-submitted tip. Stored as untrusted, never auto-published."""
    submission = Submission(
        device_id=payload.device_id,
        body=payload.body,
        category=payload.category if payload.category in ALL_SLUGS else None,
        location_text=payload.location_text,
        contact=payload.contact,
        status="new",
    )
    db.add(submission)
    db.commit()
    db.refresh(submission)
    logger.info("submission %d received from %s", submission.id, client_ip(request))
    return SubmissionOut(id=submission.id, status=submission.status,
                         created_at=submission.created_at.isoformat())


@router.get("/health")
def health(db: Session = Depends(get_db)) -> Any:
    """Liveness + readiness, including whether the datastore answers."""
    from sqlalchemy import text

    try:
        db.execute(text("SELECT 1"))
        datastore = "ok"
    except Exception as exc:  # noqa: BLE001
        return {"status": "degraded", "datastore": str(exc)[:120]}
    settings_status = []
    try:
        from newsroom.config import get_settings
        settings_status = get_settings().warn_on_insecure_defaults()
    except Exception:  # noqa: BLE001
        pass
    return {"status": "ok", "datastore": datastore,
            "configuration_warnings": settings_status,
            "published_stories": db.execute(
                select(func.count()).select_from(
                    _published_query().subquery())).scalar_one()}
