"""Newsroom admin console API.

Every endpoint requires the admin key. Every mutating action writes an audit
row before it returns, so the console's activity is reconstructible.
"""

from __future__ import annotations

import logging
from datetime import datetime
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Body, Depends, HTTPException, Query, Request, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from newsroom.api.schemas import (
    AcquisitionEventView,
    ReportOut,
    SourceSummary,
    StoryCard,
)
from newsroom.api.views import paginate, to_story_detail
from newsroom.config import get_settings
from newsroom.db.engine import get_db
from newsroom.db.models import (
    AiCall,
    Article,
    AuditLog,
    Device,
    Fact,
    Job,
    Media,
    Source,
    Story,
    StoryUpdate,
    Submission,
)
from newsroom.domain.sections import ALL_SLUGS
from newsroom.pipeline.orchestrator import regenerate_story, run_sweep
from newsroom.pipeline.publish import StoryChange, record_update
from newsroom.pipeline.scout import discover_feeds
from newsroom.security.auth import audit, client_ip, require_admin

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/admin", tags=["admin"])


def _admin(request: Request) -> str:
    return require_admin(request.headers.get("X-Dasha-Key"),
                         request.headers.get("Authorization"))


@router.get("/status")
def status_overview(request: Request, db: Session = Depends(get_db),
                    admin: str = Depends(_admin)) -> Any:
    counts = {
        "sources": db.execute(select(func.count(Source.id))).scalar_one(),
        "sources_enabled": db.execute(
            select(func.count(Source.id)).where(Source.is_enabled.is_(True))).scalar_one(),
        "articles": db.execute(select(func.count(Article.id))).scalar_one(),
        "stories": db.execute(select(func.count(Story.id))).scalar_one(),
        "published": db.execute(select(func.count(Story.id)).where(
            Story.status.in_(("published", "auto_published", "developing",
                              "breaking", "corrected")))).scalar_one(),
        "held": db.execute(select(func.count(Story.id)).where(Story.status == "held")).scalar_one(),
        "draft": db.execute(select(func.count(Story.id)).where(Story.status == "draft")).scalar_one(),
        "submissions_new": db.execute(select(func.count(Submission.id)).where(
            Submission.status == "new")).scalar_one(),
        "jobs_queued": db.execute(select(func.count(Job.id)).where(Job.status == "queued")).scalar_one(),
        "ai_calls": db.execute(select(func.count(AiCall.id))).scalar_one(),
    }
    settings = get_settings()
    from newsroom.acquisition.backends import available_backends, installed_backends

    known = sorted(available_backends())
    return {
        "counts": counts,
        "ai_provider": settings.ai_provider,
        "auto_publish_enabled": settings.auto_publish_enabled,
        "configuration_warnings": settings.warn_on_insecure_defaults(),
        "pipeline_interval_seconds": settings.pipeline_interval_seconds,
        "acquisition": {
            "backends_known": known,
            "backends_installed": sorted(installed_backends()),
            "robots_respected": settings.respect_robots_txt,
            "politeness_min_interval_seconds": settings.politeness_min_interval_seconds,
            "browser_fetch_enabled": settings.browser_fetch_enabled,
        },
    }


@router.post("/sweep", response_model=ReportOut)
def trigger_sweep(request: Request, db: Session = Depends(get_db),
                  admin: str = Depends(_admin),
                  fetch_bodies: bool = Query(True),
                  limit_sources: Optional[int] = Query(None, ge=1, le=50)) -> Any:
    report = run_sweep(db, fetch_bodies=fetch_bodies, limit_sources=limit_sources)
    audit(db, admin, "sweep", "pipeline", "run",
          detail=f"{report.articles_new} new articles, {report.stories_published} published",
          ip=client_ip(request))
    db.commit()
    return report.to_dict()


# ---------------------------------------------------------------------------
# Story management
# ---------------------------------------------------------------------------

