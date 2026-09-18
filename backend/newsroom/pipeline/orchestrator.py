"""The newsroom pipeline: ingest -> extract -> cluster -> facts -> write -> publish.

This is the composition layer. Every AI component from the spec has a module of
its own and is invoked in a defined order, with the deterministic fallback
applied whenever a stage produces nothing usable.

A sweep is idempotent: running it twice against the same feeds produces the
same stories, not duplicates.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from datetime import datetime
from statistics import mean
from typing import Any, Dict, List, Optional, Sequence

from sqlalchemy import select
from sqlalchemy.orm import Session

from newsroom.config import get_settings
from newsroom.db.models import (
    Article,
    Audio,
    Entity,
    Fact,
    Job,
    Media,
    Source,
    Story,
    StorySource,
)
from newsroom.domain.evidence import EvidenceLevel
from newsroom.media.audio import render_audio
from newsroom.media.media import build_short_script, generate_poster
from newsroom.nlp.language import Language, detect_language
from newsroom.pipeline.dedupe import (
    ClusterCandidate,
    dedupe_article,
    make_cluster_id,
    cluster_article,
)
from newsroom.pipeline.engines import (
    classify_section,
    locate_story,
    score_importance,
)
from newsroom.pipeline.facts import extract_facts, heuristic_facts, merge_facts
from newsroom.pipeline.publish import decide_publication, record_update
from newsroom.pipeline.scoring import compare_articles, summarise_comparisons
from newsroom.pipeline.editorial import write_article, write_headline
from newsroom.security.auth import audit

logger = logging.getLogger(__name__)

PIPELINE_STAGES = (
    "scout", "extract", "dedupe", "cluster", "facts", "compare",
    "locate", "score", "section", "headline", "article", "publish", "media",
)


@dataclass
class SweepReport:
    started_at: datetime
    finished_at: Optional[datetime] = None
    sources: int = 0
    articles_fetched: int = 0
    articles_new: int = 0
    articles_duplicates: int = 0
    stories_created: int = 0
    stories_updated: int = 0
    stories_published: int = 0
    stories_held: int = 0
    media_generated: int = 0
    errors: List[str] = field(default_factory=list)

    @property
    def duration_seconds(self) -> float:
        if not self.finished_at:
            return 0.0
        return (self.finished_at - self.started_at).total_seconds()

    def to_dict(self) -> Dict[str, Any]:
        return {
            "started_at": self.started_at.isoformat(),
            "finished_at": self.finished_at.isoformat() if self.finished_at else None,
            "duration_seconds": round(self.duration_seconds, 2),
            "sources": self.sources,
            "articles_fetched": self.articles_fetched,
            "articles_new": self.articles_new,
            "articles_duplicates": self.articles_duplicates,
            "stories_created": self.stories_created,
            "stories_updated": self.stories_updated,
            "stories_published": self.stories_published,
            "stories_held": self.stories_held,
            "media_generated": self.media_generated,
            "errors": self.errors[:20],
        }


# ---------------------------------------------------------------------------
# Enrichment
# ---------------------------------------------------------------------------

def enrich_article(session: Session, article: Article) -> Article:
    """Fetch the article body and extract clean text from it.

    Never fatal: a paywalled, dead or hostile page leaves the article with its
    feed summary intact, which is still enough for clustering.

    Extraction goes through the acquisition layer so that the fetch method,
    the canonical URL and the extraction confidence are recorded alongside the
    text, and so per-source failure handling applies. The legacy direct
    extractor remains the fallback when the layer cannot be built at all.
    """
    if article.body_text:
        return article
    if not _should_fetch(article):
        article.body_text = article.summary_text
        return article

    page = _extract_page(session, article)

    # Raw publisher HTML is deliberately not retained: the newsroom keeps its
    # own clean text, and stale raw bodies are pruned by the retention policy.
    article.body_text = (page.body_text if page else None) or article.summary_text
    if page:
        if page.canonical_url:
            article.canonical_url = page.canonical_url[:1000]
        if page.fetch_method:
            article.fetch_method = page.fetch_method
        article.extraction_confidence = page.confidence
        if page.author:
            article.author = page.author[:300]
        if page.lead_image_url and not article.image_url:
            article.image_url = page.lead_image_url
        title = page.title or ""
        article.title_te = title if _is_telugu(title) else article.title_te
        article.title_en = title if _is_english(title) else None
    article.word_count = len((article.body_text or "").split())
    article.status = "processed"
    return article


def _extract_page(session: Session, article: Article):
    """Run the article URL through its source's adapter.

    Returns ``None`` when nothing could be extracted — the caller falls back to
    the feed summary, which is the pre-existing behaviour.
    """
    from newsroom.acquisition.registry import acquire
    from newsroom.acquisition.retry import (
        PermanentFetchError,
        RetryExhausted,
        TransientFetchError,
    )
    from newsroom.acquisition.source_adapter import ExtractedPage

    source = article.source
    try:
        handle = acquire(source or None, session=session)
        page = handle.extract(source, article.url)
    except (PermanentFetchError, TransientFetchError, RetryExhausted) as exc:
        logger.info("acquisition refused for %s: %s", article.url, exc)
        return None
    except Exception as exc:  # noqa: BLE001 - a hostile page is editorial, not fatal
        logger.info("extraction failed for %s: %s", article.url, exc)
        return None
    if isinstance(page, ExtractedPage) and page.is_useful:
        return page
    if isinstance(page, ExtractedPage):
        logger.info("extraction produced nothing usable for %s", article.url)
    return None


def _should_fetch(article: Article) -> bool:
    return bool(article.url and article.url.startswith(("http://", "https://")))


def _is_telugu(text: Optional[str]) -> bool:
    return detect_language(text) == Language.TELUGU


def _is_english(text: Optional[str]) -> bool:
    return detect_language(text) == Language.ENGLISH


# ---------------------------------------------------------------------------
# Story building
# ---------------------------------------------------------------------------

def build_or_update_story(session: Session, article: Article,
                          cluster_key: str) -> Story:
    """Create or extend the canonical story for an article."""
    existing = session.execute(
        select(Story).where(Story.cluster_id == cluster_key)).scalar_one_or_none()

    if existing is not None:
        return _extend_story(session, existing, article)

    story = Story(
        cluster_id=cluster_key,
        slug=_slug(article.title_raw),
        section="telangana",
        status="draft",
        first_seen_at=article.published_at or datetime.utcnow(),
    )
    session.add(story)
    session.flush()
    return _extend_story(session, story, article)


def _extend_story(session: Session, story: Story, article: Article) -> Story:
    """Add an article's evidence to an existing story."""
    if article.source_id is None:
        return story

    already = session.execute(
        select(StorySource.id).where(
            StorySource.story_id == story.id, StorySource.article_id == article.id)
    ).first()
    if not already:
        story.sources_links.append(StorySource(
            story_id=story.id, article_id=article.id, source_id=article.source_id,
            contribution=1.0, corroborates=True,
        ))
    story.updated_at = datetime.utcnow()
    return story


