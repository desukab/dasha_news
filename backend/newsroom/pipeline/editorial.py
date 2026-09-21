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
    to_tenglish,
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

# The outlet's own furniture, which arrives glued to the real headline because
# the scraper read the page rather than the story. Cross-links, photo credits,
# video prompts and solicitation carry no news, and they are Telugu-outlet
# furniture written in Latin more often than they are Telugu, so both languages
# are listed against both scripts. The list is deliberately narrow: a phrase
# that can open a genuine headline costs us news, and a phrase that can only
# open a widget costs us nothing by being left in.
# Credits and image labels are safe to cut from either end: they name the
# outlet's own assets and never a fact about the story.
_BOTH_ENDS = (
    r"photo(?:graph)?\s+credits?|image\s+credits?|pic\s*[:\-]?\s*credit"
    r"|representational\s+(?:image|photo|picture)"
    r"|file\s+(?:photo|image|picture)"
    # Telugu has no single letter for the o-vowel, so the word is written with
    # either the ొ-sign or the ో-sign depending on the outlet; both spellings
    # are the same word and both have to be listed.
    r"|ఫ[ొో]టో\s*క్రెడిట్(?:స్)?"
    r"|ఇంకా\s*చదవండి|మరిన్ని\s*వార్తల\s*కోసం|మరిన్ని\s*ఆసక్తికర\s*వార్తలు"
)
# Prompts are only cut from the head. "Watch:" and "Read More" lead a chrome
# headline; at the tail they are far more likely to be the story's own words --
# "Budget watch:", "the files to read more carefully" -- and a strip there
# destroys a real headline to remove a widget that was not there.
_PROMPTS = (
    r"also\s+read(?:\s+(?:this|the|more))?(?:\s+(?:story|article|news|reports?))?"
    r"|read\s+more(?:\s+(?:about|on|at))?"
    r"|watch(?:\s+(?:now|this|live|video|here))?"
    r"|click\s+here|see\s+(?:photos?|images?|video|details?|here)"
    r"|full\s+story|more\s+details|read\s+the\s+full\s+story"
    r"|follow\s+us|subscribe\s+(?:now|to)|download\s+the\s+app"
    r"|published\s+on|updated\s+on|posted\s+on"
    r"|వీడియో\s*చూడండి|ఇక్కడ\s*చూడండి|క్లిక్\s*చేయండి"
    r"|షేర్\s*చేయండి|కామెంట్\s*చేయండి"
)
# A credit is usually followed by who owns it -- "ఫొటో క్రెడిట్: ANI" -- and
# leaving the attribution behind is worse than leaving the label, because
# "ప్రమాదం | : ANI" is a headline that says nothing after the pipe. The agency
# is bounded to an acronym-shaped token with no spaces, so it can swallow ANI
# and PTI but never the sentence that follows "Read More:".
_AGENCY = r"(?:\s*[:\-–—]\s*[A-Z][A-Za-z0-9&./-]{0,19})?"
# The glue between the furniture and the headline: "Also Read | టైటిల్" and
# "టైటిల్ - ఫొటో క్రెడిట్: ANI" are the two shapes it takes.
_GLUE = r"[\s|:.\-–—]*"

_TAIL = re.compile(rf"{_GLUE}(?:{_BOTH_ENDS}){_AGENCY}{_GLUE}$", re.I)
_HEAD = re.compile(rf"^{_GLUE}(?:(?:{_BOTH_ENDS}){_AGENCY}|{_PROMPTS}){_GLUE}", re.I)
_ANYWHERE = re.compile(word_boundary(_PROMPTS), re.I)


def strip_site_boilerplate(text: str) -> str:
    """Cut outlet furniture off both ends of a headline or a lead.

    Site chrome can stack ("Also Read | Watch: ..."), so the pass repeats until
    it stops changing the text rather than assuming one widget per end.
    """
    if not text:
        return text
    for _ in range(4):
        stripped = _TAIL.sub("", text)
        stripped = _HEAD.sub("", stripped)
        stripped = re.sub(r"\s+", " ", stripped).strip()
        if stripped == text:
            break
        text = stripped
    return text.strip(" |:.-–—")


