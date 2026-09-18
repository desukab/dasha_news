"""Importance Engine and Location Engine.

``importance``
    How prominently a story should be played. A weighted, inspectable formula --
    not a black box -- combining evidence strength, source count and quality,
    recency, breaking status, hyperlocal relevance and reader weight.
``location``
    Where a story happened, resolved to the deepest level the text supports,
    using the Telangana geographic hierarchy in :mod:`newsroom.domain.geo`.
"""

from __future__ import annotations

import logging
import math
import re
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional

from newsroom.domain.geo import GeoMatch, resolve_location
from newsroom.domain.sections import BY_SLUG, is_sensitive
from newsroom.nlp.similarity import token_overlap_score

logger = logging.getLogger(__name__)

# Weights are public and editable; the score is meaningless if it cannot be
# argued about. Each component is in [0, 1] and the weighted sum is rescaled.
COMPONENT_WEIGHTS = {
    "evidence": 0.32,
    "corroboration": 0.22,
    "recency": 0.14,
    "breaking": 0.12,
    "hyperlocal": 0.10,
    "source_trust": 0.06,
    "reader_weight": 0.04,
}


@dataclass
class ImportanceScore:
    score: float
    components: Dict[str, float] = field(default_factory=dict)
    reason: Optional[str] = None

    @property
    def level(self) -> str:
        if self.score >= 0.8:
            return "lead"
        if self.score >= 0.6:
            return "major"
        if self.score >= 0.4:
            return "standard"
        if self.score >= 0.22:
            return "brief"
        return "wire"

    def to_dict(self) -> Dict[str, Any]:
        return {
            "score": round(self.score, 3),
            "level": self.level,
            "components": {k: round(v, 3) for k, v in self.components.items()},
            "reason": self.reason,
        }


def score_importance(
    *,
    evidence_score: float,
    num_sources: int,
    source_trust: float,
    published_at: Optional[datetime],
    is_breaking: bool,
    is_developing: bool,
    district: Optional[str],
    section: str,
    reader_weight: float = 0.0,
    now: Optional[datetime] = None,
) -> ImportanceScore:
    now = now or datetime.utcnow()
    components: Dict[str, float] = {}

    components["evidence"] = _clamp(evidence_score)
    components["corroboration"] = _corroboration(num_sources)
    components["recency"] = _recency(published_at, now, is_developing)
    components["breaking"] = 1.0 if is_breaking else (0.45 if is_developing else 0.0)
    components["hyperlocal"] = _hyperlocal(district, section)
    components["source_trust"] = _clamp(source_trust)
    components["reader_weight"] = _clamp(reader_weight)

    total_weight = sum(COMPONENT_WEIGHTS.values())
    score = sum(COMPONENT_WEIGHTS[key] * components[key] for key in COMPONENT_WEIGHTS)
    score = score / total_weight

    return ImportanceScore(
        score=_clamp(score, high=1.0),
        components=components,
        reason=_reason(components, num_sources, is_breaking),
    )


def _reason(components: Dict[str, float], num_sources: int, is_breaking: bool) -> str:
    parts = []
    if is_breaking:
        parts.append("breaking")
    if num_sources >= 2:
        parts.append(f"{num_sources} sources")
    top = max(components.items(), key=lambda kv: kv[1], default=(None, 0.0))
    if top[0] and top[1] > 0.5:
        parts.append(f"top signal: {top[0]}")
    return "; ".join(parts) or "low signal"


def _corroboration(num_sources: int) -> float:
    # Two independent sources is a step change in reliability, not a linear one.
    if num_sources <= 0:
        return 0.0
    return _clamp(0.35 * math.log2(1 + num_sources), high=1.0)


_RECENCY_HALF_LIFE_HOURS = 18.0


def _recency(published_at: Optional[datetime], now: datetime, is_developing: bool) -> float:
    if not published_at:
        return 0.3 if is_developing else 0.15
    age_hours = max(0.0, (now - published_at).total_seconds() / 3600.0)
    if age_hours < 0:
        return 1.0
    decay = 0.5 ** (age_hours / _RECENCY_HALF_LIFE_HOURS)
    # A developing story stays fresher than a one-off report of equal age.
    return _clamp(decay * (1.25 if is_developing else 1.0), high=1.0)


_HYDERABAD_BOOST = {
    "Hyderabad", "Medchal-Malkajgiri", "Rangareddy", "Sangareddy",
}


def _hyperlocal(district: Optional[str], section: str) -> float:
    score = 0.25  # state-level Telangana news is the core mandate by default
    if district:
        score = 0.8 if district in _HYDERABAD_BOOST else 0.6
    slug = BY_SLUG.get(section)
    if slug and slug.telangana_local:
        score = min(1.0, score + 0.2)
    return _clamp(score)


def _clamp(value: float, *, low: float = 0.0, high: float = 1.0) -> float:
    try:
        numeric = float(value)
    except (TypeError, ValueError):
        return low
    return max(low, min(high, numeric))