def _slug(title: Optional[str], max_len: int = 220) -> str:
    import re
    text = re.sub(r"[^\wఀ-౿]+", "-", (title or "").strip().lower())
    return text.strip("-")[:max_len] or "dasha-story"


# ---------------------------------------------------------------------------
# The sweep
# ---------------------------------------------------------------------------

def run_sweep(session: Session, *, fetch_bodies: bool = True,
              limit_sources: Optional[int] = None,
              include_disabled: bool = False) -> SweepReport:
    """One full newsroom pass. Idempotent."""
    report = SweepReport(started_at=datetime.utcnow())

    query = select(Source)
    if not include_disabled:
        query = query.where(Source.is_enabled.is_(True))
    if limit_sources:
        query = query.limit(limit_sources)
    sources: Sequence[Source] = session.execute(query).scalars().all()
    report.sources = len(sources)

    from newsroom.pipeline.scout import ingest_source

    for source in sources:
        try:
            scout_report = ingest_source(session, source, fetch_bodies=False)
            report.articles_fetched += scout_report.fetched
            report.articles_new += scout_report.new
            report.articles_duplicates += scout_report.duplicates
            report.errors.extend(scout_report.errors)
            if scout_report.new:
                for article in session.execute(
                    select(Article).where(
                        Article.source_id == source.id, Article.status == "new")
                ).scalars().all():
                    _process_article(session, article, source, report, fetch_bodies)
            session.commit()
        except Exception as exc:  # noqa: BLE001 - one bad source must not kill the sweep
            session.rollback()
            report.errors.append(f"{source.guid}: {type(exc).__name__}: {exc}")
            logger.exception("source sweep failed for %s", source.guid)

    _generate_media(session, report)
    report.finished_at = datetime.utcnow()
    _schedule_next_run(session)
    return report