@router.get("/stories")
def list_stories(request: Request, db: Session = Depends(get_db),
                 admin: str = Depends(_admin),
                 status_filter: Optional[str] = Query(None, alias="status"),
                 section: Optional[str] = None,
                 needs_review: Optional[bool] = None,
                 page: int = Query(1, ge=1), page_size: int = Query(20, ge=1, le=100)) -> Any:
    query = select(Story)
    if status_filter:
        allowed = {"draft", "held", "published", "auto_published", "developing",
                   "breaking", "corrected", "killed"}
        if status_filter not in allowed:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                                detail=f"status must be one of {sorted(allowed)}")
        query = query.where(Story.status == status_filter)
    if section:
        if section not in ALL_SLUGS:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                                detail="unknown section")
        query = query.where(Story.section == section)
    if needs_review is not None:
        query = query.where(Story.needs_review.is_(needs_review))

    total = db.execute(select(func.count()).select_from(query.subquery())).scalar_one()
    rows = db.execute(query.order_by(Story.updated_at.desc())
                      .offset((page - 1) * page_size).limit(page_size)).scalars().all()
    items = [to_story_detail(db, story).model_dump() for story in rows]
    return paginate(items, total, page, page_size)


@router.get("/stories/{story_id}")
def get_story(story_id: int, request: Request, db: Session = Depends(get_db),
              admin: str = Depends(_admin)) -> Any:
    story = db.get(Story, story_id)
    if story is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Story not found")
    return to_story_detail(db, story).model_dump()


def _story_or_404(db: Session, story_id: int) -> Story:
    story = db.get(Story, story_id)
    if story is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Story not found")
    return story


@router.post("/stories/{story_id}/publish")
def publish_story(story_id: int, request: Request, db: Session = Depends(get_db),
                  admin: str = Depends(_admin),
                  body: Dict[str, Any] = Body(default={})) -> Any:
    story = _story_or_404(db, story_id)
    kind = body.get("kind", "publish")
    story.status = "published" if kind != "developing" else "developing"
    story.auto_published = False
    story.needs_review = False
    story.published_at = story.published_at or datetime.utcnow()
    record_update(db, story, StoryChange(
        kind="note", headline=story.headline_te,
        text_te=f"ఈ వార్త ప్రచురించబడింది.",
        text_en="This story was published from the newsroom console.",
        article_id=None, applied_by=admin, note="manual publish"))
    audit(db, admin, "publish", "story", story.id, ip=client_ip(request))
    db.commit()
    return {"story_id": story.id, "status": story.status}


@router.post("/stories/{story_id}/hold")
def hold_story(story_id: int, request: Request, db: Session = Depends(get_db),
               admin: str = Depends(_admin),
               body: Dict[str, Any] = Body(default={})) -> Any:
    story = _story_or_404(db, story_id)
    story.status = "held"
    story.needs_review = True
    story.auto_published = False
    record_update(db, story, StoryChange(
        kind="note", headline=story.headline_te,
        text_te=body.get("reason", "ఈ వార్తను సమీక్షలో ఉంచారు."),
        text_en=body.get("reason_en", "Held for review."),
        article_id=None, applied_by=admin, note=body.get("note")))
    audit(db, admin, "hold", "story", story.id, detail=body.get("reason"),
          ip=client_ip(request))
    db.commit()
    return {"story_id": story.id, "status": story.status}


@router.post("/stories/{story_id}/correct")
def correct_story(story_id: int, request: Request, db: Session = Depends(get_db),
                  admin: str = Depends(_admin),
                  body: Dict[str, Any] = Body(...)) -> Any:
    story = _story_or_404(db, story_id)
    text_te = body.get("text_te")
    text_en = body.get("text_en")
    if not text_te and not text_en:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="text_te or text_en is required")
    previous_te = story.body_te
    record_update(db, story, StoryChange(
        kind="correction", headline=body.get("headline"),
        text_te=text_te, text_en=text_en,
        article_id=None, applied_by=admin, note=body.get("note")))
    story.body_te = text_te or story.body_te
    story.body_en = text_en or story.body_en
    audit(db, admin, "correct", "story", story.id,
          detail=f"previous version {story.version - 1} retained", ip=client_ip(request))
    db.commit()
    return {"story_id": story.id, "status": story.status,
            "version": story.version, "corrections_count": story.corrections_count}


