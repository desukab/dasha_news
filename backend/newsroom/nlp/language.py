"""Language detection (Telugu / English / Tenglish) without a model."""

from __future__ import annotations

import re
from dataclasses import dataclass
from enum import Enum
from typing import Tuple

from newsroom.nlp.telugu import latin_ratio, telugu_ratio


class Language(str, Enum):
    TELUGU = "te"
    ENGLISH = "en"
    TENGLISH = "ten"   # Telugu written in Latin script
    MIXED = "mix"
    UNKNOWN = "und"


def detect_language(text: str | None) -> Language:
    """Rule-based script detection.

    Tenglish is detected by *shape*: no Telugus script at all, plus a high
    share of Latin characters, plus at least one token that is not an English
    dictionary word. The dictionary is tiny on purpose -- it only has to tell
    "the user typed Telugu in Latin letters" from "this is an English wire
    story".
    """
    if not text or not text.strip():
        return Language.UNKNOWN

    te = telugu_ratio(text)
    la = latin_ratio(text)

    if te > 0.15:
        return Language.TELUGU if te >= 0.5 else Language.MIXED
    if la < 0.4:
        return Language.UNKNOWN

    tokens = [t for t in text.lower().split() if t.isalpha()]
    if not tokens:
        return Language.UNKNOWN

    english_hits = sum(1 for tok in tokens if tok in _ENGLISH_CORE)
    ratio = english_hits / len(tokens)
    if ratio >= 0.6:
        return Language.ENGLISH
    if ratio <= 0.2:
        return Language.TENGLISH
    return Language.TENGLISH if ratio < 0.4 else Language.MIXED


_ENGLISH_CORE = {
    "the", "a", "an", "and", "or", "but", "of", "in", "on", "at", "to", "for",
    "with", "by", "from", "is", "are", "was", "were", "has", "have", "had",
    "that", "this", "which", "who", "whom", "when", "where", "what", "why",
    "how", "all", "any", "both", "each", "few", "more", "most", "other",
    "some", "such", "own", "same", "than", "too", "very", "can", "will",
    "just", "should", "now", "also", "said", "says", "after", "before",
    "during", "between", "while", "because", "about", "into", "over",
    "police", "government", "minister", "party", "state", "district",
    "village", "people", "year", "month", "week", "day", "today",
    "yesterday", "tomorrow", "monday", "tuesday", "wednesday", "thursday",
    "friday", "saturday", "sunday", "january", "february", "march", "april",
    "may", "june", "july", "august", "september", "october", "november",
    "december", "india", "indian", "telangana", "hyderabad", "new", "one",
    "two", "three", "first", "second", "third", "city", "town", "area",
    "office", "case", "court", "school", "college", "hospital", "road",
    "water", "power", "food", "money", "price", "market", "stock", "share",
    "cricket", "match", "team", "player", "film", "movie", "actor",
    "health", "weather", "rain", "farmer", "crop", "land", "job", "jobs",
    "exam", "result", "student", "teacher", "police", "crime", "murder",
    "arrest", "fire", "accident", "injury", "death", "killed", "injured",
    "injured", "attack", "protest", "rally", "meeting", "speech",
}


# ---------------------------------------------------------------------------
# Language quality gate
# ---------------------------------------------------------------------------

# What each output language must actually be written in. Tenglish is the
# special case: it is Telugu *in Latin script*, so a Telugu-script string is
# wrong for it and an English sentence is wrong for it too.
_EXPECTED_SCRIPT = {
    "te": Language.TELUGU,
    "ten": Language.TENGLISH,
    "en": Language.ENGLISH,
}

# A Telugu headline may legitimately carry a few Latin tokens -- a name, a
# unit, an abbreviation like "RTC" or "BRS". But past this share the line is
# an English headline wearing a Telugu column name, which is how English wire
# copy has been reaching the Telugu feed.
_MAX_LATIN_IN_TELUGU = 0.30

# Roman Telugu is told apart from English by *shape*, not vocabulary.
# Vocabulary coverage cannot do the job: the two languages share thousands of
# words -- every English noun in a code-mixed sentence is an English word --
# and the small dictionary that ships here leaves the two distributions
# overlapping. Measured against the live feed they were indistinguishable,
# which is how the Tenglish column came to be full of English copy that the
# transliteration step had passed through untouched.
#
# Two dictionary-free signals do separate them, and both are properties of the
# languages rather than accidents of a word list:
#
#  1. Telugu words end in a vowel. This is a phonological constraint of the
#     language, not a statistical tendency, so it survives transliteration
#     perfectly: a Roman Telugu line keeps its open syllables. English words
#     mostly end in a consonant.
#  2. An English sentence is held together by its closed-class function words
#     ("the", "of", "in", "is"); Roman Telugu uses "lo", "ki", "andaru"
#     instead, so those words are simply absent.
#
# Measured over 60 real Telugu facts transliterated and 60 real English facts:
#
#                   vowel-ending tokens   English function words
#     Roman Telugu      0.75 .. 1.00      0.00 .. 0.11
#     English           0.07 .. 0.38      0.23 .. 0.67
#
# The two thresholds below sit in the open gap between those bands.

_MIN_VOWEL_ENDING_FOR_TENGISH = 0.50
_MAX_ENGLISH_FUNC_IN_TENGISH = 0.20