def _process_article(session: Session, article: Article, source: Source,
                     report: SweepReport, fetch_bodies: bool) -> None:
    try:
        # 1. Deduplicate against this source's recent items.
        recent = session.execute(
            select(Article).where(
                Article.source_id == source.id, Article.id != article.id
            ).order_by(Article.ingested_at.desc()).limit(40)
        ).scalars().all()
        dedupe_result = dedupe_article(article, recent)
        if dedupe_result.is_duplicate:
            article.status = "rejected"
            article.rejection_reason = f"duplicate: {dedupe_result.reason}"
            report.articles_duplicates += 1
            return

        # 2. Extract the readable body.
        if fetch_bodies:
            enrich_article(session, article)

        # 3. Cluster into a story.
        article.cluster_id = _assign_cluster(session, article, source)
        article.status = "clustered"
        session.flush()

        story = build_or_update_story(session, article, article.cluster_id)
        _write_story(session, story, source, report)
        report.stories_updated += 1
    except Exception as exc:  # noqa: BLE001
        session.rollback()
        report.errors.append(f"article {article.id}: {type(exc).__name__}: {exc}")
        logger.exception("article processing failed for %s", article.url)


def _assign_cluster(session: Session, article: Article, source: Source) -> str:
    """Find or create the cluster key for this article."""
    candidates = [
        ClusterCandidate(
            id=story.id,
            cluster_id=story.cluster_id,
            title=story.headline_te or story.headline_en or _story_title(session, story),
            digest=_story_digest(session, story),
            published_at=story.published_at or story.first_seen_at,
            district=story.district,
            section=story.section,
        )
        for story in session.execute(
            select(Story).order_by(Story.updated_at.desc()).limit(120)
        ).scalars().all()
    ]
    match = cluster_article(article, candidates)
    if match is not None:
        return match.cluster_id
    return make_cluster_id(article.signature or article.url, str(source.id))


def _story_title(session: Session, story: Story) -> Optional[str]:
    row = session.execute(
        select(Article.title_raw).join(StorySource, StorySource.article_id == Article.id)
        .where(StorySource.story_id == story.id).order_by(Article.ingested_at.desc()).limit(1)
    ).first()
    return row[0] if row else None


def _story_digest(session: Session, story: Story) -> Optional[str]:
    row = session.execute(
        select(Article.digest).join(StorySource, StorySource.article_id == Article.id)
        .where(StorySource.story_id == story.id).limit(1)
    ).first()
    return row[0] if row else None


# ---------------------------------------------------------------------------
# Story writing
# ---------------------------------------------------------------------------

def _story_articles(session: Session, story: Story) -> List[Article]:
    return list(session.execute(
        select(Article).join(StorySource, StorySource.article_id == Article.id)
        .where(StorySource.story_id == story.id)
        .order_by(Article.ingested_at.asc())
    ).scalars().all())


def _story_sources(session: Session, story: Story) -> List[Source]:
    return list(session.execute(
        select(Source).join(StorySource, StorySource.source_id == Source.id)
        .where(StorySource.story_id == story.id)
    ).scalars().all())


class _FactView:
    """Adapter so the writers see a uniform fact interface."""

    def __init__(self, fact: Fact, article: Article, source: Source):
        self.text_te = fact.text_te
        self.text_en = fact.text_en
        self.evidence_level = fact.evidence_level
        self.confidence = fact.confidence
        self.attributed_to = fact.attributed_to
        self.source_name = source.name
        self.source_title = article.title_raw
        self.published_at = article.published_at
        self.source_article_id = article.id


