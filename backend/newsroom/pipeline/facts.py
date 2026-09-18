"""Fact Engine: extract discrete, evidence-levelled facts from source text.

This is the heart of the "prose is not the source of truth" rule. Facts are
structured rows with an evidence level, a confidence, and a pointer back to
the exact article they came from. Everything rendered for the reader is
derived from them.

The deterministic extractor is a rule-based claim splitter with Telugu-aware
sentence segmentation and a set of attribution and hedging signals. It never
invents a fact: a sentence with no attributable verb is recorded at
``unverified``, not promoted.
"""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Sequence

from newsroom.ai.prompts import fact_prompt
from newsroom.ai.provider import (
    AiUnavailable,
    get_provider,
    is_heuristic,
    parse_json_object,
    with_fallback,
)
from newsroom.domain.evidence import EvidenceLevel
from newsroom.nlp.language import Language, detect_language
from newsroom.nlp.telugu import (
    content_tokens,
    split_sentences,
    telugu_ratio,
    word_count,
    word_boundary,
)

logger = logging.getLogger(__name__)

OFFICIAL_TERMS = (
    "ప్రకటించారు", "ప్రకటించింది", "తెలిపారు", "తెలింది", "ఆదేశించారు",
    "నివేదించారు", "నిర్ణయించారు", "ప్రభుత్వం", "అధికారికంగా", "ప్రకారం",
    "announced", "said in a statement", "issued an order", "officially",
    "according to", "government", "authorities", "department of",
)
CLAIM_TERMS = (
    "వాదించారు", "పేర్కొన్నారు", "చెప్పారు", "అన్నారు", "అంటున్నారు",
    "అని చెప్పారు", "కాబట్టి",
    "claimed", "says", "stated", "alleged", "demanded", "promised",
)
ALLEGATION_TERMS = (
    "ఆరోపించారు", "ఆరోపణలు", "ఫిర్యాదు", "కేసు నమోదు",
    "accused of", "alleged", "booked", "case registered", "charged",
)
FORECAST_TERMS = (
    "అంచనా", "భవిష్యత్తు", "అనుకుంటున్నారు", "ఉంటుంది",
    "likely to", "expected to", "forecast", "may be", "will be", "predicts",
)
OPINION_TERMS = (
    "అభిప్రాయం", "నా ఉద్దేశంలో", "అనిపిస్తుంది", "కావాలి",
    "in my opinion", "should be", "ought to", "unfortunately", "we believe",
    "the truth is", "sadly",
)
VERIFIED_TERMS = (
    "నిర్ధారించారు", "ధృవీకరించారు", "రికార్డు ప్రకారం", "గణాంకాల ప్రకారం",
    "confirmed", "records show", "statistics show", "data shows", "filed in court",
)
_HEDGE = (
    "నిర్ధారణ లేదు", "పుకారు", "అతనికని", "ఇంకా స్పష్టం కాలేదు",
    "reportedly", "unconfirmed", "rumour", "allegedly", "it is said that",
)
_ATTRIBUTED = re.compile(
    word_boundary(r"ప్రకారం|చెప్పారు|తెలిపారు|వాదించారు|"
                  r"according to|said|stated|claimed") + r"|:\s", re.IGNORECASE)
_NUMBER = re.compile(r"\d[\d,\.]*")


@dataclass
class ExtractedFact:
    text_te: str
    text_en: Optional[str] = None
    level: str = "claim"
    confidence: float = 0.0
    attributed_to: Optional[str] = None

    def to_dict(self) -> Dict[str, Any]:
        return {
            "text_te": self.text_te,
            "text_en": self.text_en,
            "level": self.level,
            "confidence": round(self.confidence, 3),
            "attributed_to": self.attributed_to,
        }


