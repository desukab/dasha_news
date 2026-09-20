"""Headline Engine and the three editorial writers.

Each writer produces ORIGINAL prose. The deterministic path composes from the
story's own fact list -- it can paraphrase, reorder, and abbreviate, but it
cannot invent content, because it only has the facts to work from.

Every writer is also bounded: a maximum word count, a maximum number of
sentences, and an explicit refusal to emit anything when there is no source
material at all.
"""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Sequence

from newsroom.ai.prompts import article_prompt, headline_prompt
from newsroom.ai.provider import get_provider, is_heuristic, record_call
from newsroom.domain.evidence import EvidenceLevel
from newsroom.nlp.language import Language, detect_language
from newsroom.nlp.telugu import (
    split_sentences,
    strip_dangling_vowel_signs,
    telugu_ratio,
    transliterate_to_tenglish,
    truncate_sentences,
    word_boundary,
    word_count,
)

logger = logging.getLogger(__name__)

MAX_HEADLINE_WORDS = 10
MAX_BODY_WORDS = 200
MAX_BODY_SENTENCES = 8
MIN_FACTS_TO_WRITE = 1

_TELEGRAPHIC_CONNECTIVES = {
    "te": {"and": " మరియు ", "according": " ప్రకారం "},
    "en": {"and": " and ", "according": " according to "},
}


@dataclass
class Draft:
    language: str
    headline: str
    lead: str
    body: str
    words: int
    source: str   # "model" | "heuristic"
    warnings: List[str]

    def to_dict(self) -> Dict[str, Any]:
        return {
            "language": self.language,
            "headline": self.headline,
            "lead": self.lead,
            "body": self.body,
            "words": self.words,
            "source": self.source,
            "warnings": self.warnings,
        }


# ---------------------------------------------------------------------------
# Headline Engine
# ---------------------------------------------------------------------------

_TE_HEADLINE_STRIP = re.compile(r"^\s*(తెలంగాణ\s*న్యూస్|బ్రేకింగ్\s*న్యూస్|[|\-–—]\s*)+", re.I)
_EN_HEADLINE_STRIP = re.compile(r"^\s*(breaking[:\s\-]*|just in[:\s\-]*|[|\-–—]\s*)+", re.I)
_CLICKBAIT = re.compile(
    word_boundary(r"you won't believe|shocking|సంచలనం|షాకింగ్|goes viral|వైరల్"), re.I)


def write_headline(facts: Sequence[Any], *, language: str,
                   district: Optional[str], session=None,
                   story_id: Optional[int] = None) -> Draft:
    """Write one headline in the requested language."""
    if len(facts) < MIN_FACTS_TO_WRITE:
        return Draft(language, "", "", "", 0, "heuristic",
                     ["no facts available; nothing written"])

    if not is_heuristic():
        payload = _fact_payload(facts)
        result = get_provider().complete(
            headline_prompt(payload, language, district),
            stage="headline", story_id=story_id, temperature=0.5)
        if session is not None:
            record_call(result, "headline", story_id, session)
        if result.success and result.text.strip():
            text = _clean_headline(result.text)
            if text:
                return Draft(language, text, "", "", word_count(text), "model", [])

    return _heuristic_headline(facts, language, district)