def _write_story(session: Session, story: Story, source: Source,
                 report: SweepReport) -> None:
    """Run the editorial stages for one story."""
    articles = _story_articles(session, story)
    sources = _story_sources(session, story)
    if not articles:
        return

    # --- facts -------------------------------------------------------------
    facts = _collect_facts(session, story, articles, sources)
    if not facts:
        story.status = "draft"
        story.needs_review = True
        return

    # --- source comparison --------------------------------------------------
    comparisons = [
        compare_articles(articles[i], articles[j])
        for i in range(len(articles)) for j in range(i + 1, len(articles))
    ]
    summary = summarise_comparisons(comparisons, [s.name for s in sources])
    for link in story.sources_links:
        if summary.conflicting:
            link.conflicts_with = summary.conflicting[0]

    # --- location + section + importance -----------------------------------
    corpus = " ".join((a.title_raw or "") + " " + (a.summary_text or "") for a in articles)
    location = locate_story(
        articles[0].title_raw, corpus,
        feed_title=source.default_section or source.name)
    story.state = location.geo.state
    story.district = location.geo.district
    story.mandal = location.geo.mandal
    story.locality = location.geo.locality

    section = classify_section(
        articles[0].title_raw, corpus,
        source_section=source.default_section,
        location=location,
        is_breaking=any(a for a in articles if _article_is_breaking(a, source)),
    )
    story.section = section
    story.is_breaking = section == "breaking" or any(
        _article_is_breaking(a, source) for a in articles)
    story.is_developing = story.is_developing or len(articles) >= 3

    evidence_score = _evidence_score(facts, summary, sources)
    story.num_sources = len(sources)
    story.evidence_score = round(evidence_score, 3)
    importance = score_importance(
        evidence_score=evidence_score,
        num_sources=len(sources),
        source_trust=mean([s.trust_score for s in sources]) if sources else 0.5,
        published_at=story.first_seen_at,
        is_breaking=story.is_breaking,
        is_developing=story.is_developing,
        district=story.district,
        section=story.section,
    )
    story.importance = round(importance.score, 3)
    story.confidence = round(min(importance.score, evidence_score), 3)

    # --- editorial ----------------------------------------------------------
    fact_views = [
        _FactView(fact, _article_for_fact(session, fact, articles), _source_for_fact(fact, sources, articles))
        for fact in facts
    ]
    coverage: List[str] = []
    for language in ("te", "ten", "en"):
        try:
            headline_draft = write_headline(
                fact_views, language=language, district=story.district,
                session=session, story_id=story.id)
            article_draft = write_article(
                fact_views, language=language,
                headline=headline_draft.headline, district=story.district,
                session=session, story_id=story.id)
            if article_draft.body:
                setattr(story, f"headline_{language}", article_draft.headline or headline_draft.headline)
                setattr(story, f"lead_{language}", article_draft.lead)
                setattr(story, f"body_{language}", article_draft.body)
                coverage.append(language)
        except Exception as exc:  # noqa: BLE001
            report.errors.append(f"writer {language}: {type(exc).__name__}: {exc}")
            logger.warning("writer %s failed for story %s: %s", language, story.id, exc)

    if story.body_te and _is_new_content(story, articles):
        story.version = (story.version or 1) + 1

    # --- entities -----------------------------------------------------------
    _extract_entities(session, story, corpus)

    # --- publish gate -------------------------------------------------------
    decision = decide_publication(
        importance=importance, evidence_score=evidence_score,
        num_sources=len(sources), section=story.section,
        has_facts=bool(facts), language_coverage=coverage,
    )
    if decision.publish and story.status not in ("published", "corrected"):
        story.status = decision.status
        story.auto_published = decision.status == "auto_published"
        story.published_at = story.published_at or datetime.utcnow()
        report.stories_published += 1
    elif not decision.publish and story.status not in ("published", "corrected"):
        story.status = decision.status
        story.needs_review = decision.status == "held"
        report.stories_held += 1

    if story.is_breaking and story.status not in ("breaking", "corrected"):
        record_update(session, story, _breaking_note(story, sources))

    # --- media --------------------------------------------------------------
    _attach_primary_image(session, story, articles)
    story.updated_at = datetime.utcnow()
    session.flush()


def _article_is_breaking(article: Article, source: Source) -> bool:
    if not source.is_breaking_capable:
        return False
    markers = ("breaking", "బ్రేకింగ్", "ఫ్లాష్", "just in", "అత్యవసరం")
    haystack = f"{article.title_raw or ''} {article.summary_text or ''}".lower()
    return any(marker in haystack for marker in markers)


def _breaking_note(story: Story, sources: List[Source]) -> Any:
    from newsroom.pipeline.publish import StoryChange
    return StoryChange(
        kind="escalation",
        headline=story.headline_te,
        text_te="ఈ వార్త బ్రేకింగ్‌గా గుర్తించబడింది.",
        text_en="This story was flagged as breaking by the newsroom.",
        article_id=None, applied_by="pipeline",
        note=f"escalated from {len(sources)} source(s)",
    )


