"""Serialization: ORM rows -> API views.

Kept in one place so the response shape is defined once and both the public and
admin routers agree on it.
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional

from sqlalchemy import select
from sqlalchemy.orm import Session

from newsroom.api.schemas import (
    FactView,
    SourceLinkView,
    StoryCard,
    StoryDetail,
    UpdateView,
)
from newsroom.config import get_settings
from newsroom.domain.evidence import EvidenceLevel, story_status_label_te
from newsroom.domain.sections import BY_SLUG


def section_labels(slug: Optional[str]) -> Dict[str, Optional[str]]:
    section = BY_SLUG.get(slug or "")
    if not section:
        return {"te": slug, "en": slug}
    return {"te": section.te, "en": section.en}


def _absolute(path: Optional[str]) -> Optional[str]:
    if not path:
        return None
    return f"{get_settings().public_base_url.rstrip('/')}/media/{path}"


def _audio_url(session: Session, story_id: int) -> Optional[str]:
    from newsroom.db.models import Audio

    row = session.execute(
        select(Audio).where(Audio.story_id == story_id, Audio.status == "ready")
        .order_by(Audio.created_at.desc()).limit(1)
    ).scalar_one_or_none()
    if row is None or not row.path:
        return None
    filename = str(row.path).rsplit("/", 1)[-1]
    language = f"/{row.language}" if row.language else ""
    return f"{get_settings().public_base_url.rstrip('/')}/media/audio{language}/{filename}"


def to_story_card(session: Session, story, *, language: str = "te") -> StoryCard:
    labels = section_labels(story.section)
    return StoryCard(
        id=story.id,
        cluster_id=story.cluster_id,
        slug=story.slug,
        headline_te=story.headline_te,
        headline_ten=story.headline_ten,
        headline_en=story.headline_en,
        lead_te=story.lead_te,
        section=story.section,
        section_label_te=labels["te"],
        section_label_en=labels["en"],
        status=story.status,
        status_label_te=story_status_label_te(story.status),
        importance=round(story.importance or 0.0, 3),
        evidence_score=round(story.evidence_score or 0.0, 3),
        num_sources=story.num_sources or 0,
        district=story.district,
        mandal=story.mandal,
        state=story.state,
        is_breaking=bool(story.is_breaking),
        is_developing=bool(story.is_developing),
        image_url=story.primary_image_url,
        audio_url=_audio_url(session, story.id),
        has_audio=_audio_url(session, story.id) is not None,
        published_at=story.published_at.isoformat() if story.published_at else None,
        updated_at=story.updated_at.isoformat() if story.updated_at else None,
    )


def to_story_detail(session: Session, story) -> StoryDetail:
    from newsroom.db.models import Fact, StorySource, StoryUpdate, Article, Source

    card = to_story_card(session, story)

    facts = session.execute(
        select(Fact).where(Fact.story_id == story.id, Fact.status == "active")
        .order_by(Fact.rank.asc())
    ).scalars().all()
    fact_views = []
    for fact in facts:
        level = _evidence_level(fact.evidence_level)
        fact_views.append(FactView(
            id=fact.id,
            text_te=fact.text_te,
            text_en=fact.text_en,
            evidence_level=fact.evidence_level,
            evidence_label_te=level.label_te if level else None,
            evidence_label_en=level.label_en if level else None,
            confidence=round(fact.confidence or 0.0, 3),
            attributed_to=fact.attributed_to,
            status=fact.status,
            rank=fact.rank,
        ))

    links = session.execute(
        select(StorySource, Source, Article)
        .join(Source, Source.id == StorySource.source_id, isouter=True)
        .join(Article, Article.id == StorySource.article_id, isouter=True)
        .where(StorySource.story_id == story.id)
        .order_by(StorySource.first_seen_at.asc())
    ).all()
    source_views = [
        SourceLinkView(
            id=link.id,
            source_name=source.name if source else None,
            site_url=source.site_url if source else None,
            article_url=article.url if article else None,
            article_title=article.title_raw if article else None,
            published_at=article.published_at.isoformat() if article and article.published_at else None,
            corroborates=bool(link.corroborates),
            conflicts_with=link.conflicts_with,
        )
        for link, source, article in links
    ]

    updates = session.execute(
        select(StoryUpdate).where(StoryUpdate.story_id == story.id)
        .order_by(StoryUpdate.created_at.desc()).limit(20)
    ).scalars().all()

    detail = StoryDetail(
        **card.model_dump(),
        body_te=story.body_te,
        body_ten=story.body_ten,
        body_en=story.body_en,
        facts=fact_views,
        sources=source_views,
        updates=[
            UpdateView(
                id=update.id, kind=update.kind, headline=update.headline,
                text_te=update.text_te, text_en=update.text_en,
                created_at=update.created_at.isoformat(), applied_by=update.applied_by,
            )
            for update in updates
        ],
        corrections_count=story.corrections_count or 0,
        version=story.version or 1,
        confidence=round(story.confidence or 0.0, 3),
    )
    return detail


def _evidence_level(value: Optional[str]) -> Optional[EvidenceLevel]:
    try:
        return EvidenceLevel(value) if value else None
    except ValueError:
        return None


def paginate(items: List[Any], total: int, page: int, page_size: int) -> Dict[str, Any]:
    return {
        "items": items,
        "total": total,
        "page": page,
        "page_size": page_size,
        "has_more": page * page_size < total,
    }