@router.post("/stories/{story_id}/breaking")
def flag_breaking(story_id: int, request: Request, db: Session = Depends(get_db),
                  admin: str = Depends(_admin)) -> Any:
    story = _story_or_404(db, story_id)
    record_update(db, story, StoryChange(
        kind="escalation", headline=story.headline_te,
        text_te="ఈ వార్త బ్రేకింగ్‌గా గుర్తించబడింది.",
        text_en="Flagged as breaking from the console.",
        article_id=None, applied_by=admin))
    audit(db, admin, "flag_breaking", "story", story.id, ip=client_ip(request))
    db.commit()
    return {"story_id": story.id, "status": story.status,
            "is_breaking": story.is_breaking}


@router.post("/stories/{story_id}/kill")
def kill_story(story_id: int, request: Request, db: Session = Depends(get_db),
               admin: str = Depends(_admin),
               body: Dict[str, Any] = Body(default={})) -> Any:
    story = _story_or_404(db, story_id)
    story.status = "killed"
    story.is_breaking = False
    story.expires_at = datetime.utcnow()
    record_update(db, story, StoryChange(
        kind="note", headline=story.headline_te,
        text_te=body.get("reason", "ఈ వార్త ఉపసంహరించబడింది."),
        text_en=body.get("reason_en", "Withdrawn from publication."),
        article_id=None, applied_by=admin, note=body.get("note")))
    audit(db, admin, "kill", "story", story.id, detail=body.get("reason"),
          ip=client_ip(request))
    db.commit()
    return {"story_id": story.id, "status": story.status}


@router.post("/stories/{story_id}/regenerate")
def regenerate(story_id: int, request: Request, db: Session = Depends(get_db),
               admin: str = Depends(_admin)) -> Any:
    story = _story_or_404(db, story_id)
    regenerate_story(db, story, applied_by=admin)
    audit(db, admin, "regenerate", "story", story.id, ip=client_ip(request))
    return to_story_detail(db, story).model_dump()


@router.post("/stories/{story_id}/facts")
def add_fact(story_id: int, request: Request, db: Session = Depends(get_db),
             admin: str = Depends(_admin), body: Dict[str, Any] = Body(...)) -> Any:
    story = _story_or_404(db, story_id)
    text_te = body.get("text_te")
    if not text_te:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="text_te is required")
    allowed = {"fact", "official", "claim", "allegation", "forecast", "opinion",
               "unverified", "disputed"}
    level = body.get("evidence_level", "claim")
    if level not in allowed:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail=f"evidence_level must be one of {sorted(allowed)}")
    fact = Fact(
        story_id=story.id, text_te=text_te, text_en=body.get("text_en"),
        evidence_level=level,
        confidence=max(0.0, min(1.0, float(body.get("confidence", 0.7)))),
        attributed_to=body.get("attributed_to"),
        status="active", rank=999,
    )
    db.add(fact)
    db.flush()
    record_update(db, story, StoryChange(
        kind="verification", headline=None,
        text_te=f"కొత్త వాస్తవం చేర్చబడింది: {text_te[:120]}",
        text_en=f"Fact added from the console: {(text_te or '')[:120]}",
        article_id=None, applied_by=admin))
    audit(db, admin, "fact_add", "story", story.id, detail=text_te[:200],
          ip=client_ip(request))
    db.commit()
    return {"fact_id": fact.id, "story_id": story.id}


# ---------------------------------------------------------------------------
# Source management
# ---------------------------------------------------------------------------

# A source of kind "web" reads the outlet's own pages, so it has no feed URL to
# require; everything else must publish a machine interface or be unreachable.
_WEB_KINDS = {"web", "html"}
_KINDS = {"rss", "atom", "feed", "web", "html"}


def _validate_kind(value: Optional[Any]) -> str:
    kind = (value or "rss").strip().lower()
    if kind not in _KINDS:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail=f"kind must be one of {sorted(_KINDS)}")
    return kind