def _heuristic_headline(facts: Sequence[Any], language: str,
                        district: Optional[str]) -> Draft:
    """Compose a headline from the strongest facts without a model.

    Uses the source's own title when the story is single-source (a legitimate
    light edit is applied to strip outlet branding), otherwise composes from
    the top fact plus the place.
    """
    warnings: List[str] = []
    primary = facts[0]
    text = primary.text_te or ""
    if not text:
        return Draft(language, "", "", "", 0, "heuristic", ["empty primary fact"])

    source_title = getattr(primary, "source_title", None)
    if source_title and _source_only(facts):
        text = source_title

    if language == "te" and telugu_ratio(text) < 0.3:
        # Telugu script is the only source of a Telugu headline. The primary
        # fact of a story whose sources publish in English carries English in
        # text_te; publishing it as-is is how English reached the Telugu column.
        return Draft(language, "", "", "", 0, "heuristic",
                     ["primary fact is not Telugu script; Telugu withheld"])

    text = _clean_headline(text)
    if not text:
        return Draft(language, "", "", "", 0, "heuristic", ["headline cleaned to nothing"])

    if language == "ten":
        # Roman Telugu can only come from Telugu script. Transliteration is a
        # no-op on Latin input, so romanising an English fact would emit the
        # English sentence unchanged and it would be published as Tenglish --
        # which is how the ten column filled up with wire copy. Refuse instead,
        # the same way _to_english_sketch refuses to fake an English headline
        # out of Telugu script.
        if telugu_ratio(text) < 0.3:
            return Draft(language, "", "", "", 0, "heuristic",
                         ["source fact is not Telugu script; Tenglish withheld"])
        text = transliterate_to_tenglish(text)
    elif language == "en":
        text = _to_english_sketch(text, facts, district)

    place = district or "తెలంగాణ"
    if language == "en":
        place = district or "Telangana"
    elif language == "ten":
        place = district or "Telangana"
    elif district and telugu_ratio(district) < 0.2:
        # A district name in Latin letters has no business on a Telugu headline:
        # it is the one thing that turns a correct Telugu line into a mixed-script
        # one, and the language gate measures it as English leakage. The
        # district is already carried by the story's section, so nothing is lost
        # by leaving it off the Telugu rendering.
        place = "తెలంగాణ"

    if not _contains_place(text, place):
        text = f"{text} – {place}" if language in ("en", "ten") else f"{text} | {place}"

    if word_count(text) > MAX_HEADLINE_WORDS:
        text = " ".join(text.split()[:MAX_HEADLINE_WORDS]).rstrip("–|-| ")
    if language == "te":
        text = strip_dangling_vowel_signs(text)
    if _CLICKBAIT.search(text):
        warnings.append("clickbait marker detected and retained; review recommended")
    return Draft(language, text.strip(), "", "", word_count(text), "heuristic", warnings)


def _clean_headline(text: str) -> str:
    text = strip_dangling_vowel_signs(_TE_HEADLINE_STRIP.sub("", text.strip()))
    text = _EN_HEADLINE_STRIP.sub("", text.strip())
    text = re.sub(r"\s+", " ", text).strip()
    text = text.strip(" .|–—-")
    if text and text[-1] in ".!?" and word_count(text) > 4:
        text = text[:-1]
    return text


def _contains_place(text: str, place: str) -> bool:
    return place.lower() in text.lower()


def _source_only(facts: Sequence[Any]) -> bool:
    sources = {getattr(f, "source_article_id", None) for f in facts}
    return len(sources) == 1


_EN_PLACEHOLDER = re.compile(r"[ఀ-౿]+")


def _to_english_sketch(text: str, facts: Sequence[Any], district: Optional[str]) -> str:
    """Tenglish/English fallback: use the English fact text when present.

    Telugu script is never transliterated into English as if it were an English
    headline; that produces gibberish. If no English fact exists we say so in
    the warnings instead of faking a translation.
    """
    for fact in facts:
        if getattr(fact, "text_en", None):
            return _clean_headline(str(fact.text_en))
    english = _EN_PLACEHOLDER.sub("", text).strip()
    return english or ""


# ---------------------------------------------------------------------------
# Article writers
# ---------------------------------------------------------------------------

def write_article(facts: Sequence[Any], *, language: str,
                  headline: Optional[str], district: Optional[str],
                  session=None, story_id: Optional[int] = None,
                  max_words: int = MAX_BODY_WORDS) -> Draft:
    """Write headline + lead + body in one language."""
    if len(facts) < MIN_FACTS_TO_WRITE:
        return Draft(language, "", "", "", 0, "heuristic",
                     ["no facts available; nothing written"])

    if not is_heuristic():
        payload = _fact_payload(facts)
        result = get_provider().complete(
            article_prompt(payload, language, headline, district, max_words=max_words),
            stage=f"article:{language}", story_id=story_id, temperature=0.45)
        if session is not None:
            record_call(result, f"article:{language}", story_id, session)
        if result.success and result.text.strip():
            body = _normalise_body(result.text)
            if word_count(body) >= 12:
                lead = split_sentences(body)[0] if split_sentences(body) else body
                return Draft(language, headline or "", lead, body, word_count(body),
                             "model", [])

    return _heuristic_article(facts, language, headline, district, max_words)


