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

from dataclasses import dataclass, field
from datetime import datetime, timedelta
from typing import Iterable, List, Optional, Sequence

from newsroom.nlp.similarity import (
    NEAR_DUPLICATE_DISTANCE,
    hamming64,
    is_near_duplicate,
    is_same_story,
    shape_similarity,
    token_overlap_score,
)
from newsroom.nlp.telugu import content_tokens

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
    return DedupeResult(is_duplicate=False)


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


def make_cluster_id(*parts: str) -> str:
    """Deterministic cluster key from the article's identifying content."""
    import hashlib
    joined = "|".join(p.strip().lower() for p in parts if p)
    return hashlib.sha256(joined.encode("utf-8")).hexdigest()[:24]
