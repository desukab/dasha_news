"""Web (HTML) adapter: reads an outlet that has no usable feed.

Two jobs, both generic rather than per-site, which is what keeps this
maintainable across many outlets:

* ``discover`` finds article links on a listing page by scoring anchor text and
  URL shape rather than by hardcoded selectors, so an outlet redesign does not
  silently stop the news.
* ``extract`` turns one article page into an :class:`ExtractedPage`, reusing the
  newsroom's existing readability-style extractor and security sanitisation.

Per-site overrides live in a selector registry when an outlet genuinely needs
them — added later, per outlet, only where the generic path demonstrably fails.
"""

from __future__ import annotations

import logging
import re
from datetime import datetime
from typing import Any, Optional
from urllib.parse import urljoin

from newsroom.acquisition.canonical import canonicalise_url
from newsroom.acquisition.confidence import extraction_confidence
from newsroom.acquisition.context import AcquisitionContext
from newsroom.acquisition.observability import PARSER_VERSION
from newsroom.acquisition.retry import (
    FailurePolicy,
    PermanentFetchError,
    TransientFetchError,
)
from newsroom.acquisition.source_adapter import (
    STAGE_EXTRACT,
    STAGE_LIST,
    ExtractedPage,
    ListingItem,
)
from newsroom.nlp.language import detect_language
from newsroom.nlp.telugu import normalize_text
from newsroom.pipeline.fetch import FetchError

logger = logging.getLogger(__name__)

_PAGE_MAX_BYTES = 8 * 1024 * 1024

# An anchor whose text is shorter than this is navigation, not a headline.
_MIN_LINK_TEXT = 28
_MAX_LISTING_ITEMS = 40

# Path patterns that signal a real article rather than a category or tag page.
_ARTICLE_PATH_HINTS = re.compile(
    r"/(article|story|news|post|entry|వార్త|కథనం)[/-]|"
    r"-\d{4,}/|/\d{4}/\d{1,2}/|/\d{6,}|/p-?\d{4,}",
    re.I,
)
# Paths that look article-ish but are not.
_NON_ARTICLE_PATHS = re.compile(
    r"/(tag|tags|category|categories|author|topic|search|about|contact|"
    r"subscribe|login|register|page|amp$|print|share|rss|feed)/?$|"
    r"\.(jpg|jpeg|png|gif|webp|svg|pdf|mp4|mp3)$",
    re.I,
)


class HtmlAdapter:
    """Reads an outlet by fetching its pages directly."""

    name = "web"

    def discover(self, source: Any, ctx: AcquisitionContext) -> list[ListingItem]:
        from bs4 import BeautifulSoup

        listing_url = getattr(source, "feed_url", None) or getattr(source, "site_url", "")
        if not listing_url:
            return []

        try:
            status, raw = ctx.fetch_text(listing_url, stage=STAGE_LIST,
                                         max_bytes=_PAGE_MAX_BYTES)
        except PermissionError:
            return []
        if status != 200 or not raw:
            return []

        soup = BeautifulSoup(raw, "lxml")
        base = getattr(source, "site_url", "") or listing_url
        declared = getattr(source, "language", None) or "te"

        seen: set[str] = set()
        items: list[ListingItem] = []
        for anchor in soup.find_all("a"):
            href = anchor.get("href")
            if not href:
                continue
            title = normalize_text(anchor.get_text(" ", strip=True))
            if len(title) < _MIN_LINK_TEXT:
                continue
            url = urljoin(base, href.strip())
            if not url.startswith(("http://", "https://")):
                continue
            key = canonicalise_url(url, base=base)
            if not key or key in seen:
                continue
            if _NON_ARTICLE_PATHS.search(urlsplit_path(url)):
                continue
            seen.add(key)
            items.append(ListingItem(
                title=title[:600],
                url=url,
                guid=key,
                summary="",
                language=declared,
                structured_signals=0,
            ))
            if len(items) >= _MAX_LISTING_ITEMS:
                break
        return items

    def extract(self, source: Any, url: str, ctx: AcquisitionContext
                ) -> ExtractedPage:
        from newsroom.pipeline.extractor import (
            ExtractionError,
            extract_from_html,
        )

        try:
            result = ctx.fetch(url, stage=STAGE_EXTRACT, max_bytes=_PAGE_MAX_BYTES)
        except PermissionError as exc:
            raise PermanentFetchError(str(exc)) from exc
        except FetchError as exc:
            raise TransientFetchError(f"fetch failed for {url}: {exc}") from exc

        canonical = canonicalise_url(result.final_url or url, base=url)
        if result.status != 200 or not result.body:
            return _empty(url, canonical, fetch_method=ctx, status=result.status)

        try:
            extracted = extract_from_html(result.text, url=result.final_url or url)
        except Exception as exc:  # noqa: BLE001 - a malformed page is editorial, not fatal
            logger.info("extraction failed for %s: %s", url, exc)
            return _empty(url, canonical, fetch_method=ctx, status=result.status)

        confidence = extraction_confidence(
            canonical_url=canonical,
            title=extracted.title,
            published_at=None,
            author=extracted.author,
            lead_image_url=extracted.image_url,
            body_text=extracted.text,
            is_paywalled=extracted.is_paywalled,
            truncated=extracted.truncated,
            structured_signals=_structured_meta_count(result.text),
        )
        ctx._record(url=url, stage=STAGE_EXTRACT, status=result.status,
                    ok=bool(extracted.text), retries=0, confidence=confidence)
        return ExtractedPage(
            canonical_url=canonical or url,
            title=extracted.title,
            body_text=extracted.text,
            published_at=_published_at(result.text),
            author=extracted.author,
            section=getattr(source, "default_section", None),
            lead_image_url=extracted.image_url,
            source_metadata={
                "language": extracted.language,
                "is_paywalled": extracted.is_paywalled,
                "truncated": extracted.truncated,
            },
            confidence=confidence,
            fetch_method=getattr(ctx.backend, "name", "httpx"),
            parser_version=PARSER_VERSION,
            truncated=extracted.truncated,
            is_paywalled=extracted.is_paywalled,
        )

    def failure_policy(self, source: Any) -> FailurePolicy:
        return FailurePolicy.conservative()


