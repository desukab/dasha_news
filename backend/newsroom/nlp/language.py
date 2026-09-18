"""Language detection (Telugu / English / Tenglish) without a model."""

from __future__ import annotations

from enum import Enum

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