def _validate_backend(value: Optional[Any]) -> str:
    from newsroom.acquisition.backends import available_backends

    name = (value or "httpx").strip().lower()
    if name not in available_backends():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"fetch_backend must be one of {sorted(available_backends())}")
    return name


def _validate_politeness(value: Optional[Any]) -> Optional[float]:
    if value is None or value == "":
        return None
    try:
        seconds = float(value)
    except (TypeError, ValueError) as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="politeness_seconds must be a number of seconds") from exc
    if seconds < 0:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="politeness_seconds cannot be negative")
    return seconds


@router.get("/sources", response_model=Dict[str, Any])
def list_sources(request: Request, db: Session = Depends(get_db),
                 admin: str = Depends(_admin),
                 page: int = Query(1, ge=1), page_size: int = Query(50, ge=1, le=200)) -> Any:
    query = select(Source)
    total = db.execute(select(func.count()).select_from(query.subquery())).scalar_one()
    rows = db.execute(query.order_by(Source.id.asc())
                      .offset((page - 1) * page_size).limit(page_size)).scalars().all()
    return paginate([SourceSummary(**source.to_summary()).model_dump() for source in rows],
                    total, page, page_size)


@router.post("/sources", response_model=SourceSummary, status_code=status.HTTP_201_CREATED)
def add_source(request: Request, db: Session = Depends(get_db),
               admin: str = Depends(_admin),
               body: Dict[str, Any] = Body(...)) -> Any:
    from newsroom.security.guards import assert_safe_url

    name = (body.get("name") or "").strip()
    site_url = (body.get("site_url") or "").strip()
    feed_url = (body.get("feed_url") or "").strip()
    if not name or not site_url:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="name and site_url are required")
    for url in (site_url, feed_url):
        if url:
            try:
                assert_safe_url(url)
            except ValueError as exc:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc

    kind = _validate_kind(body.get("kind"))
    backend = _validate_backend(body.get("fetch_backend"))
    if not feed_url and kind not in _WEB_KINDS:
        discovered = discover_feeds(site_url)
        if not discovered:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="no feed URL supplied and none could be discovered. "
                       "Set kind to 'web' to read the site's own pages instead.")
        feed_url = discovered[0]

    language = body.get("language", "te")
    if language not in ("te", "en", "ten"):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="language must be te, en or ten")
    section = body.get("section")
    if section and section not in ALL_SLUGS:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail="unknown section")

    guid = body.get("guid") or f"manual:{abs(hash((site_url, feed_url)))}"
    existing = db.execute(select(Source).where(Source.guid == guid)).scalar_one_or_none()
    if existing is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT,
                            detail="source with this guid already exists")

    source = Source(
        guid=guid, name=name[:200], site_url=site_url[:500], feed_url=feed_url[:500],
        kind=kind, language=language,
        trust_score=max(0.0, min(1.0, float(body.get("trust_score", 0.6)))),
        default_section=section,
        is_enabled=bool(body.get("is_enabled", True)),
        is_breaking_capable=bool(body.get("is_breaking_capable", False)),
        fetch_backend=backend,
        requires_js=bool(body.get("requires_js", False)),
        politeness_seconds=_validate_politeness(body.get("politeness_seconds")),
    )
    db.add(source)
    db.flush()
    audit(db, admin, "source_add", "source", source.id, detail=name, ip=client_ip(request))
    db.commit()
    db.refresh(source)
    return SourceSummary(**source.to_summary())


