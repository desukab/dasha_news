"""Source Comparator.

When two or more sources report the same story, the Comparator decides what
that means editorially. It *never* silently picks a winner: agreement is
recorded as corroboration, disagreement is recorded as a conflict with both
sides attributed.
"""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

from newsroom.nlp.similarity import shape_similarity, token_overlap_score
from newsroom.nlp.telugu import word_boundary

logger = logging.getLogger(__name__)


@dataclass
class SourceComparison:
    corroborates: bool
    conflict: Optional[str] = None
    similarity: float = 0.0
    note: Optional[str] = None


def compare_articles(left, right) -> SourceComparison:
    """Compare two reports of the same event."""
    left_text = " ".join(part for part in (
        getattr(left, "title_raw", None), getattr(left, "summary_text", None)) if part)
    right_text = " ".join(part for part in (
        getattr(right, "title_raw", None), getattr(right, "summary_text", None)) if part)
    similarity = max(
        token_overlap_score(left_text, right_text),
        shape_similarity(left_text, right_text),
    )

    conflict = _detect_conflict(left_text, right_text)
    if conflict:
        return SourceComparison(
            corroborates=False,
            conflict=conflict,
            similarity=similarity,
            note="sources disagree; both versions retained",
        )
    return SourceComparison(
        corroborates=similarity >= 0.35,
        similarity=similarity,
        note="independent corroboration" if similarity < 0.35 else None,
    )


_DEATH_WORDS = (
    # Telugu: మృతి / మరణం family, and the colloquial periphrastics.
    "మృతి", "మరణ", "చనిపో", "గురై", "అసువు", "హత్య", "ప్రాణాలు కో",
    # English.
    "killed", "died", "dead", "death", "fatalit", "perished", "casualt",
)

# Telugu writes numerals as words; "ఇద్దరు మృతి చెందారు" means "two died".
_TE_NUMBERS = {
    "ఎనిమిదిమంది": 8, "తొమ్మిదిమంది": 9, "పదిమంది": 10,
    "ఇరవై": 20, "ముప్పై": 30, "నలభై": 40, "యాభై": 50,
    "ఇద్దరు": 2, "ముగ్గురు": 3, "నలుగురు": 4, "ఐదుగురు": 5,
    "ఆరుగురు": 6, "ఏడుగురు": 7,
    "ఒక్క": 1, "రెండు": 2, "మూడు": 3, "నాలుగు": 4, "ఐదు": 5,
    "ఆరు": 6, "ఏడు": 7, "ఎనిమిది": 8, "తొమ్మిది": 9, "పది": 10,
}
_TE_NUMBER_WORDS = "|".join(sorted(_TE_NUMBERS, key=len, reverse=True))

# A figure counts only if it sits close to the death word; this keeps an
# unrelated "₹3 లక్షలు" in the same sentence from masquerading as a toll.
_CASUALTY_WINDOW = 28


def _figures_near(text: str) -> List[int]:
    """Casualty figures named in ``text``, nearest-first per death mention."""
    lowered = text.lower()
    digits = [(m.start(), int(m.group(0))) for m in re.finditer(r"\d+", text)]
    telugu = []
    for match in re.finditer(word_boundary(_TE_NUMBER_WORDS), text):
        telugu.append((match.start(), _TE_NUMBERS[match.group(0)]))
    candidates = digits + telugu

    figures: List[int] = []
    for death in _DEATH_WORDS:
        start = 0
        while True:
            index = lowered.find(death, start)
            if index < 0:
                break
            start = index + len(death)
            nearby = [value for pos, value in candidates
                      if abs(pos - index) <= _CASUALTY_WINDOW]
            if nearby:
                figures.append(max(nearby))
    return figures


def _detect_casualty_conflict(left: str, right: str) -> Optional[str]:
    """Two sources quoting different casualty figures is a real conflict.

    The toll is often genuinely unknown early on, so this is not a verdict --
    it is a flag that a human editor must reconcile. If either side names no
    figure at all there is nothing to compare and no conflict is claimed.
    """
    figures = []
    for text in (left, right):
        found = _figures_near(text)
        if not found:
            return None
        figures.append(max(found))
    if len(set(figures)) > 1:
        small, large = sorted(figures)
        return f"casualty figures differ ({small} vs {large}) across sources"
    return None


_CONFLICT_PAIRS = (
    ("కాదు", "అవుతుంది"),
    ("లేదు", "ఉంది"),
    ("నిరాకరించారు", "అంగీకరించారు"),
    ("denied", "confirmed"),
    ("not", "confirmed"),
    ("killed", "injured"),
    ("died", "injured"),
    ("resigned", "appointed"),
    ("వ్యతిరేకం", "మద్దతు"),
    ("opposed", "supported"),
)


def _detect_conflict(left: str, right: str) -> Optional[str]:
    casualty = _detect_casualty_conflict(left, right)
    if casualty:
        return casualty
    lowered_left, lowered_right = left.lower(), right.lower()
    for affirmative, negative in _CONFLICT_PAIRS:
        if affirmative in lowered_left and negative in lowered_right:
            return f"'{affirmative}' vs '{negative}' across sources"
        if negative in lowered_left and affirmative in lowered_right:
            return f"'{negative}' vs '{affirmative}' across sources"
    return None


@dataclass
class ComparisonSummary:
    num_sources: int = 0
    corroborating: List[str] = field(default_factory=list)
    conflicting: List[str] = field(default_factory=list)
    independent_count: int = 0

    def to_dict(self) -> Dict[str, Any]:
        return {
            "num_sources": self.num_sources,
            "corroborating": self.corroborating,
            "conflicting": self.conflicting,
            "independent_count": self.independent_count,
        }


def summarise_comparisons(comparisons: List[SourceComparison], source_names: List[str]
                          ) -> ComparisonSummary:
    summary = ComparisonSummary(num_sources=len(source_names))
    for index, comparison in enumerate(comparisons):
        if comparison.conflict and comparison.conflict not in summary.conflicting:
            summary.conflicting.append(comparison.conflict)
        elif comparison.corroborates:
            name = source_names[index] if index < len(source_names) else "source"
            if name not in summary.corroborating:
                summary.corroborating.append(name)
        else:
            summary.independent_count += 1
    return summary