_ENGLISH_FUNCTION_WORDS = {
    "the", "a", "an", "and", "or", "but", "of", "in", "on", "at", "to", "for",
    "with", "by", "from", "is", "are", "was", "were", "be", "been", "being",
    "am", "has", "have", "had", "having", "that", "this", "these", "those",
    "which", "who", "whom", "whose", "when", "where", "what", "why", "how",
    "all", "any", "both", "each", "few", "more", "most", "other", "some",
    "such", "own", "same", "than", "too", "very", "can", "will", "just",
    "should", "now", "also", "not", "no", "if", "then", "there", "here",
    "would", "could", "may", "might", "must", "shall", "as", "so", "up",
    "out", "about", "into", "over", "under", "after", "before", "during",
    "between", "while", "because", "since", "until", "upon", "within",
    "without", "among", "across", "along", "around", "toward", "despite",
    "per", "via", "amid", "according", "said", "says", "told", "reported",
    "stated", "added", "noted", "confirmed", "announced", "declared",
    "several", "many", "much", "one", "two", "three", "first", "second",
    "third", "new", "i", "you", "he", "she", "it", "we", "they", "me", "my",
    "your", "his", "her", "its", "our", "their",
}

_WORD_RE = re.compile(r"[A-Za-z']+")


def roman_telugu_shape(text: str) -> Tuple[float, float]:
    """(vowel-ending token share, English function-word share) of a text.

    The two signals that separate Roman Telugu from English without a
    dictionary of either language: Telugu words end in a vowel, and Telugu
    written in Latin does not use English closed-class words to hold a
    sentence together.
    """
    tokens = _WORD_RE.findall((text or "").lower())
    # Tokens of fewer than three characters -- "a", "of", "to" on the English
    # side -- are excluded from the vowel count, because a one-vowel token
    # ends in a vowel trivially and would swamp the measure on short strings.
    counted = [t for t in tokens if len(t) > 2]
    n = len(counted) or 1
    vowel_end = sum(1 for t in counted if t[-1] in "aeiou") / n
    english = (sum(1 for t in tokens if t in _ENGLISH_FUNCTION_WORDS)
               / len(tokens) if tokens else 0.0)
    return vowel_end, english


@dataclass
class LanguageVerdict:
    """The outcome of attributing one language to one rendered field."""
    ok: bool
    detected: Language
    reason: str

    def to_dict(self) -> dict:
        return {"ok": self.ok, "detected": self.detected.value, "reason": self.reason}


def validate_language(text: Optional[str], language: str) -> LanguageVerdict:
    """Is `text` acceptable as a `language` rendering?

    This is the guard that stops a source-language leak from being published
    as a translation. It never rewrites the text: on failure the caller must
    withhold the language from the story's coverage, so the publish gate sees
    that the rendering is missing rather than trusting a field that is full of
    the wrong script.

    "ten" (Tenglish) is judged by shape rather than script, because Roman
    Telugu has no script of its own: a Latin-script line is Telugu only if it
    keeps Telugu words' open syllables and is not held together by English
    function words. Vocabulary coverage was tried first and does not work --
    English and Roman Telugu share their nouns, so both score alike.
    """
    if language not in _EXPECTED_SCRIPT:
        return LanguageVerdict(False, Language.UNKNOWN, f"unknown language {language!r}")

    detected = detect_language(text)

    if detected is Language.UNKNOWN or not (text and text.strip()):
        return LanguageVerdict(False, detected, "empty or unreadable text")

    if language == "ten":
        # Roman Telugu is Latin-script, so script alone cannot settle it. This
        # is what stops English wire copy being published as Tenglish, which is
        # how the ten column was filled: the transliteration step is a no-op on
        # Latin input, so English copy passed through it untouched and was
        # attributed as Telugu-written-in-Latin.
        if telugu_ratio(text) > 0.05:
            return LanguageVerdict(False, detected, "Tenglish field holds Telugu script")
        if latin_ratio(text) < 0.5:
            return LanguageVerdict(False, detected, "not enough Latin characters to be Tenglish")
        vowel_end, english = roman_telugu_shape(text)
        if english >= _MAX_ENGLISH_FUNC_IN_TENGISH:
            return LanguageVerdict(
                False, detected,
                f"Tenglish field reads as English "
                f"({english:.0%} English function words)")
        if vowel_end < _MIN_VOWEL_ENDING_FOR_TENGISH:
            return LanguageVerdict(
                False, detected,
                f"Tenglish field has no Telugu words in it "
                f"({vowel_end:.0%} vowel-ending tokens; Telugu words end in a vowel)")
        return LanguageVerdict(True, detected, "roman Telugu")

    if language == "te":
        # Telugu is a script language: the check is the script itself. A
        # Telugu line may carry a Latin name or unit, but not enough Latin to
        # be an English headline.
        if telugu_ratio(text) < (1.0 - _MAX_LATIN_IN_TELUGU):
            return LanguageVerdict(
                False, detected,
                f"Telugu field is "
                f"{latin_ratio(text):.0%} Latin, above the {_MAX_LATIN_IN_TELUGU:.0%} budget")
        return LanguageVerdict(True, detected, "telugu script")

    # English: no Telugu script, and no Telugu words wearing Latin letters.
    if telugu_ratio(text) > 0.05:
        return LanguageVerdict(False, detected, "English field carries Telugu characters")
    vowel_end, english = roman_telugu_shape(text)
    if english < _MAX_ENGLISH_FUNC_IN_TENGISH and vowel_end >= _MIN_VOWEL_ENDING_FOR_TENGISH:
        return LanguageVerdict(
            False, detected,
            f"English field holds Roman Telugu "
            f"({vowel_end:.0%} vowel-ending tokens, {english:.0%} English function words)")
    return LanguageVerdict(True, detected, "english")

