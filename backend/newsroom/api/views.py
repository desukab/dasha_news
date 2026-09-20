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
from newsroom.db.models import Story
from newsroom.domain.evidence import EvidenceLevel, story_status_label_te
from newsroom.domain.sections import BY_SLUG
from newsroom.nlp.language import validate_language


def section_labels(slug: Optional[str]) -> Dict[str, Optional[str]]:
    section = BY_SLUG.get(slug or "")
    if not section:
        return {"te": slug, "en": slug}
    return {"te": section.te, "en": section.en}


# ---------------------------------------------------------------------------
# Language truth at the wire
# ---------------------------------------------------------------------------

# A column name is a promise: headline_te is Telugu, headline_ten is Telugu in
# Latin script, headline_en is English. The pipeline's writer gate enforces
# that when it composes a story, but two paths still let a wrong-script value
# reach the wire:
#
#  * stories published before the gate landed were never remediated, and a
#    sweep does not re-render a story that has no new article behind it;
#  * the gate clears a failed field, but a story already published keeps its
#    status, so the stale value sits in a live row until something rewrites it.
#
# Withholding is the last line of defence and it is cheap: it is what makes a
# column mean its language to every client, including one reading a stale
# offline cache. The text is never rewritten -- the field is dropped, so the
# reader's fallback chain shows the best language the story really has and the
# story stops counting as translated.
_LANGUAGE_FIELDS = (("headline", "headline"), ("lead", "lead"), ("body", "body"))


def _renderable(value: Optional[str], language: str) -> Optional[str]:
    """`value` if it is genuinely written in `language`, else None."""
    if value is None:
        return None
    text = str(value)
    if not text.strip():
        return None
    return text if validate_language(text, language).ok else None


def story_language(story) -> Dict[str, Dict[str, Optional[str]]]:
    """Every language field this story may actually be served in.

    One pass over the nine columns, so a card and a detail of the same story
    can never disagree about what the story is in. Callers that need to know
    only whether a language is served should read [serves_language] from this
    set rather than re-walking the columns.
    """
    languages: Dict[str, Dict[str, Optional[str]]] = {}
    for language in ("te", "ten", "en"):
        gated = {
            field: _renderable(getattr(story, f"{field}_{language}"), language)
            for field, _ in _LANGUAGE_FIELDS
        }
        languages[language] = gated
    return languages


def serves_language(coverage: Dict[str, Dict[str, Optional[str]]],
                    language: str) -> bool:
    """Does the reader asking for `language` get a headline in it?"""
    fields = coverage.get(language) or {}
    headline = fields.get("headline")
    return headline is not None and headline.strip() != ""


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
    # Audio is written flat into media/audio/ (see render_audio), and the media
    # route is /media/{kind}/{name} -- two segments. Interpolating the language
    # here produced /media/audio/te/<file>, a path nothing serves, which left
    # every narrated story 404ing and the app's audio tab dead.
    filename = str(row.path).rsplit("/", 1)[-1]
    return f"{get_settings().public_base_url.rstrip('/')}/media/audio/{filename}"


def to_story_card(session: Session, story, *, language: str = "te",
                  rendered: Optional[Dict[str, Dict[str, Optional[str]]]] = None
                  ) -> StoryCard:
    labels = section_labels(story.section)
    # Computed once by a caller that needs the coverage set for anything else
    # (the feed's language filter, or a detail's body fields), so a card and a
    # detail of one story can never disagree about what the story is in.
    rendered = rendered or story_language(story)
    return StoryCard(
        id=story.id,
        cluster_id=story.cluster_id,
        slug=story.slug,
        headline_te=rendered["te"]["headline"],
        headline_ten=rendered["ten"]["headline"],
        headline_en=rendered["en"]["headline"],
        lead_te=rendered["te"]["lead"],
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
        origin=story.origin,
        editor_locked=bool(story.editor_locked),
        needs_review=bool(story.needs_review),
        image_url=story.primary_image_url,
        audio_url=_audio_url(session, story.id),
        has_audio=_audio_url(session, story.id) is not None,
        published_at=story.published_at.isoformat() if story.published_at else None,
        updated_at=story.updated_at.isoformat() if story.updated_at else None,
    )


