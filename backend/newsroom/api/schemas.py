"""Response schemas shared by the public and admin APIs."""

from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field


class SourceSummary(BaseModel):
    id: int
    guid: str
    name: str
    site_url: str
    language: str
    trust_score: float
    is_enabled: bool
    default_section: Optional[str] = None
    last_fetched_at: Optional[str] = None
    fetch_error_count: int = 0
    kind: str = "rss"
    fetch_backend: str = "httpx"
    requires_js: bool = False
    politeness_seconds: Optional[float] = None


class AcquisitionEventView(BaseModel):
    """One recorded fetch — the observability the newsroom owes every source."""

    id: int
    source_id: Optional[int] = None
    url: str
    stage: str
    fetch_method: str
    http_status: int
    extraction_ok: bool
    extraction_confidence: float = 0.0
    latency_ms: int = 0
    retries: int = 0
    parser_version: Optional[str] = None
    error_kind: Optional[str] = None
    created_at: str


class FactView(BaseModel):
    id: int
    text_te: str
    text_en: Optional[str] = None
    evidence_level: str
    evidence_label_te: Optional[str] = None
    evidence_label_en: Optional[str] = None
    confidence: float
    attributed_to: Optional[str] = None
    status: str
    rank: int


class SourceLinkView(BaseModel):
    id: int
    source_name: Optional[str] = None
    site_url: Optional[str] = None
    article_url: Optional[str] = None
    article_title: Optional[str] = None
    published_at: Optional[str] = None
    corroborates: bool
    conflicts_with: Optional[str] = None


class UpdateView(BaseModel):
    id: int
    kind: str
    headline: Optional[str] = None
    text_te: Optional[str] = None
    text_en: Optional[str] = None
    created_at: str
    applied_by: Optional[str] = None


class StoryCard(BaseModel):
    id: int
    cluster_id: str
    slug: str
    headline_te: Optional[str] = None
    headline_ten: Optional[str] = None
    headline_en: Optional[str] = None
    lead_te: Optional[str] = None
    section: str
    section_label_te: Optional[str] = None
    section_label_en: Optional[str] = None
    status: str
    status_label_te: Optional[str] = None
    importance: float
    evidence_score: float
    num_sources: int
    district: Optional[str] = None
    mandal: Optional[str] = None
    state: Optional[str] = None
    is_breaking: bool
    is_developing: bool
    # Who put this story here, and whether automation may touch its words. The
    # editor app shows these differently; the reader app never sees them.
    origin: str = "automated"
    editor_locked: bool = False
    needs_review: bool = False
    image_url: Optional[str] = None
    audio_url: Optional[str] = None
    has_audio: bool = False
    published_at: Optional[str] = None
    updated_at: Optional[str] = None


class StoryDetail(StoryCard):
    body_te: Optional[str] = None
    body_ten: Optional[str] = None
    body_en: Optional[str] = None
    facts: List[FactView] = Field(default_factory=list)
    sources: List[SourceLinkView] = Field(default_factory=list)
    updates: List[UpdateView] = Field(default_factory=list)
    corrections_count: int = 0
    version: int = 1
    confidence: float = 0.0


# ---------------------------------------------------------------------------
# The reader's view of a story.
#
# Everything above is the desk's own model: it carries the evidence taxonomy, the
# source links, the review flags and the provenance of every claim, because that
# is what an editor is checking a story against. Nothing of it belongs on a
# reader's phone. The separation is a schema, not a convention: a field that is
# not declared here cannot reach `/v1/front` even if a serializer later tries to
# add it, because pydantic drops undeclared keys rather than passing them through.
# ---------------------------------------------------------------------------


class ReaderStoryCard(BaseModel):
    """What a story looks like on the front page.

    The reader sees Dasha's story. Where the reporting came from, how strongly
    it is supported and whether a editor has locked it are answers to questions
    the reader did not ask, and publishing them is publishing the newsroom's
    working notes alongside its finished work.
    """

    id: int
    cluster_id: str
    slug: str
    headline_te: Optional[str] = None
    headline_ten: Optional[str] = None
    headline_en: Optional[str] = None
    lead_te: Optional[str] = None
    section: str
    section_label_te: Optional[str] = None
    section_label_en: Optional[str] = None
    status: str
    status_label_te: Optional[str] = None
    district: Optional[str] = None
    mandal: Optional[str] = None
    state: Optional[str] = None
    is_breaking: bool
    is_developing: bool
    image_url: Optional[str] = None
    audio_url: Optional[str] = None
    has_audio: bool = False
    published_at: Optional[str] = None
    updated_at: Optional[str] = None


