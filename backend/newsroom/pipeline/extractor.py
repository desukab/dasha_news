"""Extractor: raw HTML -> clean, readable text + structured fields.

Uses a readability-style heuristic (no external readability dependency, which
keeps the stack free). Output is always sanitised before parsing and never
re-served verbatim: the newsroom publishes its own summaries.
"""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass, field
from typing import List, Optional

from bs4 import BeautifulSoup

from newsroom.media.image_select import ImageCandidate, collect_image_candidates
from newsroom.nlp.language import detect_language
from newsroom.nlp.telugu import normalize_text, word_count
from newsroom.pipeline.fetch import FetchError, fetch
from newsroom.security.guards import sanitize_html

logger = logging.getLogger(__name__)

_NEGATIVE = re.compile(
    r"comment|share|advert|sponsor|newsletter|subscribe|cookie|footer|"
    r"header|sidebar|social|related|taboola|outbrain|popup|modal|nav\b|"
    r"breadcrumb|pagination|disclaimer|వ్యాఖ్యలు|ప్రకటన", re.I)
_POSITIVE = re.compile(
    r"article|story|content|post|entry|main|body|కథనం|వార్త|ప్రధాన", re.I)
_BYLINE = re.compile(
    r"^\s*(by|రచన[:\s]|రచయిత[:\s])\s*[:\-]?\s*", re.I)
_MIN_CONTENT_CHARS = 200


@dataclass
class ExtractedArticle:
    url: str
    title: str
    text: str
    author: Optional[str]
    image_url: Optional[str]
    language: str
    is_paywalled: bool
    truncated: bool
    # Every image the page offered, best first, relative URLs already resolved
    # against the page's own origin. The single ``image_url`` is the first of
    # these; the list is what lets the pipeline compare a whole cluster's
    # photographs and pick a picture of the story rather than of the outlet.
    image_candidates: List["ImageCandidate"] = field(default_factory=list)


def extract_from_html(html: str, url: str = "") -> ExtractedArticle:
    """Extract the readable article from already-fetched HTML."""
    safe = sanitize_html(html)
    soup = BeautifulSoup(safe, "lxml")
    for tag in soup(["script", "style", "noscript"]):
        tag.decompose()

    container = _pick_main_content(soup)
    paragraphs = _paragraphs(container)
    text = "\n".join(paragraphs)
    truncated = False
    if len(text) > 40_000:
        text = text[:40_000]
        truncated = True

    title = _title(soup)
    # The raw page is read for the outlet's declared preview images: the
    # sanitiser strips <head> meta tags, which is right for rendering but would
    # leave only the page's <img> set — whose first member is usually a logo.
    # Only URLs are read from the raw page; it is never parsed for content.
    raw_soup = BeautifulSoup(html, "lxml")
    image_candidates = collect_image_candidates(raw_soup, soup, base_url=url)
    author = _author(soup)

    text = normalize_text(text)
    # Under this, what we picked is chrome rather than copy: a boilerplate page,
    # a photo caption, a paywall interstitial. Reporting it as an article body
    # would overwrite the feed summary with junk, so it is dropped and the
    # caller falls back to whatever the feed actually said.
    if len(text.strip()) < _MIN_CONTENT_CHARS:
        text = ""

    return ExtractedArticle(
        url=url,
        title=title,
        text=text,
        author=author,
        image_url=image_candidates[0].url if image_candidates else None,
        language=detect_language(title + " " + text).value,
        is_paywalled=_is_paywalled(soup),
        truncated=truncated,
        image_candidates=image_candidates,
    )


def extract_from_url(url: str) -> ExtractedArticle:
    """Fetch and extract in one step, for background enrichment."""
    try:
        response = fetch(url)
    except (FetchError, Exception) as exc:  # noqa: BLE001
        raise ExtractionError(f"fetch failed for {url}: {exc}") from exc
    if response.status != 200 or not response.body:
        raise ExtractionError(f"HTTP {response.status} for {url}")
    return extract_from_html(response.body.decode("utf-8", "ignore"), url=response.final_url)


class ExtractionError(RuntimeError):
    pass


def _pick_main_content(soup: BeautifulSoup) -> BeautifulSoup:
    best = soup.body or soup
    best_score = -1.0
    candidates = best.find_all(["article", "main", "section", "div", "td"])
    for node in candidates:
        if not node.text:
            continue
        cls = " ".join(node.get("class", []) or [])
        score = len(node.text)
        if _NEGATIVE.search(cls + " " + (node.get("id") or "")):
            score *= 0.15
        if _POSITIVE.search(cls + " " + (node.get("id") or "")):
            score *= 1.6
        if node.name == "article":
            score *= 1.5
        if score > best_score:
            best_score = score
            best = node
    return best


def _paragraphs(node) -> List[str]:
    out: List[str] = []
    for paragraph in node.find_all(["p", "li", "blockquote"]):
        line = normalize_text(paragraph.get_text(" ", strip=True))
        if len(line) >= 60:
            out.append(line)
    return out


def _title(soup: BeautifulSoup) -> str:
    og = soup.find("meta", property="og:title")
    if og and og.get("content"):
        return og["content"].strip()
    h1 = soup.find(["h1", "h2"])
    if h1 and h1.get_text(strip=True):
        return h1.get_text(strip=True)
    return (soup.title.get_text(strip=True) if soup.title else "") or ""


_AUTHOR_PATTERNS = ("author", "byline", "రచయిత", "రచన")


def _author(soup: BeautifulSoup) -> Optional[str]:
    for attribute in ("name", "property"):
        tag = soup.find("meta", attrs={attribute: _AUTHOR_PATTERNS})
        if tag and tag.get("content"):
            return _BYLINE.sub("", tag["content"].strip())[:200]
    tag = soup.find(attrs={"class": re.compile("|".join(_AUTHOR_PATTERNS), re.I)})
    if tag:
        text = normalize_text(tag.get_text(" ", strip=True))
        if 2 < len(text) < 120 and word_count(text) <= 12:
            return _BYLINE.sub("", text)
    return None


_PAYWALL_MARKERS = re.compile(
    r"paywall|subscribe to (read|continue)|sign in to (read|continue)|"
    r"చందాదారులు మాత్రమే|ప్రీమియం", re.I)


def _is_paywalled(soup: BeautifulSoup) -> bool:
    return bool(_PAYWALL_MARKERS.search(soup.get_text(" ", strip=True)[:5000]))
