"""Similarity primitives used by the Deduplicator and Story Clusterer.

Everything here is deterministic and dependency-free:

* `simhash`        - 64-bit near-duplicate fingerprint (Charikar's algorithm).
* `hamming64`      - bit-distance between two fingerprints.
* `jaccard`        - set overlap for token-based comparison.
* `cosine_of_bags` - vector cosine over token-frequency bags.

The Telugu-script vs. Tenglish-script problem is handled by hashing *character
n-grams* rather than words: two publishers writing "హైదరాబాద్" and
"Hyderabad" still share enough shape signal to cluster when combined with
title overlap and temporal proximity.
"""

from __future__ import annotations

import hashlib
import struct
from collections import Counter
from typing import Dict, Iterable, List, Optional, Sequence

from newsroom.nlp.telugu import char_ngrams, content_tokens

HASH_BITS = 64

# Empirically reasonable: a simhash distance under 4 on 64 bits almost always
# means the same story in slightly different wording; 4-10 is "same topic".
NEAR_DUPLICATE_DISTANCE = 4
SAME_STORY_DISTANCE = 10


def _stable_hash(token: str) -> int:
    digest = hashlib.blake2b(token.encode("utf-8", "ignore"), digest_size=8).digest()
    return struct.unpack(">Q", digest)[0]


def simhash(text: Optional[str], ngram: int = 4) -> str:
    """64-bit Charikar simhash of `text`, returned as lowercase hex."""
    features = _feature_weights(text, ngram)
    if not features:
        return "0" * 16

    vector = [0] * HASH_BITS
    for feature, weight in features.items():
        h = _stable_hash(feature)
        for bit in range(HASH_BITS):
            if h >> bit & 1:
                vector[bit] += weight
            else:
                vector[bit] -= weight

    fingerprint = 0
    threshold = sum(features.values()) / len(features) * 0  # 0: use sign test
    for bit, value in enumerate(vector):
        if value > threshold:
            fingerprint |= 1 << bit
    return f"{fingerprint:016x}"


def _feature_weights(text: Optional[str], ngram: int) -> Dict[str, float]:
    """Weighted features: word tokens count double, n-grams single."""
    weights: Dict[str, float] = {}
    for token in content_tokens(text, min_len=3):
        weights[f"w:{token}"] = weights.get(f"w:{token}", 0.0) + 2.0
    for gram in char_ngrams(text, ngram):
        key = f"g:{gram}"
        weights[key] = weights.get(key, 0.0) + 1.0
    return weights


def hamming64(a: str, b: str) -> int:
    """Bit distance between two hex simhashes."""
    try:
        ia = int(a, 16)
        ib = int(b, 16)
    except (TypeError, ValueError):
        return HASH_BITS
    return bin(ia ^ ib).count("1")


def jaccard(left: Iterable[str], right: Iterable[str]) -> float:
    set_a = set(left)
    set_b = set(right)
    if not set_a or not set_b:
        return 0.0
    intersection = len(set_a & set_b)
    union = len(set_a | set_b)
    return intersection / union if union else 0.0


def cosine_of_bags(left: Sequence[str], right: Sequence[str]) -> float:
    bag_a = Counter(left)
    bag_b = Counter(right)
    if not bag_a or not bag_b:
        return 0.0
    dot = sum(count * bag_b[token] for token, count in bag_a.items())
    norm_a = sum(count * count for count in bag_a.values()) ** 0.5
    norm_b = sum(count * count for count in bag_b.values()) ** 0.5
    if norm_a == 0 or norm_b == 0:
        return 0.0
    return dot / (norm_a * norm_b)


def token_overlap_score(left: Optional[str], right: Optional[str]) -> float:
    """Blended content-word similarity in [0, 1]."""
    tokens_a = content_tokens(left)
    tokens_b = content_tokens(right)
    if not tokens_a or not tokens_b:
        return 0.0
    return max(
        jaccard(set(tokens_a), set(tokens_b)),
        cosine_of_bags(tokens_a, tokens_b),
    )


def shape_similarity(left: Optional[str], right: Optional[str]) -> float:
    """Cross-script similarity using character n-gram Jaccard."""
    return jaccard(set(char_ngrams(left, 4)), set(char_ngrams(right, 4)))


def is_near_duplicate(
    left: Optional[str],
    right: Optional[str],
    *,
    left_hash: Optional[str] = None,
    right_hash: Optional[str] = None,
) -> bool:
    if left_hash and right_hash:
        if hamming64(left_hash, right_hash) <= NEAR_DUPLICATE_DISTANCE:
            return True
    return token_overlap_score(left, right) >= 0.72


def is_same_story(
    left_title: Optional[str],
    right_title: Optional[str],
    *,
    left_hash: Optional[str] = None,
    right_hash: Optional[str] = None,
    max_age_gap_hours: Optional[float] = None,
) -> bool:
    """Same-event test used by the Story Clusterer."""
    if left_hash and right_hash:
        distance = hamming64(left_hash, right_hash)
        if distance <= NEAR_DUPLICATE_DISTANCE:
            return True
    title_score = max(
        token_overlap_score(left_title, right_title),
        shape_similarity(left_title, right_title),
    )
    return title_score >= 0.42


def rank_by_similarity(
    query: str, candidates: List[str], limit: Optional[int] = None
) -> List[tuple[int, float]]:
    """Return (index, score) pairs for `candidates`, best first."""
    scored = [
        (index, max(token_overlap_score(query, candidate), shape_similarity(query, candidate)))
        for index, candidate in enumerate(candidates)
    ]
    scored.sort(key=lambda item: item[1], reverse=True)
    return scored[:limit] if limit is not None else scored