def to_story_detail(session: Session, story) -> StoryDetail:
    from newsroom.db.models import Fact, StorySource, StoryUpdate, Article, Source

    rendered = story_language(story)
    card = to_story_card(session, story, rendered=rendered)

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
        body_te=rendered["te"]["body"],
        body_ten=rendered["ten"]["body"],
        body_en=rendered["en"]["body"],
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


# ---------------------------------------------------------------------------
# The front page's regions
# ---------------------------------------------------------------------------

# The four questions the front page answers, in the order the reader scans it.
# Splitting the room by the section taxonomy's own flags -- rather than by a
# hardcoded list of slugs -- is what keeps the split honest when the newsroom
# adds a desk: a section marked telangana_local is local wherever it appears,
# and everything else is the national and world desk.
_TELENGANA_LOCAL = tuple(
    slug for slug, section in BY_SLUG.items() if section.telangana_local)


def _region(session: Session, query, *, language: str, asked: Optional[str],
            page_size: int) -> Dict[str, Any]:
    """Build one region: candidates -> language pass -> one page of cards.

    A region is allowed to come back empty, and an empty region is still
    returned (with `asked`) so the reader can see which question went
    unanswered rather than being handed a region full of the wrong stories.
    """
    from newsroom.api.schemas import RegionPage

    candidates = session.execute(query.limit(_FRONT_CANDIDATES)).scalars().all()
    rendered = {story.id: story_language(story) for story in candidates}
    served = [story for story in candidates
              if serves_language(rendered[story.id], language)]
    rows = served[:page_size]
    items = [to_story_card(session, story, language=language, rendered=rendered[story.id])
             .model_dump() for story in rows]
    return RegionPage(
        items=items,
        total=len(served),
        asked=asked,
        has_more=len(served) > page_size,
    ).model_dump()


def to_front_page(session: Session, *, language: str = "te",
                  district: Optional[str] = None,
                  page_size: int = 6) -> Dict[str, Any]:
    """The whole front page: Now, Near You, Telangana, India & World.

    One response rather than four calls, because a phone on a cold start should
    make one request to learn what is happening around it, and because the four
    regions are only coherent together -- a front page that arrives in pieces
    can show a Near You slot before the reader learns there is no district set.

    `district` is the reader's own choice and is the one thing that can make a
    region mean something different from one reader to the next. When it is
    unset the Near You region comes back empty and carries that fact, so the
    app asks the reader for a district instead of quietly showing the whole
    state under a local label.
    """
    from newsroom.api.schemas import FrontPage

    published = Story.status.in_(("published", "auto_published",
                                  "developing", "breaking", "corrected"))

    now_q = select(Story).where(published).order_by(
        Story.is_breaking.desc(), Story.published_at.desc())

    near_q = None
    if district:
        near_q = select(Story).where(
            published,
            (Story.district == district) | (Story.mandal == district) |
            (Story.locality == district),
        ).order_by(Story.is_breaking.desc(), Story.published_at.desc())

    telangana_q = select(Story).where(
        published, Story.section.in_(_TELENGANA_LOCAL),
    ).order_by(Story.is_breaking.desc(), Story.importance.desc(),
               Story.published_at.desc())

    india_q = select(Story).where(
        published, ~Story.section.in_(_TELENGANA_LOCAL),
    ).order_by(Story.is_breaking.desc(), Story.importance.desc(),
               Story.published_at.desc())

    return FrontPage(
        now=_region(session, now_q, language=language, asked="now",
                    page_size=page_size),
        near=_region(session, near_q, language=language, asked=district,
                     page_size=page_size) if near_q is not None else
        {"items": [], "total": 0, "asked": None, "has_more": False},
        telangana=_region(session, telangana_q, language=language,
                          asked="telangana", page_size=page_size),
        india_world=_region(session, india_q, language=language,
                            asked="india-world", page_size=page_size),
        language=language,
        district=district,
    ).model_dump()


# The widest window a front-page region will read. The published room is in the
# hundreds, so this is the whole room in practice; it is bounded only so a room
# that grew without bound could not turn a front page into a table scan.
_FRONT_CANDIDATES = 300