def _heuristic_article(facts: Sequence[Any], language: str,
                       headline: Optional[str], district: Optional[str],
                       max_words: int) -> Draft:
    """Compose an article from facts, attributing each claim to its source."""
    warnings: List[str] = []
    sentences: List[str] = []

    for fact in facts:
        text = (fact.text_en if language == "en" and fact.text_en else fact.text_te) or ""
        if not text:
            continue
        attribution = fact.attributed_to
        if language in ("te", "ten"):
            # Telugu script is the only source for both Telugu and Roman Telugu.
            # A clustered story can carry an English fact alongside Telugu ones,
            # and composing the Telugu body from both yields one sentence of
            # each script in the same paragraph; the language gate measures
            # that as leakage and the reader sees it as a broken translation.
            # The English fact still serves the en rendering.
            if telugu_ratio(text) < 0.3:
                continue
        if language == "ten":
            # Only Telugu script romanises into Roman Telugu; a Latin-script
            # fact would pass through transliteration untouched and be
            # published as Tenglish. Skipped here, not faked.
            text = transliterate_to_tenglish(text)
            attribution = transliterate_to_tenglish(attribution) if attribution else None
        if language == "en" and fact.text_en is None:
            continue
        if attribution and _needs_attribution(fact, language):
            text = _attach_attribution(text, attribution, language)
        if language == "te":
            text = strip_dangling_vowel_signs(text)
        sentences.append(text)

    if not sentences:
        return Draft(language, headline or "", "", "", 0, "heuristic",
                     ["no renderable facts for this language"])

    lead = sentences[0]
    body = truncate_sentences(" ".join(sentences), MAX_BODY_SENTENCES)
    if word_count(body) > max_words:
        body = " ".join(body.split()[:max_words])
        warnings.append("truncated to the configured word limit")

    if language == "te":
        body = strip_dangling_vowel_signs(body)
    return Draft(language, headline or "", lead, body, word_count(body), "heuristic", warnings)


def _fact_evidence_level(fact: Any) -> Optional[EvidenceLevel]:
    """Evidence level of a fact, from an ExtractedFact or an ORM Fact row."""
    value = getattr(fact, "level", None) or getattr(fact, "evidence_level", None)
    if value is None:
        return None
    try:
        return EvidenceLevel(str(value).strip().lower())
    except ValueError:
        return None


def _needs_attribution(fact: Any, language: str) -> bool:
    level = _fact_evidence_level(fact)
    if level is None:
        return True
    return level.weight < EvidenceLevel.FACT.weight


def _attach_attribution(text: str, attribution: Optional[str], language: str) -> str:
    if not attribution:
        return text
    if language == "en":
        tail = f", according to {attribution}"
    elif language == "ten":
        tail = f", {transliterate_to_tenglish(attribution)} prakaram"
    else:
        tail = f", {attribution} ప్రకారం"
    if text.rstrip().endswith((".", "।")):
        return text.rstrip(" .।") + tail + "।"
    return text + tail


def _normalise_body(text: str) -> str:
    text = strip_dangling_vowel_signs(re.sub(r"\n{3,}", "\n\n", text.strip()))
    return re.sub(r"[ \t]+", " ", text).strip()


def _fact_payload(facts: Sequence[Any]) -> List[Dict[str, Any]]:
    payload: List[Dict[str, Any]] = []
    for fact in facts:
        payload.append({
            "source_name": getattr(fact, "source_name", "source"),
            "published": str(getattr(fact, "published_at", "") or ""),
            "title": getattr(fact, "source_title", "") or "",
            "text": fact.text_te or fact.text_en or "",
        })
    return payload