@router.patch("/sources/{source_id}", response_model=SourceSummary)
def update_source(source_id: int, request: Request, db: Session = Depends(get_db),
                  admin: str = Depends(_admin),
                  body: Dict[str, Any] = Body(...)) -> Any:
    source = db.get(Source, source_id)
    if source is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Source not found")
    allowed = {"name", "site_url", "feed_url", "language", "trust_score",
               "default_section", "is_enabled", "is_breaking_capable",
               "kind", "fetch_backend", "requires_js", "politeness_seconds"}
    for key, value in body.items():
        if key not in allowed:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                                detail=f"field '{key}' cannot be updated")
        if key in ("site_url", "feed_url") and value:
            from newsroom.security.guards import assert_safe_url
            try:
                assert_safe_url(value)
            except ValueError as exc:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
        if key == "kind":
            value = _validate_kind(value)
        if key == "fetch_backend":
            value = _validate_backend(value)
        if key == "politeness_seconds":
            value = _validate_politeness(value)
        setattr(source, key, value)
    audit(db, admin, "source_update", "source", source.id,
          detail=",".join(sorted(body.keys())), ip=client_ip(request))
    db.commit()
    db.refresh(source)
    return SourceSummary(**source.to_summary())


@router.delete("/sources/{source_id}")
def delete_source(source_id: int, request: Request, db: Session = Depends(get_db),
                  admin: str = Depends(_admin)) -> Any:
    source = db.get(Source, source_id)
    if source is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Source not found")
    # Disable rather than delete: the source's articles still back published
    # stories and must remain attributable.
    source.is_enabled = False
    audit(db, admin, "source_disable", "source", source.id, detail=source.name,
          ip=client_ip(request))
    db.commit()
    return {"source_id": source.id, "is_enabled": False}


@router.get("/sources/{source_id}/acquisition", response_model=Dict[str, Any])
def source_acquisition_history(source_id: int, request: Request,
                               db: Session = Depends(get_db),
                               admin: str = Depends(_admin),
                               page: int = Query(1, ge=1),
                               page_size: int = Query(50, ge=1, le=200)) -> Any:
    """The recent fetch record for one source.

    This is the observability the acquisition layer owes an operator: which
    transport was used, what it got back, and how often it had to retry. A
    source whose extractions are failing at 40% needs a human, and this is how
    they find out.
    """
    from newsroom.acquisition.observability import summarise_source

    source = db.get(Source, source_id)
    if source is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Source not found")

    summary = summarise_source(db, source_id, limit=page_size)
    events = [AcquisitionEventView(**event).model_dump()
              for event in summary.get("events", [])]
    return paginate(events, summary.get("total", len(events)), page, page_size)


# ---------------------------------------------------------------------------
# AI queue, audit log, submissions, media
# ---------------------------------------------------------------------------

@router.get("/jobs")
def list_jobs(request: Request, db: Session = Depends(get_db),
              admin: str = Depends(_admin),
              status_filter: Optional[str] = Query(None, alias="status"),
              limit: int = Query(50, ge=1, le=200)) -> Any:
    query = select(Job)
    if status_filter:
        query = query.where(Job.status == status_filter)
    rows = db.execute(query.order_by(Job.created_at.desc()).limit(limit)).scalars().all()
    return {
        "jobs": [
            {"id": job.id, "stage": job.stage, "status": job.status,
             "priority": job.priority, "attempts": job.attempts,
             "error": job.error, "created_at": job.created_at.isoformat(),
             "finished_at": job.finished_at.isoformat() if job.finished_at else None}
            for job in rows
        ]
    }


@router.post("/jobs/{job_id}/retry")
def retry_job(job_id: int, request: Request, db: Session = Depends(get_db),
              admin: str = Depends(_admin)) -> Any:
    job = db.get(Job, job_id)
    if job is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Job not found")
    if job.status not in ("failed", "dead"):
        raise HTTPException(status_code=status.HTTP_409_CONFLICT,
                            detail="only failed jobs can be retried")
    job.status = "queued"
    job.attempts = 0
    job.error = None
    audit(db, admin, "job_retry", "job", job.id, ip=client_ip(request))
    db.commit()
    return {"job_id": job.id, "status": job.status}


@router.get("/audit")
def list_audit(request: Request, db: Session = Depends(get_db),
               admin: str = Depends(_admin),
               limit: int = Query(100, ge=1, le=500)) -> Any:
    rows = db.execute(select(AuditLog).order_by(AuditLog.created_at.desc())
                      .limit(limit)).scalars().all()
    return {
        "entries": [
            {"id": row.id, "actor": row.actor, "action": row.action,
             "target_type": row.target_type, "target_id": row.target_id,
             "detail": row.detail, "ip": row.ip,
             "created_at": row.created_at.isoformat()}
            for row in rows
        ]
    }