def _collect_facts(session: Session, story: Story, articles: List[Article],
                   sources: List[Source]) -> List[Fact]:
    """Extract and persist facts from every article in the cluster."""
    by_id = {article.id: article for article in articles}
    source_by_id = {source.id: source for source in sources}

    existing = list(session.execute(
        select(Fact).where(Fact.story_id == story.id, Fact.status == "active")
    ).scalars().all())
    if existing and _all_articles_covered(existing, articles):
        return existing

    incoming: List[Any] = []
    seen_signatures: set[str] = set()
    for article in articles:
        source = source_by_id.get(article.source_id)
        text = article.body_text or article.summary_text or article.title_raw
        try:
            extracted = extract_facts(
                text, language=article.language,
                article_id=article.id, session=session, story_id=story.id)
        except Exception as exc:  # noqa: BLE001
            logger.info("fact extraction failed for article %s: %s", article.id, exc)
            continue
        for item in extracted:
            signature = _fact_key(item.text_te)
            if signature in seen_signatures:
                continue
            seen_signatures.add(signature)
            fact = Fact(
                story_id=story.id,
                text_te=item.text_te,
                text_en=item.text_en,
                evidence_level=item.level,
                confidence=item.confidence,
                attributed_to=item.attributed_to,
                source_article_id=article.id,
                status="active",
                rank=len(incoming),
            )
            session.add(fact)
            session.flush()
            incoming.append(fact)

    facts = merge_facts([_as_extracted(f) for f in existing],
                        [_as_extracted(f) for f in incoming])
    _persist_merged(session, story, facts)
    return list(session.execute(
        select(Fact).where(Fact.story_id == story.id, Fact.status == "active")
        .order_by(Fact.rank.asc())
    ).scalars().all())


def _as_extracted(fact: Fact):
    from newsroom.pipeline.facts import ExtractedFact
    return ExtractedFact(
        text_te=fact.text_te, text_en=fact.text_en,
        level=fact.evidence_level, confidence=fact.confidence,
        attributed_to=fact.attributed_to,
    )


def _persist_merged(session: Session, story: Story, facts: List[Any]) -> None:
    """Re-rank persisted facts according to the merged order."""
    rows = list(session.execute(
        select(Fact).where(Fact.story_id == story.id, Fact.status == "active")
    ).scalars().all())
    by_key = {_fact_key(fact.text_te): fact for fact in rows}
    for rank, fact in enumerate(facts):
        row = by_key.get(_fact_key(fact.text_te))
        if row is not None:
            row.rank = rank
            row.evidence_level = fact.level
            row.confidence = fact.confidence
    session.flush()


def _fact_key(text: Optional[str]) -> str:
    import hashlib
    from newsroom.nlp.telugu import content_tokens
    normalised = "".join(content_tokens(text)).lower()
    return hashlib.sha256(normalised.encode("utf-8")).hexdigest()[:16]


def _all_articles_covered(facts: List[Fact], articles: List[Article]) -> bool:
    covered = {fact.source_article_id for fact in facts}
    return covered >= {article.id for article in articles}


def _evidence_score(facts: List[Fact], summary, sources: List[Source]) -> float:
    if not facts:
        return 0.0
    weights = [EvidenceLevel(fact.evidence_level).weight * (0.5 + 0.5 * fact.confidence)
               for fact in facts]
    base = mean(weights)
    corroboration = min(0.25, 0.08 * max(0, len(sources) - 1))
    conflict_penalty = 0.1 * len(summary.conflicting)
    return max(0.02, min(1.0, base * 0.85 + corroboration - conflict_penalty))


def _is_new_content(story: Story, articles: List[Article]) -> bool:
    latest = max((a.ingested_at for a in articles), default=None)
    if latest is None:
        return False
    return story.updated_at is None or latest > story.updated_at


_ENTITY_KINDS = {
    "person": ("శ్రీ", "గారు", "మంత్రి", "ఎమ్మెల్యే", "ఎంపీ", "chairman", "minister",
               "mla", "mp", "officer", "అధికారి"),
    "org": ("పార్టీ", "సంస్థ", "కంపెనీ", "విశ్వవిద్యాలయం", "party", "corporation",
            "university", "federation", "సంఘం"),
    "party": ("కాంగ్రెస్", "బీజేపీ", "టీఆర్ఎస్", "బీఆర్ఎస్", "congress", "bjp",
              "brs", "trs", "పార్టీ"),
    "place": ("జిల్లా", "మండలం", "గ్రామం", "నగరం", "district", "town", "village"),
}


