"""SQLAlchemy ORM models.

Design rule: the *canonical* record is `Story` + its `Fact` children. Every
generated article body (`Story.body_te`, `body_ten`, `body_en`) is a *rendering*
of those facts and can always be regenerated. Nothing downstream may treat
generated prose as ground truth.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, List, Optional

from sqlalchemy import (
    Boolean,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


class Base(DeclarativeBase):
    pass


class Source(Base):
    """A news outlet or feed the Scout watches."""

    __tablename__ = "sources"
    __table_args__ = (UniqueConstraint("guid", name="uq_sources_guid"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    guid: Mapped[str] = mapped_column(String(120), unique=True, index=True)
    name: Mapped[str] = mapped_column(String(200))
    site_url: Mapped[str] = mapped_column(String(500))
    feed_url: Mapped[Optional[str]] = mapped_column(String(500))
    kind: Mapped[str] = mapped_column(String(20), default="rss")  # rss | atom | web
    language: Mapped[str] = mapped_column(String(8), default="te")  # te | en | ten
    trust_score: Mapped[float] = mapped_column(Float, default=0.5)
    default_section: Mapped[Optional[str]] = mapped_column(String(40))
    is_enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    is_breaking_capable: Mapped[bool] = mapped_column(Boolean, default=False)
    last_fetched_at: Mapped[Optional[datetime]] = mapped_column(DateTime)
    fetch_error_count: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)

    # ---- Acquisition ------------------------------------------------------
    # How the newsroom reaches this outlet. ``httpx`` is the default and needs
    # no extra dependency; ``scrapling`` (TLS impersonation) and
    # ``scrapling-dynamic`` (a real browser) are opt-in per source and require
    # the optional ``scrapling[fetchers]`` extra.
    fetch_backend: Mapped[str] = mapped_column(String(40), default="httpx")
    # Set only for outlets whose article bodies are produced by JavaScript.
    # Browser automation is never started without an explicit operator opt-in
    # (ACQUISITION_BROWSER_ENABLED) as well as this flag.
    requires_js: Mapped[bool] = mapped_column(Boolean, default=False)
    # Overrides the global politeness interval for this outlet, in seconds.
    politeness_seconds: Mapped[Optional[float]] = mapped_column(Float)

    articles: Mapped[List["Article"]] = relationship(back_populates="source")

    def to_summary(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "guid": self.guid,
            "name": self.name,
            "site_url": self.site_url,
            "language": self.language,
            "trust_score": self.trust_score,
            "is_enabled": self.is_enabled,
            "default_section": self.default_section,
            "last_fetched_at": self.last_fetched_at.isoformat() if self.last_fetched_at else None,
            "fetch_error_count": self.fetch_error_count,
            "kind": self.kind,
            "fetch_backend": self.fetch_backend,
            "requires_js": self.requires_js,
            "politeness_seconds": self.politeness_seconds,
        }


class Article(Base):
    """Raw ingested item, exactly as captured. Never mutated after extraction."""

    __tablename__ = "articles"
    __table_args__ = (
        UniqueConstraint("source_id", "guid", name="uq_articles_source_guid"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    source_id: Mapped[int] = mapped_column(ForeignKey("sources.id"), index=True)
    guid: Mapped[str] = mapped_column(String(400))
    url: Mapped[str] = mapped_column(String(1000))
    title_raw: Mapped[str] = mapped_column(String(600))
    title_te: Mapped[Optional[str]] = mapped_column(String(600))
    title_en: Mapped[Optional[str]] = mapped_column(String(600))
    author: Mapped[Optional[str]] = mapped_column(String(300))
    body_html: Mapped[Optional[str]] = mapped_column(Text)
    body_text: Mapped[Optional[str]] = mapped_column(Text)
    summary_text: Mapped[Optional[str]] = mapped_column(Text)
    language: Mapped[str] = mapped_column(String(8), default="te")
    image_url: Mapped[Optional[str]] = mapped_column(String(1000))
    published_at: Mapped[Optional[datetime]] = mapped_column(DateTime, index=True)
    ingested_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, index=True)
    digest: Mapped[Optional[str]] = mapped_column(String(64), index=True)  # simhash hex
    signature: Mapped[Optional[str]] = mapped_column(String(64))           # title-normalised
    word_count: Mapped[int] = mapped_column(Integer, default=0)
    status: Mapped[str] = mapped_column(String(20), default="new", index=True)
    # new -> clustered -> processed | rejected
    cluster_id: Mapped[Optional[str]] = mapped_column(String(64), index=True)
    rejection_reason: Mapped[Optional[str]] = mapped_column(String(200))

    # ---- Acquisition provenance ------------------------------------------
    # How this row was actually obtained, so an editor can tell a full-text
    # extraction from a two-line RSS summary that merely fell back.
    canonical_url: Mapped[Optional[str]] = mapped_column(String(1000), index=True)
    fetch_method: Mapped[Optional[str]] = mapped_column(String(40))
    extraction_confidence: Mapped[Optional[float]] = mapped_column(Float)

    source: Mapped[Optional["Source"]] = relationship(back_populates="articles")

    def to_summary(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "url": self.url,
            "title": self.title_te or self.title_raw,
            "source": self.source.name if self.source else None,
            "published_at": self.published_at.isoformat() if self.published_at else None,
            "status": self.status,
        }


class Story(Base):
    """The canonical story. One row per real-world event."""

    __tablename__ = "stories"

    id: Mapped[int] = mapped_column(primary_key=True)
    cluster_id: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    slug: Mapped[str] = mapped_column(String(300), index=True)

    headline_te: Mapped[Optional[str]] = mapped_column(String(600))
    headline_ten: Mapped[Optional[str]] = mapped_column(String(600))
    headline_en: Mapped[Optional[str]] = mapped_column(String(600))
    lead_te: Mapped[Optional[str]] = mapped_column(Text)
    lead_ten: Mapped[Optional[str]] = mapped_column(Text)
    lead_en: Mapped[Optional[str]] = mapped_column(Text)
    body_te: Mapped[Optional[str]] = mapped_column(Text)
    body_ten: Mapped[Optional[str]] = mapped_column(Text)
    body_en: Mapped[Optional[str]] = mapped_column(Text)

    section: Mapped[str] = mapped_column(String(40), index=True)
    status: Mapped[str] = mapped_column(String(30), default="draft", index=True)
    # draft | held | auto_published | published | developing | breaking |
    # corrected | killed

    importance: Mapped[float] = mapped_column(Float, default=0.0)
    evidence_score: Mapped[float] = mapped_column(Float, default=0.0)
    confidence: Mapped[float] = mapped_column(Float, default=0.0)
    num_sources: Mapped[int] = mapped_column(Integer, default=0)

    state: Mapped[Optional[str]] = mapped_column(String(60), index=True)
    district: Mapped[Optional[str]] = mapped_column(String(80), index=True)
    mandal: Mapped[Optional[str]] = mapped_column(String(120))
    locality: Mapped[Optional[str]] = mapped_column(String(160))

    is_breaking: Mapped[bool] = mapped_column(Boolean, default=False, index=True)
    is_developing: Mapped[bool] = mapped_column(Boolean, default=False)
    auto_published: Mapped[bool] = mapped_column(Boolean, default=False)
    needs_review: Mapped[bool] = mapped_column(Boolean, default=False)
    corrections_count: Mapped[int] = mapped_column(Integer, default=0)
    version: Mapped[int] = mapped_column(Integer, default=1)

    primary_image_url: Mapped[Optional[str]] = mapped_column(String(1000))
    primary_image_license: Mapped[Optional[str]] = mapped_column(String(200))
    primary_image_attribution: Mapped[Optional[str]] = mapped_column(String(400))

    first_seen_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, index=True)
    published_at: Mapped[Optional[datetime]] = mapped_column(DateTime, index=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, onupdate=utcnow)
    expires_at: Mapped[Optional[datetime]] = mapped_column(DateTime)

    facts: Mapped[List["Fact"]] = relationship(
        back_populates="story", cascade="all, delete-orphan"
    )
    sources_links: Mapped[List["StorySource"]] = relationship(
        back_populates="story", cascade="all, delete-orphan"
    )
    entities: Mapped[List["Entity"]] = relationship(
        back_populates="story", cascade="all, delete-orphan"
    )
    updates: Mapped[List["StoryUpdate"]] = relationship(
        back_populates="story", cascade="all, delete-orphan"
    )
    media: Mapped[List["Media"]] = relationship(
        back_populates="story", cascade="all, delete-orphan"
    )
    audio: Mapped[List["Audio"]] = relationship(
        back_populates="story", cascade="all, delete-orphan"
    )
    shorts: Mapped[List["Short"]] = relationship(
        back_populates="story", cascade="all, delete-orphan"
    )

    def to_summary(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "cluster_id": self.cluster_id,
            "headline_te": self.headline_te,
            "headline_ten": self.headline_ten,
            "headline_en": self.headline_en,
            "lead_te": self.lead_te,
            "section": self.section,
            "status": self.status,
            "importance": round(self.importance, 3),
            "evidence_score": round(self.evidence_score, 3),
            "num_sources": self.num_sources,
            "district": self.district,
            "state": self.state,
            "is_breaking": self.is_breaking,
            "is_developing": self.is_developing,
            "image_url": self.primary_image_url,
            "published_at": self.published_at.isoformat() if self.published_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
        }


class Fact(Base):
    """One discrete, attributable, evidence-levelled statement."""

    __tablename__ = "facts"

    id: Mapped[int] = mapped_column(primary_key=True)
    story_id: Mapped[int] = mapped_column(ForeignKey("stories.id"), index=True)
    text_te: Mapped[str] = mapped_column(Text)
    text_en: Mapped[Optional[str]] = mapped_column(Text)
    evidence_level: Mapped[str] = mapped_column(String(20), default="claim")
    confidence: Mapped[float] = mapped_column(Float, default=0.5)
    attributed_to: Mapped[Optional[str]] = mapped_column(String(300))
    source_article_id: Mapped[Optional[int]] = mapped_column(ForeignKey("articles.id"))
    status: Mapped[str] = mapped_column(String(20), default="active")  # active | superseded | retracted
    rank: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    superseded_by: Mapped[Optional[int]] = mapped_column(ForeignKey("facts.id"))

    story: Mapped[Optional["Story"]] = relationship(back_populates="facts")

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "text_te": self.text_te,
            "text_en": self.text_en,
            "evidence_level": self.evidence_level,
            "confidence": round(self.confidence, 3),
            "attributed_to": self.attributed_to,
            "status": self.status,
            "rank": self.rank,
        }


class StorySource(Base):
    """Which raw articles back a story, and how much each contributed."""

    __tablename__ = "story_sources"

    id: Mapped[int] = mapped_column(primary_key=True)
    story_id: Mapped[int] = mapped_column(ForeignKey("stories.id"), index=True)
    article_id: Mapped[int] = mapped_column(ForeignKey("articles.id"))
    source_id: Mapped[int] = mapped_column(ForeignKey("sources.id"))
    contribution: Mapped[float] = mapped_column(Float, default=0.5)
    corroborates: Mapped[bool] = mapped_column(Boolean, default=True)
    conflicts_with: Mapped[Optional[str]] = mapped_column(String(200))
    first_seen_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)

    story: Mapped[Optional["Story"]] = relationship(back_populates="sources_links")


class Entity(Base):
    __tablename__ = "entities"

    id: Mapped[int] = mapped_column(primary_key=True)
    story_id: Mapped[int] = mapped_column(ForeignKey("stories.id"), index=True)
    name: Mapped[str] = mapped_column(String(300), index=True)
    kind: Mapped[str] = mapped_column(String(20))  # person | org | place | party
    mention_count: Mapped[int] = mapped_column(Integer, default=1)
    first_seen_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)

    story: Mapped[Optional["Story"]] = relationship(back_populates="entities")


class StoryUpdate(Base):
    """Append-only timeline: updates, corrections, verifications, escalations."""

    __tablename__ = "story_updates"

    id: Mapped[int] = mapped_column(primary_key=True)
    story_id: Mapped[int] = mapped_column(ForeignKey("stories.id"), index=True)
    kind: Mapped[str] = mapped_column(String(30))  # update | correction | verification | escalation | note
    headline: Mapped[Optional[str]] = mapped_column(String(600))
    text_te: Mapped[Optional[str]] = mapped_column(Text)
    text_en: Mapped[Optional[str]] = mapped_column(Text)
    article_id: Mapped[Optional[int]] = mapped_column(ForeignKey("articles.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, index=True)
    applied_by: Mapped[Optional[str]] = mapped_column(String(120))

    story: Mapped[Optional["Story"]] = relationship(back_populates="updates")


class Media(Base):
    """Images with their license/attribution metadata attached."""

    __tablename__ = "media"

    id: Mapped[int] = mapped_column(primary_key=True)
    story_id: Mapped[Optional[int]] = mapped_column(ForeignKey("stories.id"), index=True)
    article_id: Mapped[Optional[int]] = mapped_column(ForeignKey("articles.id"))
    url: Mapped[str] = mapped_column(String(1000))
    local_path: Mapped[Optional[str]] = mapped_column(String(1000))
    provider: Mapped[str] = mapped_column(String(60))  # wikimedia|unsplash|pexels|generated|source
    license: Mapped[Optional[str]] = mapped_column(String(200))
    attribution: Mapped[Optional[str]] = mapped_column(String(400))
    credit_text: Mapped[Optional[str]] = mapped_column(String(400))
    width: Mapped[Optional[int]] = mapped_column(Integer)
    height: Mapped[Optional[int]] = mapped_column(Integer)
    status: Mapped[str] = mapped_column(String(20), default="candidate")  # candidate|primary|rejected
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)

    story: Mapped[Optional["Story"]] = relationship(back_populates="media")


class Audio(Base):
    __tablename__ = "audio"

    id: Mapped[int] = mapped_column(primary_key=True)
    story_id: Mapped[int] = mapped_column(ForeignKey("stories.id"), index=True)
    language: Mapped[str] = mapped_column(String(8))  # te | en | ten
    voice: Mapped[str] = mapped_column(String(80))
    rate: Mapped[int] = mapped_column(Integer, default=160)
    duration_seconds: Mapped[float] = mapped_column(Float, default=0.0)
    path: Mapped[str] = mapped_column(String(1000))
    byte_size: Mapped[int] = mapped_column(Integer, default=0)
    status: Mapped[str] = mapped_column(String(20), default="pending")  # pending|ready|failed
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)

    story: Mapped[Optional["Story"]] = relationship(back_populates="audio")


class Short(Base):
    __tablename__ = "shorts"

    id: Mapped[int] = mapped_column(primary_key=True)
    story_id: Mapped[int] = mapped_column(ForeignKey("stories.id"), index=True)
    language: Mapped[str] = mapped_column(String(8), default="te")
    path: Mapped[str] = mapped_column(String(1000))
    poster_path: Mapped[Optional[str]] = mapped_column(String(1000))
    duration_seconds: Mapped[float] = mapped_column(Float, default=0.0)
    byte_size: Mapped[int] = mapped_column(Integer, default=0)
    status: Mapped[str] = mapped_column(String(20), default="pending")
    caption_te: Mapped[Optional[str]] = mapped_column(String(600))
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)

    story: Mapped[Optional["Story"]] = relationship(back_populates="shorts")


class Submission(Base):
    """A reader-submitted tip. Treated as untrusted until verified."""

    __tablename__ = "submissions"

    id: Mapped[int] = mapped_column(primary_key=True)
    device_id: Mapped[str] = mapped_column(String(120), index=True)
    body: Mapped[str] = mapped_column(Text)
    category: Mapped[Optional[str]] = mapped_column(String(40))
    location_text: Mapped[Optional[str]] = mapped_column(String(400))
    contact: Mapped[Optional[str]] = mapped_column(String(300))
    media_path: Mapped[Optional[str]] = mapped_column(String(1000))
    status: Mapped[str] = mapped_column(String(20), default="new", index=True)
    # new | triaged | verified | published | rejected
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, index=True)
    triage_note: Mapped[Optional[str]] = mapped_column(Text)
    story_id: Mapped[Optional[int]] = mapped_column(ForeignKey("stories.id"))


class AcquisitionEvent(Base):
    """One outbound acquisition attempt, for reliability observability.

    Every fetch the newsroom makes on a source's behalf is recorded here, so
    that a silently empty feed or a permanently blocked outlet shows up in the
    admin console instead of looking like a slow news day. AI calls already
    have ``AiCall``; this is the acquisition-side equivalent.

    Rows are write-once and never block the pipeline: a failure to record is
    logged and swallowed, never propagated.
    """

    __tablename__ = "acquisition_events"

    id: Mapped[int] = mapped_column(primary_key=True)
    source_id: Mapped[Optional[int]] = mapped_column(ForeignKey("sources.id"), index=True)
    url: Mapped[str] = mapped_column(String(1000), index=True)
    stage: Mapped[str] = mapped_column(String(20), index=True)  # discover | list | extract
    fetch_method: Mapped[str] = mapped_column(String(40))       # rss | httpx | scrapling | scrapling-dynamic
    http_status: Mapped[int] = mapped_column(Integer, default=0)
    extraction_ok: Mapped[bool] = mapped_column(Boolean, default=False)
    extraction_confidence: Mapped[float] = mapped_column(Float, default=0.0)
    latency_ms: Mapped[int] = mapped_column(Integer, default=0)
    retries: Mapped[int] = mapped_column(Integer, default=0)
    parser_version: Mapped[Optional[str]] = mapped_column(String(40))
    error_kind: Mapped[Optional[str]] = mapped_column(String(120))
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, index=True)

    source: Mapped[Optional["Source"]] = relationship()


class Job(Base):
    """The AI processing queue."""

    __tablename__ = "jobs"

    id: Mapped[int] = mapped_column(primary_key=True)
    stage: Mapped[str] = mapped_column(String(60), index=True)
    payload_json: Mapped[Optional[str]] = mapped_column(Text)
    status: Mapped[str] = mapped_column(String(20), default="queued", index=True)
    # queued | running | done | failed | dead
    priority: Mapped[int] = mapped_column(Integer, default=0)
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    max_attempts: Mapped[int] = mapped_column(Integer, default=3)
    error: Mapped[Optional[str]] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, index=True)
    started_at: Mapped[Optional[datetime]] = mapped_column(DateTime)
    finished_at: Mapped[Optional[datetime]] = mapped_column(DateTime)


class AiCall(Base):
    """Auditable record of every model call, for cost and drift analysis."""

    __tablename__ = "ai_calls"

    id: Mapped[int] = mapped_column(primary_key=True)
    provider: Mapped[str] = mapped_column(String(60))
    model: Mapped[str] = mapped_column(String(120))
    stage: Mapped[str] = mapped_column(String(60))
    story_id: Mapped[Optional[int]] = mapped_column(ForeignKey("stories.id"))
    tokens_in: Mapped[int] = mapped_column(Integer, default=0)
    tokens_out: Mapped[int] = mapped_column(Integer, default=0)
    duration_ms: Mapped[int] = mapped_column(Integer, default=0)
    success: Mapped[bool] = mapped_column(Boolean, default=True)
    error: Mapped[Optional[str]] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, index=True)


class AuditLog(Base):
    __tablename__ = "audit_log"

    id: Mapped[int] = mapped_column(primary_key=True)
    actor: Mapped[str] = mapped_column(String(120))
    action: Mapped[str] = mapped_column(String(80))
    target_type: Mapped[str] = mapped_column(String(40))
    target_id: Mapped[str] = mapped_column(String(120))
    detail: Mapped[Optional[str]] = mapped_column(Text)
    ip: Mapped[Optional[str]] = mapped_column(String(64))
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, index=True)


class Device(Base):
    __tablename__ = "devices"
    __table_args__ = (UniqueConstraint("device_id", name="uq_devices_device_id"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    device_id: Mapped[str] = mapped_column(String(120), unique=True, index=True)
    locale: Mapped[str] = mapped_column(String(16), default="te")
    theme: Mapped[str] = mapped_column(String(16), default="system")
    push_token: Mapped[Optional[str]] = mapped_column(String(400))
    breaking_alerts: Mapped[bool] = mapped_column(Boolean, default=True)
    daily_digest: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    last_seen_at: Mapped[Optional[datetime]] = mapped_column(DateTime)


class Bookmark(Base):
    __tablename__ = "bookmarks"
    __table_args__ = (
        UniqueConstraint("device_id", "story_id", name="uq_bookmarks_device_story"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    device_id: Mapped[str] = mapped_column(String(120), index=True)
    story_id: Mapped[int] = mapped_column(ForeignKey("stories.id"), index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, index=True)


class ReadingHistory(Base):
    __tablename__ = "reading_history"
    __table_args__ = (
        UniqueConstraint("device_id", "story_id", name="uq_history_device_story"),
    )

    id: Mapped[int] = mapped_column(primary_key=True)
    device_id: Mapped[str] = mapped_column(String(120), index=True)
    story_id: Mapped[int] = mapped_column(ForeignKey("stories.id"), index=True)
    read_seconds: Mapped[int] = mapped_column(Integer, default=0)
    completed: Mapped[bool] = mapped_column(Boolean, default=False)
    first_read_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    last_read_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, onupdate=utcnow)


class Notification(Base):
    __tablename__ = "notifications"

    id: Mapped[int] = mapped_column(primary_key=True)
    device_id: Mapped[Optional[str]] = mapped_column(String(120), index=True)
    kind: Mapped[str] = mapped_column(String(40), default="breaking")
    title_te: Mapped[str] = mapped_column(String(300))
    body_te: Mapped[Optional[str]] = mapped_column(Text)
    story_id: Mapped[Optional[int]] = mapped_column(ForeignKey("stories.id"))
    sent_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, index=True)
    read_at: Mapped[Optional[datetime]] = mapped_column(DateTime)
    delivered: Mapped[bool] = mapped_column(Boolean, default=False)


Index("ix_stories_section_published", Story.section, Story.published_at)
Index("ix_stories_district_published", Story.district, Story.published_at)
Index("ix_jobs_status_created", Job.status, Job.created_at)
Index("ix_acquisition_source_created", AcquisitionEvent.source_id, AcquisitionEvent.created_at)
