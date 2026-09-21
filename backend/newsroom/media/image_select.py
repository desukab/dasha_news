"""Choosing the photograph a reader sees.

A page offers many images and most of them are furniture: the outlet's logo,
its watermark, a favicon, an ad slot, a sharing button. The first image in the
HTML is usually the logo, and picking the first one is what put a publisher's
watermark on the front page (spec §42: compare the available images and select
the most relevant one, and §14: never ship a logo as the story's picture).

This module is the judgement layer. It has no database and no network: the
extractor hands it every image a page offered, it throws out the furniture, and
it ranks what is left by how much of the story the image actually shows. The
caller takes one answer or none.
"""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass
from typing import Iterable, List, Optional
from urllib.parse import urljoin, urlparse

logger = logging.getLogger(__name__)

# Where a candidate came from, in the page's own order of trustworthiness: an
# Open Graph image is what the outlet chose for its own preview card, a body
# <img> is whatever the CMS happened to insert.
OG_PROPERTIES = ("og:image", "og:image:secure_url", "twitter:image")

_MAX_CANDIDATES = 24

# URL furniture. Matched against the URL with every separator normalised to a
# single "-" (see [_chrome_hit]), so a path segment of "watermarklogo.png" is
# caught as readily as a host of "logos.example.com". Tokens are anchored at a
# segment start. [_CHROME_PREFIX] matches any continuation of the token —
# "watermark" must catch "watermarklogo" — while [_CHROME_EXACT] must fill the
# whole segment, which is what stops "-download-image.jpg" from matching "-ad".
_CHROME_PREFIX = re.compile(
    r"-(?:logo|watermark|favicon|sprite|banner|placeholder|spacer|advert|"
    r"advertising|subscribe|newsletter|button|badge|emoji|sticker|avatar|"
    r"default|spinner|loader|scorecard|analytics|beacon|tracking|sidebar|"
    r"promo|sponsor|cookie|icon|arrow|header|footer|social|comment|related|"
    r"noimage|nophoto|nopicture)",
    re.I,
)
_CHROME_EXACT = re.compile(
    r"-(?:ad|rss|btn|print|blank|pixel|1x1)(?=-|$)",
    re.I,
)

# Hosts that exist to track readers or to serve a site's own chrome. An image
# on one of these is not a photograph of anything.
_CHROME_HOSTS = (
    "google-analytics.com",
    "googletagmanager.com",
    "scorecardresearch.com",
    "facebook.com/tr",
    "platform.twitter.com",
    "whatsapp.com",
    "doubleclick.net",
    "adnxs.com",
    "pubmatic.com",
    "quantserve.com",
    "comscore.com",
    "clarity.ms",
)

_IMAGE_SUFFIX = re.compile(r"\.(jpe?g|png|webp|avif|gif|tiff?|bmp|svg)(\?|$)", re.I)
_NOT_AN_IMAGE = re.compile(r"\.(html?|php|aspx?|jsp|js|css|pdf|docx?|mp[34])(\?|$)", re.I)

# Loopback and RFC 1918 space: the publisher naming its own machine, which a
# phone cannot reach. The newsroom's own media is a relative path served from
# the API origin and never arrives here as a candidate.
_PRIVATE_HOST = re.compile(
    r"^(?:localhost|127\.|10\.|192\.168\.|172\.(?:1[6-9]|2\d|3[01])\.|"
    r"0\.0\.0\.0|\[?::1\]?)",
    re.I,
)

_MIN_EDGE = 320
_MIN_AREA = _MIN_EDGE * _MIN_EDGE


@dataclass(frozen=True)
class ImageCandidate:
    """One image a page offered, with whatever the page said about it."""

    url: str
    # og:image, twitter:image, figure or body — the page's own ranking of how
    # important this image is to the article.
    origin: str = "body"
    width: Optional[int] = None
    height: Optional[int] = None
    alt: str = ""