def _empty(url: str, canonical: str, *, fetch_method: Any,
           status: int) -> ExtractedPage:
    return ExtractedPage(
        canonical_url=canonical or url,
        title="",
        body_text="",
        fetch_method=getattr(fetch_method.backend, "name", "httpx"),
        parser_version=PARSER_VERSION,
        source_metadata={"http_status": status},
    )


_META_PUBLISHED = (
    ("property", "og:published_time"),
    ("property", "article:published_time"),
    ("name", "datepublished"),
    ("name", "pubdate"),
    ("name", "date"),
)


def _published_at(html: str) -> Optional[datetime]:
    """Publication time from structured metadata, if the page declares one.

    Only machine-readable forms are trusted; guessing a date from prose is how
    wrong timestamps enter a corrections-heavy system.
    """
    from bs4 import BeautifulSoup

    try:
        soup = BeautifulSoup(html, "lxml")
    except Exception:  # noqa: BLE001
        return None
    for attribute, key in _META_PUBLISHED:
        tag = soup.find("meta", attrs={attribute: key})
        if tag and tag.get("content"):
            moment = _parse_moment(tag["content"])
            if moment is not None:
                return moment
    time_tag = soup.find("time")
    if time_tag:
        moment = _parse_moment(time_tag.get("datetime") or time_tag.get_text(strip=True))
        if moment is not None:
            return moment
    return None


def _parse_moment(raw: str) -> Optional[datetime]:
    from datetime import timezone

    text = (raw or "").strip()
    if not text:
        return None
    for parser in (_parse_iso, _parse_rfc822):
        try:
            moment = parser(text)
        except (ValueError, TypeError, OverflowError):
            moment = None
        if moment is not None:
            if moment.year < 2000 or moment.year > 2100:
                return None
            return moment if moment.tzinfo else moment.replace(tzinfo=timezone.utc)
    return None


def _parse_iso(text: str) -> Optional[datetime]:
    from datetime import datetime

    return datetime.fromisoformat(text[:26].replace("Z", "+00:00"))


def _parse_rfc822(text: str) -> Optional[datetime]:
    from email.utils import parsedate_to_datetime

    return parsedate_to_datetime(text)


def _structured_meta_count(html: str) -> int:
    """Structured signals present in the page, for the confidence score."""
    from bs4 import BeautifulSoup

    try:
        soup = BeautifulSoup(html, "lxml")
    except Exception:  # noqa: BLE001
        return 0
    count = 0
    if soup.find("meta", property="og:title"):
        count += 1
    if soup.find("meta", attrs={"name": "author"}) or soup.find("meta", property="article:author"):
        count += 1
    if soup.find("time") or soup.find("meta", property="article:published_time"):
        count += 1
    return count


def urlsplit_path(url: str) -> str:
    from urllib.parse import urlsplit

    try:
        return urlsplit(url).path or ""
    except ValueError:
        return ""
