"""Deduplicator and Story Clusterer.

Two distinct jobs, deliberately separate:

* :mod:`dedupe` removes the same article arriving twice from the *same* outlet
  (syndicated copies, feed churn, URL variants). Exact-and-near matches against
  the source's own recent items.
* :mod:`cluster` groups *different* outlets' reports of the *same event* into
  one Story. That is a higher threshold: the titles may be in different
  scripts, but the event, place and time must agree.

Both are pure functions over text, so they are deterministic and testable
without any network or model.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from functools import lru_cache
from typing import Iterable, List, Optional, Sequence, Set

from newsroom.nlp.similarity import (
    NEAR_DUPLICATE_DISTANCE,
    hamming64,
    is_near_duplicate,
    is_same_story,
    shape_similarity,
    token_overlap_score,
)
from newsroom.nlp.telugu import content_tokens

# Counts, casualty figures, amounts and other measures. Clustered only when the
# same distinctive figure turns up in two outlets' headlines.
_NUMBERS = re.compile(r"\d{1,6}")
_YEAR = re.compile(r"(?:19|20)\d{2}")

# Articles older than this are not compared, because the same headline shape
# recurs for recurring events (a holiday, a fixture, an anniversary).
DEDUPE_WINDOW_HOURS = 72
CLUSTER_WINDOW_HOURS = 120


@dataclass
class DedupeResult:
    is_duplicate: bool
    reason: Optional[str] = None
    matched_article_id: Optional[int] = None
    distance: Optional[int] = None


def dedupe_article(article, candidates: Sequence, *, window_hours: int = DEDUPE_WINDOW_HOURS
                   ) -> DedupeResult:
    """Is `article` a copy of something already ingested from this source?"""
    if not candidates:
        return DedupeResult(is_duplicate=False)
    now = article.ingested_at or datetime.utcnow()
    horizon = now - timedelta(hours=window_hours)

    for candidate in candidates:
        if candidate.id == article.id:
            continue
        if candidate.published_at and candidate.published_at < horizon:
            continue
        if article.digest and candidate.digest:
            distance = hamming64(article.digest, candidate.digest)
            if distance <= NEAR_DUPLICATE_DISTANCE:
                return DedupeResult(True, f"simhash distance {distance}", candidate.id, distance)
        if is_near_duplicate(article.title_raw, candidate.title_raw):
            return DedupeResult(True, "title near-duplicate", candidate.id)
        if _same_article_url(article, candidate):
            return DedupeResult(True, "same URL", candidate.id)
    return DedupeResult(is_duplicate=False)


def _same_article_url(article, candidate) -> bool:
    """Two URLs point at the same article.

    Canonical forms are compared when both articles have one — the acquisition
    layer records a normalised URL, which collapses tracking parameters, AMP
    variants and case differences that the raw URLs keep. Older rows (and the
    pre-acquisition tests) have no canonical URL, so the query-stripped raw URL
    remains the fallback rather than the primary test.
    """
    from newsroom.acquisition.canonical import urls_equivalent

    left = getattr(article, "canonical_url", None) or getattr(article, "url", None)
    right = getattr(candidate, "canonical_url", None) or getattr(candidate, "url", None)
    if not left or not right:
        return False
    return urls_equivalent(left, right, base=getattr(article, "url", "") or "")


@dataclass
class ClusterMatch:
    story_id: int
    cluster_id: str
    score: float


@dataclass
class ClusterCandidate:
    """A lightweight projection of a Story, for scoring without ORM loading."""
    id: int
    cluster_id: str
    title: Optional[str]
    digest: Optional[str]
    published_at: Optional[datetime]
    district: Optional[str] = None
    section: Optional[str] = None
    excerpt: Optional[str] = None


def cluster_article(article, stories: Sequence[ClusterCandidate], *,
                    window_hours: int = CLUSTER_WINDOW_HOURS) -> Optional[ClusterMatch]:
    """Find the existing Story this article belongs to, if any."""
    if not stories:
        return None
    now = article.ingested_at or datetime.utcnow()
    horizon = now - timedelta(hours=window_hours)

    best: Optional[ClusterMatch] = None
    best_score = 0.0

    for story in stories:
        if story.published_at and story.published_at < horizon:
            continue
        title_score = max(
            token_overlap_score(article.title_raw, story.title),
            shape_similarity(article.title_raw, story.title),
            # A Telugu report and an English report of the same event share no
            # script at all: no tokens and almost no character n-grams. The
            # cross-script scorer falls back to the things that *are* the same
            # in either alphabet -- the place, and the numbers involved.
            _cross_script_score(article.title_raw, story.title),
            _cross_script_score(_article_text(article), story.excerpt or story.title),
        )
        hash_score = _hash_similarity(article.digest, story.digest)
        score = max(title_score, hash_score * 0.9)

        # Geographic agreement is a strong signal: two different events in
        # different districts should never merge, even with similar titles.
        article_district = getattr(article, "district", None)
        if article_district and story.district and article_district != story.district:
            score *= 0.45

        if score >= 0.42 and score > best_score:
            best_score = score
            best = ClusterMatch(story.id, story.cluster_id, score)
    return best


def _hash_similarity(a: Optional[str], b: Optional[str]) -> float:
    if not a or not b:
        return 0.0
    distance = hamming64(a, b)
    if distance == 0:
        return 1.0
    return max(0.0, 1.0 - distance / 24.0)


def _cross_script_score(left: Optional[str], right: Optional[str]) -> float:
    """Same-event evidence that survives a change of script.

    A Telugu headline and an English headline of one event share no tokens and
    almost no character n-grams, so the ordinary title scorers score them zero.
    Transliterating one side does not help either: "హైదరాబాద్" transliterates to
    "haidrabad", which is no closer to "Hyderabad" than the Telugu was.

    Two things *are* script-independent, and this function scores only them:

    * **Places.** The geo alias table already maps both scripts to one canonical
      district, so "హైదరాబాద్" and "Hyderabad" both resolve to Hyderabad.
    * **Numbers.** "12 గ్రామాలు" and "12 villages" share the digit run "12".

    Agreement on one signal alone is far too weak -- many unrelated stories
    share a district, and small counts recur -- so it scores below the cluster
    threshold. Both signals agreeing is what merges a cross-script pair.
    """
    if not left or not right:
        return 0.0
    if not _different_script(left, right):
        return 0.0

    place_agrees = _titles_share_place(left, right)
    number_agrees = bool(_shared_numbers(left, right))
    if place_agrees and number_agrees:
        return 0.55
    return 0.30 if place_agrees else 0.0


def _different_script(left: str, right: str) -> bool:
    """One side is Telugu script and the other is predominantly Latin.

    Same-script pairs keep using the token and shape scorers, which are sharper
    for them; this bridge is only for the pairs those scorers cannot see.
    """
    from newsroom.nlp.telugu import telugu_ratio

    return min(telugu_ratio(left), telugu_ratio(right)) < 0.2 < max(
        telugu_ratio(left), telugu_ratio(right))


@lru_cache(maxsize=4096)
def _title_district(title: str) -> Optional[str]:
    """The district a title names, cached: clustering compares many titles.

    ``resolve_location`` is a pure function over a static alias table, so the
    cache cannot go stale, and titles repeat heavily across a sweep.
    """
    from newsroom.domain.geo import resolve_location

    try:
        return resolve_location(title).district
    except Exception:  # noqa: BLE001 - clustering must never fail on text shape
        return None


def _titles_share_place(left: str, right: str) -> bool:
    district = _title_district(left)
    return district is not None and district == _title_district(right)


def _article_text(article) -> str:
    """Title plus whatever body the pipeline has for the article so far.

    Clustering runs before the full body fetch in the default sweep path, so
    the feed summary is what is available; it is usually enough for the place
    and number signals to land.
    """
    return " ".join(
        part for part in (getattr(article, "title_raw", None),
                          getattr(article, "body_text", None),
                          getattr(article, "summary_text", None))
        if part)


def _shared_numbers(left: str, right: str) -> Set[str]:
    """Distinctive counts and amounts present in both texts.

    Single digits and four-digit years are excluded: the former repeat across
    unrelated stories, the latter appears in almost every dateline, so neither
    says anything about whether two reports describe the same event.
    """
    def _keep(value: str) -> bool:
        return len(value) >= 2 and not _YEAR.fullmatch(value)

    return {n for n in _NUMBERS.findall(left) if _keep(n)} & {
        n for n in _NUMBERS.findall(right) if _keep(n)}


def make_cluster_id(*parts: str) -> str:
    """Deterministic cluster key from the article's identifying content."""
    import hashlib
    joined = "|".join(p.strip().lower() for p in parts if p)
    return hashlib.sha256(joined.encode("utf-8")).hexdigest()[:24]
