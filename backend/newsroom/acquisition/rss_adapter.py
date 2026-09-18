"""RSS/Atom adapter: the preferred machine interface.

An outlet that publishes a feed is telling us how it wants to be read, and this
adapter takes it at its word. It is a thin wrapper over the existing feed
parsing, moved behind the adapter interface so the pipeline no longer needs to
know that this particular source happens to be RSS.

One bug is fixed here: the feed parser used to stamp every item with
``language="te"`` regardless of the outlet, which silently mislabeled The Hindu
and Indian Express. The adapter now takes the language from the source, which is
the one place that actually knows.
"""

from __future__ import annotations

import logging
from typing import Any, Optional

from newsroom.acquisition.context import AcquisitionContext
from newsroom.acquisition.retry import FailurePolicy
from newsroom.acquisition.source_adapter import (
    STAGE_DISCOVER,
    ListingItem,
)
from newsroom.nlp.language import detect_language

logger = logging.getLogger(__name__)

_FEED_MAX_BYTES = 8 * 1024 * 1024


class RssAdapter:
    """Reads an outlet's RSS or Atom feed as a listing."""

    name = "rss"

    def discover(self, source: Any, ctx: AcquisitionContext) -> list[ListingItem]:
        from newsroom.pipeline.scout import parse_feed

        feed_url = self._feed_url(source)
        if not feed_url:
            return []

        status, raw = ctx.fetch_text(feed_url, stage=STAGE_DISCOVER,
                                     max_bytes=_FEED_MAX_BYTES)
        if status != 200 or not raw:
            return []

        declared = getattr(source, "language", None) or "te"
        items = parse_feed(raw, base_url=getattr(source, "site_url", "") or "",
                           language=declared)
        out: list[ListingItem] = []
        for item in items:
            language = item.language
            if declared not in ("te", "en", "ten"):
                language = detect_language(item.title).value
            out.append(ListingItem(
                title=item.title,
                url=item.url,
                guid=item.guid,
                summary=item.summary,
                published_at=item.published_at,
                image_url=item.image_url,
                language=language,
                is_breaking=item.is_breaking,
                structured_signals=_structured_count(item),
            ))
        return out

    def extract(self, source: Any, url: str, ctx: AcquisitionContext
                ) -> Any:
        """An RSS source has no article-body contract; extraction is the web
        adapter's job, reached via the article URL."""
        from newsroom.acquisition.html_adapter import HtmlAdapter

        return HtmlAdapter().extract(source, url, ctx)

    def failure_policy(self, source: Any) -> FailurePolicy:
        return FailurePolicy.conservative()

    def _feed_url(self, source: Any) -> Optional[str]:
        feed_url = getattr(source, "feed_url", None)
        if feed_url:
            return feed_url
        site_url = getattr(source, "site_url", None)
        if not site_url:
            return None
        from newsroom.pipeline.scout import discover_feeds

        try:
            discovered = discover_feeds(site_url)
        except Exception as exc:  # noqa: BLE001
            logger.info("feed discovery failed for %s: %s", site_url, exc)
            return None
        return discovered[0] if discovered else None


def _structured_count(item: Any) -> int:
    """How many fields came from feed elements rather than guesses."""
    count = 0
    if getattr(item, "published_at", None):
        count += 1
    if getattr(item, "image_url", None):
        count += 1
    if getattr(item, "summary", None):
        count += 1
    return count