# ---------------------------------------------------------------------------
# Location Engine
# ---------------------------------------------------------------------------

# Telangana state-level keywords, including the political institutions that
# make a story state-level even when no district is named.
_STATE_TERMS = (
    "తెలంగాణ", "telangana", "ముఖ్యమంత్రి", "ప్రభుత్వం", "అసెంబ్లీ",
    "హైకోర్టు", "ఎన్నికల సంఘం", "ప్రజా పంపిణీ", "tspsc", "ghmc",
)
_NON_TELANGANA_STATES = (
    "ఆంధ్రప్రదేశ్", "andhra pradesh", "కర్ణాటక", "karnataka",
    "మహారాష్ట్ర", "maharashtra", "తమిళనాడు", "tamil nadu",
)


@dataclass
class LocationResult:
    geo: GeoMatch
    is_telangana: bool
    is_national: bool
    is_world: bool
    confidence: float
    matched_terms: List[str] = field(default_factory=list)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "state": self.geo.state,
            "district": self.geo.district,
            "mandal": self.geo.mandal,
            "locality": self.geo.locality,
            "is_telangana": self.is_telangana,
            "is_national": self.is_national,
            "is_world": self.is_world,
            "confidence": round(self.confidence, 3),
            "matched_terms": self.matched_terms,
        }


def locate_story(title: Optional[str], body: Optional[str] = None,
                 *, feed_title: Optional[str] = None) -> LocationResult:
    """Resolve a story's geography from its own text plus its origin feed.

    Feed origin is a *weak* prior (an outlet can publish national copy); the
    article text always wins.
    """
    combined = "\n".join(part for part in (title, body) if part)
    geo = resolve_location(combined)
    used_feed_origin = False
    if geo.district is None and feed_title:
        # The article itself names no place. Fall back to the outlet's home
        # turf -- weak, but better than silently filing a district story as
        # state-level, and it never overrides an explicit district in the text.
        geo = resolve_location(feed_title)
        used_feed_origin = geo.district is not None

    text = (combined or "").lower()
    origin = (feed_title or "").lower()
    is_telangana = bool(_STATE_TERMS and any(term in text or term in origin for term in _STATE_TERMS))
    if geo.district:
        is_telangana = True
    is_national = geo.state == "India"
    is_world = geo.state == "World"
    outside = any(term in text for term in _NON_TELANGANA_STATES)
    if outside and not geo.district:
        is_telangana = False

    confidence = _location_confidence(geo, is_telangana)
    if used_feed_origin:
        confidence = min(confidence, 0.45)  # inferred from the outlet, not the story
    return LocationResult(
        geo=geo, is_telangana=is_telangana, is_national=is_national,
        is_world=is_world, confidence=confidence,
        matched_terms=geo.matched_terms,
    )


def _location_confidence(geo: GeoMatch, is_telangana: bool) -> float:
    if geo.locality:
        return 0.95
    if geo.mandal:
        return 0.9
    if geo.district:
        return 0.85
    if is_telangana:
        return 0.5  # state-level by default -- deliberately uncertain
    return 0.3


# ---------------------------------------------------------------------------
# Section (category) classifier
# ---------------------------------------------------------------------------

_STOPWORDS_FOR_CLASS = {"లో", "లోని", "కి", "కీ", "తో", "పై", "మీద", "వద్ద"}


def classify_section(title: Optional[str], body: Optional[str] = None,
                     *, source_section: Optional[str] = None,
                     location: Optional[LocationResult] = None,
                     is_breaking: bool = False) -> str:
    """Assign the story's section.

    Priority: an explicit breaking flag, then the source's own vertical, then
    keyword scoring over title+body, then a geographic default (Hyderabad vs
    Telangana) so nothing is ever uncategorised.
    """
    if is_breaking:
        return "breaking"

    if source_section and source_section in BY_SLUG:
        return source_section

    hay = " ".join(part for part in (title, body) if part) or ""
    lowered = hay.lower()
    best_slug, best_score = None, 0.0
    for slug, section in BY_SLUG.items():
        if not section.keywords:
            continue
        hits = sum(1.0 if keyword in lowered else 0.0 for keyword in section.keywords)
        # Normalising by keyword-list length punishes well-covered sections:
        # two distinct keyword hits is strong evidence no matter how long the
        # list is, so floor such matches above the single-keyword threshold.
        score = hits / max(1, len(section.keywords))
        if hits >= 2:
            score = max(score, 0.25)
        if score > best_score:
            best_slug, best_score = slug, score

    if best_slug and best_score >= 0.18:
        return best_slug

    if location and location.geo.district in ("Hyderabad", "Medchal-Malkajgiri", "Rangareddy"):
        return "hyderabad"
    if location and location.is_telangana:
        return "telangana"
    if location and location.is_world:
        return "world"
    if location and location.is_national:
        return "national"
    return "telangana"