def extract_facts(text: Optional[str], *, language: str = "te",
                  article_id: Optional[int] = None, session=None,
                  story_id: Optional[int] = None) -> List[ExtractedFact]:
    """Extract facts from source text.

    Uses the configured model when one is available, otherwise the deterministic
    rule-based extractor. The heuristic path is the default and is always the
    fallback when a model call fails or returns unusable output.
    """
    if not text or not text.strip():
        return []

    if is_heuristic():
        return heuristic_facts(text, language)

    source_name = "source"
    result = get_provider().complete(
        fact_prompt(text, source_name), stage="fact_engine", story_id=story_id)
    if session is not None:
        from newsroom.ai.provider import record_call
        record_call(result, "fact_engine", story_id, session)
    parsed = parse_json_object(result.text) if result.success else None
    if parsed is None:
        return heuristic_facts(text, language)
    items = parsed if isinstance(parsed, list) else parsed.get("facts")
    facts: List[ExtractedFact] = []
    for item in items or []:
        if not isinstance(item, dict):
            continue
        raw_text = str(item.get("text_te") or item.get("text_en") or "").strip()
        if not raw_text:
            continue
        level = _normalise_level(str(item.get("level") or "claim"))
        confidence = _clamp(item.get("confidence"))
        facts.append(ExtractedFact(
            text_te=raw_text,
            text_en=str(item.get("text_en") or "").strip() or None,
            level=level,
            confidence=confidence,
            attributed_to=str(item.get("attributed_to") or "").strip() or None,
        ))
    return facts or heuristic_facts(text, language)


def heuristic_facts(text: str, language: str = "te") -> List[ExtractedFact]:
    """Deterministic, model-free fact extraction."""
    sentences = [s for s in split_sentences(text) if 30 <= len(s) <= 600]
    facts: List[ExtractedFact] = []
    for sentence in sentences:
        level = classify_sentence(sentence)
        confidence = _sentence_confidence(sentence, level)
        attribution = _attribution(sentence, language)
        facts.append(ExtractedFact(
            text_te=sentence,
            text_en=_english_rendering(sentence, language),
            level=level,
            confidence=confidence,
            attributed_to=attribution,
        ))
    facts.sort(key=lambda f: (-EvidenceLevel(f.level).weight, -f.confidence))
    return facts[:14]


def _english_rendering(sentence: str, language: str) -> Optional[str]:
    """The Latin-script text of a sentence, when it is already Latin-script.

    The heuristic path never translates: Telugu script stays Telugu and its
    ``text_en`` stays empty rather than being faked. But an English or
    Tenglish sentence is Latin script already, and storing it under
    ``text_en`` is what lets the English writer render it. Without it, every
    fact looked "untranslated" and the English edition of an English-language
    story came out blank.

    Tenglish (Telugu written in Latin script) is recorded here deliberately:
    it is not an English translation, but it is the closest Latin-script
    rendering the deterministic path can produce, and it is labelled as
    Tenglish everywhere the reader sees it.
    """
    detected = detect_language(sentence)
    if detected in (Language.ENGLISH, Language.TENGLISH):
        return sentence
    return None


def classify_sentence(sentence: str) -> str:
    """Assign the strongest evidence level a sentence supports."""
    lowered = sentence.lower()
    if any(term in lowered for term in _HEDGE):
        return EvidenceLevel.UNVERIFIED.value
    if any(term in lowered for term in VERIFIED_TERMS):
        return EvidenceLevel.FACT.value
    if any(term in lowered for term in OFFICIAL_TERMS):
        return EvidenceLevel.OFFICIAL_STATEMENT.value
    if any(term in lowered for term in FORECAST_TERMS):
        return EvidenceLevel.FORECAST.value
    if any(term in lowered for term in OPINION_TERMS):
        return EvidenceLevel.OPINION.value
    if any(term in lowered for term in ALLEGATION_TERMS):
        return EvidenceLevel.ALLEGATION.value
    if any(term in lowered for term in CLAIM_TERMS):
        return EvidenceLevel.CLAIM.value
    if _ATTRIBUTED.search(sentence):
        return EvidenceLevel.CLAIM.value
    # A bare declarative with numbers and no attribution is still a claim.
    return EvidenceLevel.CLAIM.value if _NUMBER.search(sentence) else EvidenceLevel.UNVERIFIED.value