class ReaderStoryDetail(ReaderStoryCard):
    """The same story, opened. Adds the body and nothing else."""
    body_te: Optional[str] = None
    body_ten: Optional[str] = None
    body_en: Optional[str] = None


class ReaderRegionPage(BaseModel):
    """One region of the front page, in the reader's vocabulary.

    `asked` is the question the region answers -- a district for Near You, the
    section slug otherwise -- and it is echoed because an empty region is only
    meaningful if the reader can see which question went unanswered.
    """

    items: List[ReaderStoryCard] = Field(default_factory=list)
    total: int = 0
    asked: Optional[str] = None
    has_more: bool = False


class ReaderFrontPage(BaseModel):
    """The whole front page in one round trip.

    Four regions in the order the reader scans them. Each region is a separate
    question over the same published room, so a story may appear in two -- the
    lead of the Telangana region can also be the freshest story in Now. That is
    the front page repeating itself, not a bug in the deduper.
    """

    now: ReaderRegionPage = Field(default_factory=ReaderRegionPage)
    near: ReaderRegionPage = Field(default_factory=ReaderRegionPage)
    telangana: ReaderRegionPage = Field(default_factory=ReaderRegionPage)
    india_world: ReaderRegionPage = Field(default_factory=ReaderRegionPage)
    language: str = "te"
    district: Optional[str] = None


class Page(BaseModel):
    items: List[Any]
    total: int
    page: int
    page_size: int
    has_more: bool


class RegionPage(BaseModel):
    """One region of the front page.

    `asked` is the question the region answers -- a district name for Near You,
    the section slug otherwise. It is echoed because a region is allowed to be
    empty, and an empty region is only meaningful if the reader can see which
    question went unanswered.
    """

    items: List[StoryCard] = Field(default_factory=list)
    total: int = 0
    asked: Optional[str] = None
    has_more: bool = False


class FrontPage(BaseModel):
    """The whole front page in one round trip.

    Four regions, in the order the reader scans them. Each region is a separate
    question over the same published room, so a story may appear in two -- the
    lead of the Telangana region can also be the freshest story in Now. That is
    the front page repeating itself, not a bug in the deduper.
    """

    now: RegionPage = Field(default_factory=RegionPage)
    near: RegionPage = Field(default_factory=RegionPage)
    telangana: RegionPage = Field(default_factory=RegionPage)
    india_world: RegionPage = Field(default_factory=RegionPage)
    language: str = "te"
    district: Optional[str] = None


class DeviceIn(BaseModel):
    device_id: str = Field(..., min_length=6, max_length=120)
    locale: str = "te"
    theme: str = "system"
    breaking_alerts: bool = True
    daily_digest: bool = False


class DeviceOut(BaseModel):
    device_id: str
    locale: str
    theme: str
    breaking_alerts: bool
    daily_digest: bool


class SubmissionIn(BaseModel):
    device_id: str = Field(..., min_length=6, max_length=120)
    body: str = Field(..., min_length=10, max_length=4000)
    category: Optional[str] = None
    location_text: Optional[str] = Field(None, max_length=400)
    contact: Optional[str] = Field(None, max_length=300)


class SubmissionOut(BaseModel):
    id: int
    status: str
    created_at: str


class SearchIn(BaseModel):
    q: str = Field(..., min_length=1, max_length=200)
    language: str = "te"
    limit: int = 20


class ReportOut(BaseModel):
    started_at: Optional[str] = None
    finished_at: Optional[str] = None
    duration_seconds: float = 0.0
    sources: int = 0
    articles_fetched: int = 0
    articles_new: int = 0
    stories_created: int = 0
    stories_published: int = 0
    stories_held: int = 0
    media_generated: int = 0
    errors: List[str] = Field(default_factory=list)