def collect_image_candidates(*soups, base_url: str = "") -> List[ImageCandidate]:
    """Every image the page offered, best first, duplicates collapsed.

    Multiple soups may be given: the raw page is the only place an Open Graph
    image lives — the sanitiser strips ``<head>`` meta tags, which is correct
    for rendering but would cost the newsroom the outlet's own chosen preview
    image — while the sanitised page is the only place a trusted ``<img>`` set
    exists. Candidates are taken in the order the soups are given.

    Relative URLs are resolved against [base_url] — the page's own canonical
    URL — because a bare ``/wp-content/...`` path is only meaningful on the
    server that served it.
    """
    found: List[ImageCandidate] = []
    seen = set()

    def add(raw: Optional[str], origin: str, *,
            width: Optional[int] = None, height: Optional[int] = None,
            alt: str = "") -> None:
        if not raw or not raw.strip():
            return
        resolved = resolve_url(raw.strip(), base_url)
        if not resolved or resolved in seen:
            return
        seen.add(resolved)
        found.append(ImageCandidate(
            url=resolved, origin=origin, width=width, height=height,
            alt=(alt or "").strip()[:300],
        ))

    for soup in soups:
        if soup is None:
            continue
        for prop in OG_PROPERTIES:
            tag = soup.find("meta", property=prop) or soup.find("meta", attrs={"name": prop})
            if tag:
                add(tag.get("content"), "og:image")

        # A <figure> is the article's own illustration; its caption is the
        # closest thing to a description of the image that the page provides.
        for figure in soup.find_all("figure"):
            img = figure.find("img")
            if not img:
                continue
            caption = figure.find("figcaption")
            add(img.get("src") or img.get("data-src"), "figure",
                width=_as_int(img.get("width")), height=_as_int(img.get("height")),
                alt=caption.get_text(" ", strip=True) if caption else (img.get("alt") or ""))

        for img in soup.find_all("img"):
            add(img.get("src") or img.get("data-src"), "body",
                width=_as_int(img.get("width")), height=_as_int(img.get("height")),
                alt=img.get("alt") or "")

    return found[:_MAX_CANDIDATES]


def resolve_url(raw: str, base_url: str) -> Optional[str]:
    """Absolute-ise [raw], or ``None`` when no origin can be inferred."""
    try:
        joined = urljoin(base_url, raw) if base_url else raw
    except ValueError:
        return None
    parsed = urlparse(joined)
    if not parsed.scheme or not parsed.netloc:
        return None
    if parsed.scheme.lower() not in ("http", "https"):
        return None
    return joined


def is_usable(url: Optional[str], base_url: str = "") -> bool:
    """True when [url] can plausibly be a photograph of something.

    The negative tests matter more than the positive ones: a rejected logo is a
    guaranteed improvement, while an over-eager accept puts furniture back on the
    front page.
    """
    if not url or not url.strip():
        return False
    resolved = resolve_url(url.strip(), base_url or url)
    if not resolved:
        return False
    parsed = urlparse(resolved)
    host = (parsed.hostname or "").lower()
    if _PRIVATE_HOST.match(host):
        return False
    if any(part in host for part in _CHROME_HOSTS):
        return False
    if _NOT_AN_IMAGE.search(resolved):
        return False
    if _chrome_hit(resolved):
        return False
    return True


def _chrome_hit(url: str) -> bool:
    """[url] with separators collapsed, so a furniture token can only ever
    match at the edge of a path segment."""
    normalised = re.sub(r"[^a-z0-9]+", "-", url.lower())
    return bool(_CHROME_PREFIX.search(normalised) or _CHROME_EXACT.search(normalised))


_ORIGIN_WEIGHT = {"og:image": 1.0, "twitter:image": 0.9, "figure": 0.8, "body": 0.6}
_STOP = re.compile(r"^[0-9\W_]+$")


def absolutise(candidates: Iterable[ImageCandidate], base_url: str = "") -> List[ImageCandidate]:
    """Candidates with every URL made absolute against [base_url].

    A page's own declaration can be a bare ``/wp-content/...`` path, which
    [is_usable] accepts during scoring — it resolves internally — but the
    surviving candidate is handed to the reader, and a relative path on the
    reader's wire resolves against the newsroom, not the outlet. Resolving
    here is what keeps the chosen photograph pointing at the file (spec §42).
    URLs that no origin can be inferred for are dropped.
    """
    out: List[ImageCandidate] = []
    for candidate in candidates:
        resolved = resolve_url(candidate.url, base_url or candidate.url)
        if not resolved:
            continue
        out.append(candidate if resolved == candidate.url
                   else ImageCandidate(url=resolved, origin=candidate.origin,
                                       width=candidate.width, height=candidate.height,
                                       alt=candidate.alt))
    return out


