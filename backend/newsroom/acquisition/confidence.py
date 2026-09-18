"""Extraction confidence.

Distinct from ``Story.confidence``, which scores the *editorial* case
(evidence level, corroboration, importance). This scores the *acquisition*: how
much of the article did we actually manage to read, and how much of what we
report came from a structured signal rather than a guess?

A paywalled page that silently fell back to a two-line RSS summary must not
look identical to a full-text extraction. That distinction starts here.
"""

from __future__ import annotations

from typing import Optional

# Weight of each field an extractor can resolve. The body dominates because an
# article without a body cannot yield facts; the rest are corroborating detail.
_WEIGHTS = {
    "canonical_url": 0.15,
    "title": 0.20,
    "published_at": 0.15,
    "author": 0.10,
    "lead_image": 0.10,
}
_BODY_WEIGHT = 0.30
# A body this long is treated as complete; shorter bodies score proportionally.
_FULL_BODY_CHARS = 2000

# Penalties applied to an extraction that did succeed but is suspect.
_PAYWALL_PENALTY = 0.40
_TRUNCATION_PENALTY = 0.10
_SHORT_BODY_PENALTY = 0.20


def extraction_confidence(
    *,
    canonical_url: Optional[str],
    title: Optional[str],
    published_at: Optional[object],
    author: Optional[str],
    lead_image_url: Optional[str],
    body_text: Optional[str],
    is_paywalled: bool = False,
    truncated: bool = False,
    structured_signals: int = 0,
) -> float:
    """Score an extraction in [0, 1] from the fields it actually resolved.

    ``structured_signals`` counts fields that came from a machine-readable
    source (an RSS element, an Open Graph tag) rather than a heuristic guess,
    and gives such extractions a small bonus.
    """
    score = 0.0
    resolved = {
        "canonical_url": bool(canonical_url),
        "title": bool(title and title.strip()),
        "published_at": published_at is not None,
        "author": bool(author and author.strip()),
        "lead_image": bool(lead_image_url),
    }
    for field, present in resolved.items():
        if present:
            score += _WEIGHTS[field]

    body = body_text or ""
    score += _BODY_WEIGHT * min(1.0, len(body) / _FULL_BODY_CHARS)

    if is_paywalled:
        score -= _PAYWALL_PENALTY
    if truncated:
        score -= _TRUNCATION_PENALTY
    # A body that resolved but is too short to hold a fact is worth less than
    # the raw length score suggests.
    if 0 < len(body) < _MIN_USEFUL_BODY:
        score -= _SHORT_BODY_PENALTY

    if structured_signals:
        score += 0.05 * min(structured_signals, 3)

    return round(max(0.0, min(1.0, score)), 3)


_MIN_USEFUL_BODY = 200