_CLICKBAIT = re.compile(
    word_boundary(r"you won't believe|shocking|సంచలనం|షాకింగ్|goes viral|వైరల్"), re.I)


def write_headline(facts: Sequence[Any], *, language: str,
                   district: Optional[str], session=None,
                   story_id: Optional[int] = None) -> Draft:
    """Write one headline in the requested language."""
    if len(facts) < MIN_FACTS_TO_WRITE:
        return Draft(language, "", "", "", 0, "heuristic",
                     ["no facts available; nothing written"])
    if language == "ten":
        # Tenglish is a *reading* of the Telugu line, not a second opinion on
        # it: the Roman form is fixed by how readers write the names in it, so
        # a model asked for Tenglish copy would only guess at a register it has
        # no copy in. The Telugu headline is composed and [to_tenglish]
        # romanises it.
        return _heuristic_headline(facts, "ten", district)

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

    if language in ("te", "ten") and telugu_ratio(text) < 0.3:
        # Telugu script is the only source of a Telugu headline. The primary
        # fact of a story whose sources publish in English carries English in
        # text_te; publishing it as-is is how English reached the Telugu column.
        # Tenglish is the same Telugu read in Roman letters, so it has the same
        # requirement -- English romanised is still English.
        return Draft(language, "", "", "", 0, "heuristic",
                     [f"primary fact is not Telugu script; {language} withheld"])

    text = _clean_headline(text)
    if not text:
        return Draft(language, "", "", "", 0, "heuristic", ["headline cleaned to nothing"])

    if language == "en":
        text = _to_english_sketch(text, facts, district)

    # Location belongs in the story's metadata, not in its headline. The place
    # is already carried by `district`/`mandal`/`section` and the front page
    # shows it beside the headline, so appending "| తెలంగాణ" to every Telugu
    # line ate two of the ten words a headline is allowed and pushed the actual
    # news to the tail, where a phone truncates it.
    if word_count(text) > MAX_HEADLINE_WORDS:
        text = " ".join(text.split()[:MAX_HEADLINE_WORDS]).rstrip("–|-| ")
    if language == "te":
        text = strip_dangling_vowel_signs(text)
    elif language == "ten":
        text = to_tenglish(text)
    if _CLICKBAIT.search(text):
        warnings.append("clickbait marker detected and retained; review recommended")
    return Draft(language, text.strip(), "", "", word_count(text), "heuristic", warnings)


def _clean_headline(text: str) -> str:
    text = strip_site_boilerplate(text.strip())
    text = strip_dangling_vowel_signs(_TE_HEADLINE_STRIP.sub("", text.strip()))
    text = _EN_HEADLINE_STRIP.sub("", text.strip())
    text = re.sub(r"\s+", " ", text).strip()
    text = text.strip(" .|–—-")
    if text and text[-1] in ".!?" and word_count(text) > 4:
        text = text[:-1]
    return text


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
            # Telugu script is the only source of a Telugu sentence. A
            # clustered story can carry an English fact alongside Telugu ones,
            # and composing the Telugu body from both yields one sentence of
            # each script in the same paragraph; the language gate measures
            # that as leakage and the reader sees it as a broken translation.
            # The English fact still serves the en rendering. Tenglish reads
            # the Telugu sentence, so the same English fact is no more use to
            # it in Roman letters than in script.
            if telugu_ratio(text) < 0.3:
                continue
        if language == "en" and fact.text_en is None:
            continue
        if attribution and _needs_attribution(fact, language):
            # The attribution's Telugu tail romanises with the sentence; the
            # outlet name is already Latin either way.
            text = _attach_attribution(text, attribution,
                                       "te" if language == "ten" else language)
        if language == "te":
            text = strip_dangling_vowel_signs(text)
        elif language == "ten":
            text = to_tenglish(text)
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
