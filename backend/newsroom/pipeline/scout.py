"""Scout: source discovery and RSS/Atom ingestion.

The Scout never copies an article. It captures the *index* of what an outlet
has published (title, link, timestamps) plus the raw HTML for extraction, and
records exactly when it was seen. Everything after this stage works from that
captured record, which is what makes deduplication, corrections and evidence
trails possible.
"""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass, field
from datetime import datetime
from typing import Dict, List, Optional

from sqlalchemy import select
from sqlalchemy.orm import Session

from newsroom.db.models import Article, Source
from newsroom.nlp.language import Language, detect_language
from newsroom.nlp.similarity import simhash
from newsroom.nlp.telugu import normalize_text, strip_dangling_vowel_signs
from newsroom.pipeline.fetch import FetchError, fetch

logger = logging.getLogger(__name__)

# Many regional outlets publish partial feeds; this is the marker that tells us
# the feed body is a summary rather than the full article.
_CONTINUED_MARKERS = re.compile(r"(read more|ఇంకా చదవండి|continue reading|…\s*$)", re.I)


@dataclass
class FeedItem:
    title: str
    url: str
    guid: str
    summary: str
    published_at: Optional[datetime]
    image_url: Optional[str] = None
    language: str = "te"
    is_breaking: bool = False
    raw_html: Optional[str] = None


@dataclass
class ScoutReport:
    source_guid: str
    fetched: int = 0
    new: int = 0
    duplicates: int = 0
    errors: List[str] = field(default_factory=list)


def discover_feeds(site_url: str) -> List[str]:
    """Find the feed(s) a site advertises.

    Looks for ``<link rel="alternate" type="application/rss+xml">`` /
    ``application/atom+xml`` in the homepage, then falls back to the common
    Indian-outlet feed paths. Deliberately small: discovery is a hint, not a
    crawl, and it is bounded to one page per site.
    """
    from bs4 import BeautifulSoup

    candidate_urls = [site_url.rstrip("/") + "/"]
    for path in ("/feed", "/rss", "/rss.xml", "/feeds", "/index.xml",
                 "/rss/latest", "/rss/news"):
        candidate_urls.append(site_url.rstrip("/") + path)

    from newsroom.security.guards import is_safe_url
    for url in candidate_urls:
        if not is_safe_url(url):
            continue
        try:
            response = fetch(url)
        except (FetchError, Exception):  # noqa: BLE001 - move to the next candidate
            continue
        if response.status != 200 or not response.body:
            continue
        text = response.body.decode("utf-8", "ignore")
        if "<rss" in text or "<feed" in text or "<channel" in text:
            return [response.final_url]
        soup = BeautifulSoup(text, "lxml")
        links = [
            link.get("href")
            for link in soup.find_all("link")
            if (link.get("type") or "") in ("application/rss+xml", "application/atom+xml")
        ]
        resolved = [l for l in (links or []) if l]
        if resolved:
            return [resolved[0]]
    return []


def parse_feed(raw: str, base_url: str = "", *,
               language: str = "te") -> List[FeedItem]:
    """Parse RSS 2.0 / Atom into normalised feed items.

    ``language`` comes from the source, which is the one place that actually
    knows. Hard-coding it here used to label every English-language feed
    Telugu.
    """
    import feedparser

    parsed = feedparser.parse(raw)
    items: List[FeedItem] = []
    for entry in parsed.entries:
        title = _clean_text(entry.get("title"))
        url = _first_link(entry, base_url)
        if not title or not url:
            continue
        summary = _clean_text(_entry_summary(entry))
        published = _entry_published(entry)
        image = _entry_image(entry)
        is_breaking = _is_breaking_entry(entry)
        items.append(FeedItem(
            title=title,
            url=url,
            guid=str(entry.get("id") or url),
            summary=summary,
            published_at=published,
            image_url=image,
            language=language,
            is_breaking=is_breaking,
        ))
    return items


def _clean_text(text: Optional[str]) -> str:
    text = normalize_text(text)
    return strip_dangling_vowel_signs(text)


def _first_link(entry, base_url: str) -> str:
    link = entry.get("link")
    if not link:
        for alternate in entry.get("links", []):
            if alternate.get("rel") == "alternate" and alternate.get("href"):
                link = alternate["href"]
                break
    if not link:
        return ""
    if not link.startswith("http"):
        from urllib.parse import urljoin
        link = urljoin(base_url, link)
    return link


def _entry_summary(entry) -> str:
    for key in ("summary", "description", "content"):
        value = entry.get(key)
        if isinstance(value, list):
            value = " ".join(part.get("value", "") for part in value if isinstance(part, dict))
        if value:
            return str(value)
    return ""