def _sentence_confidence(sentence: str, level: str) -> float:
    base = EvidenceLevel(level).weight
    tokens = content_tokens(sentence)
    specificity = min(0.12, len(tokens) * 0.008)
    return _clamp(base + specificity)


def _attribution(sentence: str, language: str) -> Optional[str]:
    match = _ATTRIBUTED.search(sentence)
    if not match:
        return None
    start = max(0, match.start() - 60)
    fragment = sentence[start:match.start()].strip().rstrip(",")
    if not fragment:
        return None
    return fragment[-120:]


def _normalise_level(value: str) -> str:
    try:
        return EvidenceLevel(value.strip().lower()).value
    except ValueError:
        return EvidenceLevel.CLAIM.value


def _clamp(value: Any) -> float:
    try:
        numeric = float(value)
    except (TypeError, ValueError):
        return 0.5
    return max(0.05, min(1.0, numeric))


def fact_signature(fact: ExtractedFact) -> str:
    import hashlib
    normalised = "".join(content_tokens(fact.text_te)).lower()
    return hashlib.sha256(normalised.encode("utf-8")).hexdigest()[:16]


def merge_facts(existing: Sequence[ExtractedFact], incoming: Sequence[ExtractedFact]
                ) -> List[ExtractedFact]:
    """Deduplicate facts across sources while keeping disagreement visible.

    Two facts are the same claim only when their content signature matches AND
    they are not in tension -- otherwise both survive and the story is marked
    as disputed.
    """
    merged: List[ExtractedFact] = []
    seen: Dict[str, ExtractedFact] = {}

    def place(fact: ExtractedFact) -> None:
        fact.level = _normalise_level(fact.level)
        signature = fact_signature(fact)
        prior = seen.get(signature)
        if prior is None:
            seen[signature] = fact
            merged.append(fact)
            return
        if _in_tension(prior, fact):
            prior.level = EvidenceLevel.DISPUTED.value
            prior.confidence = min(prior.confidence, fact.confidence) * 0.8
            prior.attributed_to = prior.attributed_to or fact.attributed_to
            return
        # Same claim, no tension: corroboration upgrades it. Keep the
        # best-evidenced rendering, and never let the surviving confidence
        # fall below either side -- a second source confirming a fact is
        # itself evidence.
        if _better_evidence(fact, prior):
            fact.confidence = max(fact.confidence, prior.confidence)
            fact.attributed_to = fact.attributed_to or prior.attributed_to
            merged[merged.index(prior)] = fact
            seen[signature] = fact
        else:
            prior.confidence = min(1.0, max(prior.confidence, fact.confidence) * 0.92 + 0.05)
            prior.attributed_to = prior.attributed_to or fact.attributed_to

    for fact in list(existing) + list(incoming):
        place(fact)
    merged.sort(key=lambda f: (-EvidenceLevel(f.level).weight, -f.confidence))
    return merged


def _better_evidence(candidate: ExtractedFact, incumbent: ExtractedFact) -> bool:
    """Should `candidate` replace `incumbent` for the same claim?

    Evidence level dominates; ties fall back to confidence, then to whichever
    version names its source.
    """
    left = EvidenceLevel(candidate.level).weight
    right = EvidenceLevel(incumbent.level).weight
    if left != right:
        return left > right
    if candidate.confidence != incumbent.confidence:
        return candidate.confidence > incumbent.confidence
    return bool(candidate.attributed_to) and not incumbent.attributed_to


def _in_tension(left: ExtractedFact, right: ExtractedFact) -> bool:
    """Crude contradiction detector: numbers disagree, polarity differs."""
    left_numbers = set(_NUMBER.findall(left.text_te))
    right_numbers = set(_NUMBER.findall(right.text_te))
    if left_numbers and right_numbers and left_numbers.isdisjoint(right_numbers):
        return True
    negators = ("కాదు", "లేదు", "నిరాకరించారు", "denied", "not ", "no ")
    left_negative = any(neg in left.text_te for neg in negators)
    right_negative = any(neg in right.text_te for neg in negators)
    if left_negative != right_negative:
        return True
    return False