def select_primary(candidates: Iterable[ImageCandidate], *, headline: str = "",
                   body: str = "", base_url: str = "") -> Optional[ImageCandidate]:
    """The best photograph for a story, or ``None`` when a page offered none.

    Ranking combines three signals: how prominently the page itself presented
    the image, how large it is, and how closely its own description matches the
    story's words. The third is what separates two equally large images — one
    of the chief minister, one of the outlet's building.
    """
    keywords = _keywords(f"{headline} {body[:400]}")
    best: Optional[ImageCandidate] = None
    best_score = 0.0
    for candidate in candidates:
        if not is_usable(candidate.url, base_url):
            continue
        score = _ORIGIN_WEIGHT.get(candidate.origin, 0.6)
        score += _area_score(candidate)
        score += _proximity(candidate, keywords)
        if score > best_score:
            best, best_score = candidate, score
    if best is None:
        return None
    logger.debug("primary image %s (%.2f) for %s", best.url, best_score,
                 (headline or "")[:60])
    return best


def _area_score(candidate: ImageCandidate) -> float:
    """Size as a fraction of the minimum useful photograph."""
    if not candidate.width or not candidate.height:
        # Unknown size costs nothing — the page simply did not say — but it
        # cannot outrank an image that did declare usable dimensions.
        return 0.0
    if candidate.width < 160 or candidate.height < 90:
        return -0.5
    area = candidate.width * candidate.height
    return min(0.6, area / _MIN_AREA) - 0.1


def _proximity(candidate: ImageCandidate, keywords: set) -> float:
    """How much of the image's own description appears in the story."""
    if not keywords:
        return 0.0
    haystack = f"{candidate.alt} {_slug_words(candidate.url)}"
    words = _keywords(haystack)
    if not words:
        return 0.0
    overlap = len(words & keywords)
    # Coverage, not a raw count: a four-word caption that matches three of them
    # is a better signal than a twelve-word one that matches four.
    return min(0.8, 0.25 * overlap / max(1.0, len(words) / 3.0))


_PATH_WORDS = re.compile(r"[A-Za-z0-9ఀ-౿]+")


def _slug_words(url: str) -> str:
    """The descriptive words in a URL's path, which often name the subject."""
    parsed = urlparse(url)
    return " ".join(
        part for part in re.split(r"[-_/]+", parsed.path)
        if part and not _STOP.match(part)
        and not _IMAGE_SUFFIX.match(f".{part}")
    )


def _keywords(text: str) -> set:
    """The content words of [text], lowercased, in both scripts it may carry."""
    return {
        word.lower()
        for word in _PATH_WORDS.findall(text or "")
        if len(word) > 2 and not _STOP.match(word)
    }


def _as_int(raw: Optional[str]) -> Optional[int]:
    if raw is None:
        return None
    try:
        value = int(re.sub(r"\D", "", str(raw)) or 0)
    except (TypeError, ValueError):
        return None
    return value or None


# ---------------------------------------------------------------------------
# Storage
# ---------------------------------------------------------------------------

_RECORD_KEYS = ("url", "origin", "w", "h", "alt")


def to_records(candidates: Iterable[ImageCandidate]) -> List[dict]:
    """Candidates as plain records, for the column that carries them to the
    stage that compares a whole cluster's photographs."""
    out: List[dict] = []
    seen = set()
    for candidate in candidates:
        if not candidate.url or candidate.url in seen:
            continue
        seen.add(candidate.url)
        out.append({
            "url": candidate.url,
            "origin": candidate.origin,
            "w": candidate.width,
            "h": candidate.height,
            "alt": candidate.alt,
        })
        if len(out) >= _MAX_CANDIDATES:
            break
    return out


def from_records(records: Optional[Iterable[dict]]) -> List[ImageCandidate]:
    """The inverse of [to_records], tolerant of a row written by an older or a
    newer release: unknown keys are ignored, a malformed one is dropped rather
    than costing the story its images."""
    if not records:
        return []
    out: List[ImageCandidate] = []
    for record in records:
        try:
            if not isinstance(record, dict) or not record.get("url"):
                continue
            out.append(ImageCandidate(
                url=str(record["url"])[:1000],
                origin=str(record.get("origin") or "body")[:40],
                width=_as_int(record.get("w")) if record.get("w") else None,
                height=_as_int(record.get("h")) if record.get("h") else None,
                alt=str(record.get("alt") or "")[:300],
            ))
        except (TypeError, ValueError, AttributeError):
            continue
    return out