@router.get("/submissions")
def list_submissions(request: Request, db: Session = Depends(get_db),
                     admin: str = Depends(_admin),
                     status_filter: Optional[str] = Query(None, alias="status"),
                     limit: int = Query(50, ge=1, le=200)) -> Any:
    query = select(Submission)
    if status_filter:
        query = query.where(Submission.status == status_filter)
    rows = db.execute(query.order_by(Submission.created_at.desc())
                      .limit(limit)).scalars().all()
    return {
        "submissions": [
            {"id": row.id, "device_id": row.device_id, "body": row.body,
             "category": row.category, "location_text": row.location_text,
             "contact": row.contact, "status": row.status,
             "triage_note": row.triage_note, "story_id": row.story_id,
             "created_at": row.created_at.isoformat()}
            for row in rows
        ]
    }


@router.post("/submissions/{submission_id}/triage")
def triage_submission(submission_id: int, request: Request, db: Session = Depends(get_db),
                      admin: str = Depends(_admin),
                      body: Dict[str, Any] = Body(...)) -> Any:
    submission = db.get(Submission, submission_id)
    if submission is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND,
                            detail="Submission not found")
    new_status = body.get("status")
    allowed = {"triaged", "verified", "published", "rejected"}
    if new_status not in allowed:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                            detail=f"status must be one of {sorted(allowed)}")
    submission.status = new_status
    submission.triage_note = body.get("note")
    if new_status == "published" and body.get("story_id"):
        submission.story_id = int(body["story_id"])
    audit(db, admin, "submission_triage", "submission", submission.id,
          detail=new_status, ip=client_ip(request))
    db.commit()
    return {"submission_id": submission.id, "status": submission.status}


@router.get("/media")
def list_media(request: Request, db: Session = Depends(get_db),
               admin: str = Depends(_admin),
               story_id: Optional[int] = None,
               limit: int = Query(50, ge=1, le=200)) -> Any:
    query = select(Media)
    if story_id:
        query = query.where(Media.story_id == story_id)
    rows = db.execute(query.order_by(Media.created_at.desc())
                      .limit(limit)).scalars().all()
    return {
        "media": [
            {"id": row.id, "story_id": row.story_id, "url": row.url,
             "provider": row.provider, "license": row.license,
             "attribution": row.attribution, "credit_text": row.credit_text,
             "status": row.status, "width": row.width, "height": row.height}
            for row in rows
        ]
    }


@router.get("/ai-calls")
def list_ai_calls(request: Request, db: Session = Depends(get_db),
                  admin: str = Depends(_admin),
                  limit: int = Query(50, ge=1, le=200)) -> Any:
    rows = db.execute(select(AiCall).order_by(AiCall.created_at.desc())
                      .limit(limit)).scalars().all()
    return {
        "calls": [
            {"id": row.id, "provider": row.provider, "model": row.model,
             "stage": row.stage, "story_id": row.story_id,
             "tokens_in": row.tokens_in, "tokens_out": row.tokens_out,
             "duration_ms": row.duration_ms, "success": row.success,
             "error": row.error, "created_at": row.created_at.isoformat()}
            for row in rows
        ]
    }


@router.get("/articles")
def list_articles(request: Request, db: Session = Depends(get_db),
                  admin: str = Depends(_admin),
                  source_id: Optional[int] = None,
                  status_filter: Optional[str] = Query(None, alias="status"),
                  limit: int = Query(50, ge=1, le=200)) -> Any:
    query = select(Article)
    if source_id:
        query = query.where(Article.source_id == source_id)
    if status_filter:
        query = query.where(Article.status == status_filter)
    rows = db.execute(query.order_by(Article.ingested_at.desc())
                      .limit(limit)).scalars().all()
    return {"articles": [article.to_summary() for article in rows]}