def _extract_entities(session: Session, story: Story, corpus: str) -> None:
    """Extract named entities with a lightweight rule-based recogniser."""
    from newsroom.nlp.telugu import content_tokens
    tokens = content_tokens(corpus, min_len=3)
    counts: Dict[str, int] = {}
    for token in tokens:
        counts[token] = counts.get(token, 0) + 1

    existing = {row[0] for row in session.execute(
        select(Entity.name).where(Entity.story_id == story.id)).all()}
    added = 0
    for name, count in sorted(counts.items(), key=lambda kv: kv[1], reverse=True):
        if added >= 12:
            break
        if count < 2 or name in existing:
            continue
        kind = _entity_kind(name)
        if kind is None:
            continue
        session.add(Entity(story_id=story.id, name=name, kind=kind,
                           mention_count=count))
        existing.add(name)
        added += 1
    session.flush()


def _entity_kind(token: str) -> Optional[str]:
    lowered = token.lower()
    for kind, markers in _ENTITY_KINDS.items():
        if any(marker in lowered for marker in markers):
            return kind
    # Capitalised Latin token mid-sentence is a probable proper noun.
    if token[:1].isupper() and token.isalpha():
        return "person"
    return None


def _attach_primary_image(session: Session, story: Story, articles: List[Article]) -> None:
    if story.primary_image_url:
        return
    for article in articles:
        if not article.image_url:
            continue
        source = article.source
        story.primary_image_url = article.image_url
        story.primary_image_license = "source"
        story.primary_image_attribution = (
            f"Publisher-supplied thumbnail: {source.name if source else 'unknown'}. "
            f"Dasha News links to the originating report."
        )
        media = Media(
            story_id=story.id, article_id=article.id, url=article.image_url,
            provider="source", license="source",
            attribution=story.primary_image_attribution,
            credit_text=source.name if source else None,
            status="primary",
        )
        session.add(media)
        session.flush()
        return


# ---------------------------------------------------------------------------
# Media generation
# ---------------------------------------------------------------------------

def _generate_media(session: Session, report: SweepReport) -> None:
    """Generate audio (and prepare shorts) for published stories lacking it."""
    settings = get_settings()
    media_dir = settings.resolved_media_dir

    stories = session.execute(
        select(Story).where(Story.status.in_(("auto_published", "published", "developing",
                                             "breaking", "corrected")))
        .order_by(Story.importance.desc()).limit(12)
    ).scalars().all()

    generated = 0
    for story in stories:
        existing = session.execute(
            select(Audio.id).where(Audio.story_id == story.id).limit(1)
        ).first()
        if existing:
            continue
        body = story.body_te or story.body_en or ""
        if not body:
            continue
        try:
            result = render_audio(
                body, language="te", out_dir=media_dir / "audio",
                name=f"story-{story.id}-te")
            session.add(Audio(
                story_id=story.id, language="te", voice=result.voice,
                rate=settings.tts_rate, duration_seconds=result.duration_seconds,
                path=result.path or "", byte_size=result.byte_size,
                status=result.status,
            ))
            session.flush()
            generated += 1
        except Exception as exc:  # noqa: BLE001
            report.errors.append(f"audio story {story.id}: {type(exc).__name__}: {exc}")
    report.media_generated = generated
    session.commit()


def _schedule_next_run(session: Session) -> None:
    """Note the next sweep time as a queued job for the scheduler."""
    session.add(Job(stage="sweep", status="queued",
                    payload_json="{}", priority=0))
    session.commit()


def regenerate_story(session: Session, story: Story, *, applied_by: str = "admin"
                     ) -> Story:
    """Re-render a story from its facts. Used after corrections."""
    sources = _story_sources(session, story)
    if not sources:
        return story
    _write_story(session, story, sources[0], _SweepStub())
    audit(session, applied_by, "regenerate", "story", story.id,
          detail="story re-rendered from facts")
    session.commit()
    return story


@dataclass
class _SweepStub:
    """Minimal report stand-in for single-story regeneration."""
    errors: List[str] = field(default_factory=list)
    stories_published: int = 0
    stories_held: int = 0
    stories_updated: int = 0