_MONTHS = {m.lower(): index + 1 for index, month in enumerate(
    ("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"))
    for index, m in enumerate(["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                               "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"])
    for m in (month, month.upper(), month.lower())
}


def _entry_published(entry) -> Optional[datetime]:
    for key in ("published_parsed", "updated_parsed", "created_parsed"):
        parsed = entry.get(key)
        if parsed and len(parsed) >= 6:
            try:
                return datetime(*parsed[:6])
            except (TypeError, ValueError):
                continue
    raw = entry.get("published") or entry.get("updated")
    if isinstance(raw, str):
        try:
            return datetime.fromisoformat(raw[:19])
        except ValueError:
            return None
    return None


def _entry_image(entry) -> Optional[str]:
    for enclosure in entry.get("links", []) or []:
        if (enclosure.get("type") or "").startswith("image") and enclosure.get("href"):
            return enclosure["href"]
    media = entry.get("media_content") or entry.get("media_thumbnail") or []
    if media and isinstance(media, list) and media[0].get("url"):
        return media[0]["url"]
    return None


_BREAKING_MARKERS = ("breaking", "బ్రేకింగ్", "ఆకస్మికం", "అత్యవసరం", "just in", "ఫ్లాష్")


def _is_breaking_entry(entry) -> bool:
    haystack = " ".join(
        str(entry.get(key) or "")
        for key in ("title", "summary")
    ).lower()
    if any(marker in haystack for marker in _BREAKING_MARKERS):
        return True
    tags = entry.get("tags") or []
    return any("breaking" in str(tag.get("term", "")).lower() for tag in tags)


def ingest_source(session: Session, source: Source,
                  *, fetch_bodies: bool = True,
                  settings: Optional[object] = None) -> ScoutReport:
    """Fetch one source's listing and persist every item not seen before.

    The listing comes from the acquisition layer, so this function no longer
    needs to know whether the outlet publishes RSS, Atom or nothing usable at
    all. A source with no feed URL is now a *web* source rather than an error,
    provided it has a site URL to read.
    """
    report = ScoutReport(source_guid=source.guid)
    if not source.is_enabled:
        return report
    if not source.feed_url and not source.site_url:
        return report

    try:
        items = _list_source(source, session=session, settings=settings)
    except Exception as exc:  # noqa: BLE001 - one dead source must not stop the sweep
        source.fetch_error_count = (source.fetch_error_count or 0) + 1
        report.errors.append(f"{type(exc).__name__}: {exc}")
        logger.info("source %s failed: %s", source.guid, exc)
        return report

    if not items:
        source.fetch_error_count = (source.fetch_error_count or 0) + 1
        report.errors.append("no items in listing")
        return report

    source.fetch_error_count = 0
    source.last_fetched_at = datetime.utcnow()
    report.fetched = len(items)

    existing = {row[0] for row in session.execute(
        select(Article.guid).where(Article.source_id == source.id)).all()}

    for item in items:
        if item.guid in existing or item.url in existing:
            report.duplicates += 1
            continue
        article = persist_item(session, source, item, fetch_bodies=fetch_bodies)
        if article is not None:
            report.new += 1
            existing.add(article.guid)
    return report


def _list_source(source: Source, *, session: Optional[Session] = None,
                 settings: Optional[object] = None) -> List[FeedItem]:
    """Ask the acquisition layer what this outlet has published.

    RSS sources keep their existing parsing path — the feed is fetched through
    the context, which adds robots, pacing and retries, but the feed parser is
    unchanged. Web sources get the anchor-scoring listing from HtmlAdapter.
    """
    from newsroom.acquisition.registry import acquire

    declared = getattr(source, "language", None) or "te"
    handle = acquire(source, session=session, settings=settings)
    listing = handle.discover(source)

    items: List[FeedItem] = []
    for row in listing:
        # A listing item may carry its own detected language; the source's
        # declared language wins for feeds, where the whole outlet is one
        # language, and per-item detection is left to persist_item for web.
        language = declared if declared in ("te", "en", "ten") else row.language
        items.append(FeedItem(
            title=row.title,
            url=row.url,
            guid=row.guid,
            summary=row.summary,
            published_at=row.published_at,
            image_url=row.image_url,
            language=language,
            is_breaking=bool(row.is_breaking),
        ))
    return items


def persist_item(session: Session, source: Source, item: FeedItem,
                 *, fetch_bodies: bool = True) -> Optional[Article]:
    """Store one feed item as an immutable raw Article."""
    language = detect_language(item.title)
    article = Article(
        source_id=source.id,
        guid=item.guid,
        url=item.url,
        title_raw=item.title,
        title_te=item.title if language == Language.TELUGU else None,
        title_en=item.title if language == Language.ENGLISH else None,
        summary_text=item.summary or None,
        language=language.value,
        image_url=item.image_url,
        published_at=item.published_at,
        digest=simhash(item.title),
        status="new",
    )
    article.signature = _title_signature(item.title)
    session.add(article)
    session.flush()
    return article


def _title_signature(title: str) -> str:
    tokens = sorted({t for t in re.sub(r"[^a-zఀ-౿0-9]+", " ", (title or "").lower()).split()
                     if len(t) > 2})
    return " ".join(tokens[:12])
