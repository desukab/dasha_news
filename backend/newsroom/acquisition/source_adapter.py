"""The source-adapter interface.

Each news source is a different machine to talk to. Some publish RSS and mean
it; some serve clean server-rendered HTML; some build their pages in JavaScript.
An adapter is what lets the pipeline ask "what have you published?" and "what
does this article actually say?" without knowing which of those it is talking
to.

Fields are named after the editorial objects they become, not the HTML they came
from, so an adapter for an outlet with no Open Graph tags and one with nothing
but can both report the same shape.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from typing import TYPE_CHECKING, Any, Optional, Protocol, runtime_checkable

if TYPE_CHECKING:  # a protocol-level type only; the extractor is a dependency
    from newsroom.media.image_select import ImageCandidate

# Stages, recorded verbatim on every AcquisitionEvent row.
STAGE_DISCOVER = "discover"
STAGE_LIST = "list"
STAGE_EXTRACT = "extract"


@dataclass
class ListingItem:
    """One item an outlet has published, before its body is read."""

    title: str
    url: str
    guid: str
    summary: str = ""
    published_at: Optional[datetime] = None
    image_url: Optional[str] = None
    language: str = "te"
    is_breaking: bool = False
    # True when the summary is known to be partial ("read more" style), which
    # tells the pipeline the body is worth fetching rather than trusting this.
    is_partial: bool = False
    # How many fields came from a structured source (RSS element, JSON field)
    # rather than a heuristic, feeding the extraction confidence.
    structured_signals: int = 0


@dataclass
class ExtractedPage:
    """One article, normalised."""

    canonical_url: str
    title: str
    body_text: str
    published_at: Optional[datetime] = None
    author: Optional[str] = None
    section: Optional[str] = None
    lead_image_url: Optional[str] = None
    # Every photograph the page offered, best first. A single ``lead_image_url``
    # cannot tell a picture of the story from the outlet's watermark, so the
    # pipeline compares the whole set before choosing one.
    image_candidates: list["ImageCandidate"] = field(default_factory=list)
    source_metadata: dict[str, Any] = field(default_factory=dict)
    # How much of the article was actually read, in [0, 1]. See
    # ``newsroom.acquisition.confidence``: this is an acquisition score, not an
    # editorial one, and it is what separates a full-text extraction from a
    # paywalled page that fell back to its RSS summary.
    confidence: float = 0.0
    fetch_method: str = "httpx"
    parser_version: str = ""
    truncated: bool = False
    is_paywalled: bool = False
    structured_signals: int = 0

    @property
    def is_useful(self) -> bool:
        """Does this extraction hold enough to extract facts from?"""
        return bool(self.title and self.body_text and len(self.body_text) >= 80)


@runtime_checkable
class SourceAdapter(Protocol):
    """How the newsroom talks to one kind of news source."""

    name: str

    def discover(self, source: Any, ctx: "AcquisitionContext") -> list[ListingItem]:
        """List what the source has published.

        For an RSS outlet this is the feed; for a web outlet it is a listing
        page. Returns an empty list when the source has nothing new to say.
        """
        ...

    def extract(self, source: Any, url: str, ctx: "AcquisitionContext"
                ) -> ExtractedPage:
        """Read one article.

        Never raises for ordinary editorial reasons (a paywall, a dead link, a
        page the outlet has removed): the adapter reports what it could recover
        and lets the caller judge. Raises only when the fetch itself failed in a
        way the caller must see.
        """
        ...

    def failure_policy(self, source: Any) -> "FailurePolicy":
        """How hard this source wants the newsroom to try."""
        ...


# Imported here to keep the protocol self-describing without creating a cycle:
# the context module imports the adapter protocol, the protocol only names it.
from newsroom.acquisition.context import AcquisitionContext  # noqa: E402
from newsroom.acquisition.retry import FailurePolicy  # noqa: E402

__all__: list[str] = [
    "AcquisitionContext",
    "ExtractedPage",
    "FailurePolicy",
    "ListingItem",
    "STAGE_DISCOVER",
    "STAGE_EXTRACT",
    "STAGE_LIST",
    "SourceAdapter",
]
