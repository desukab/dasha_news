"""Telugu text utilities.

Handles the parts of Telugu NLP that matter for a news product without
pulling in a heavyweight toolkit: script-range detection, syllabic
normalisation, sentence boundary detection that copes with both Telugu danda
(। / ॥) punctuation and Latin full stops, stopword filtering, and transliteration
helpers for Tenglish output.

The Telugu block is U+0C00–U+0C7F. Valid independent-letter codepoints are used
to strip dangling vowel signs produced by careless copy-paste, which is a
frequent cause of garbled mobile rendering.
"""

from __future__ import annotations

import re
import unicodedata
from typing import Iterable, List, Optional

TELUGU_START = 0x0C00
TELUGU_END = 0x0C7F

TELUGU_VOWEL_SIGNS = set("ాిీుూృౄెేైొోౌ")
TELUGU_INDEPENDENT_VOWELS = set("అఆఇఈఉఊఋఌఎఏఐఒఔ")

# Frequent function words. Removing them keeps dedup/cluster similarity focused
# on content words without needing a treebank.
TELUGU_STOPWORDS = {
    "మరియు", "మరి", "మాత్రమే", "అంటే", "అని", "అన్ని", "అన్నీ", "ఇది", "ఇదీ", "అది",
    "అదీ", "ఇవి", "అవి", "అవీ", "అతను", "ఆమె", "వారు", "అతని", "ఆమెకు", "మనం", "మన",
    "మీరు", "నీవు", "నేను", "అదే", "అందుకే", "అందువల్ల", "అంతే", "అక్కడ", "ఇక్కడ",
    "ఎక్కడ", "ఎప్పుడు", "ఎలా", "ఎందుకు", "ఏమిటి", "ఏమి", "ఏ", "కొంత", "కొన్ని", "కొన్ని",
    "అనేక", "అన్ని", "అంత", "అంతా", "అందరూ", "అందరు", "కూడా", "కూడా", "మళ్ళీ",
    "ఇప్పుడు", "ఇప్పటికి", "ఇప్పటివరకు", "ఇదివరకు", "తర్వాత", "తరువాత", "ముందు",
    "ముందుగా", "తరువాత", "ప్రకారం", "గురించి", "గురించి", "కోసం", "కోసమని", "వల్ల",
    "వలన", "ద్వారా", "ద్వార", "తో", "తోపాటు", "పాటు", "సహా", "సహిత", "అయితే", "అయిన",
    "అయినా", "అయినప్పటికీ", "అయినా", "కానీ", "కాని", "కాక", "కాకపోయినా", "లేదు",
    "లేదా", "లేదా", "అంటే", "అనగా", "అంటే", "అంటూ", "అంటూ", "ఉండగా", "ఉండగానే",
    "అయ్యే", "అయ్యే", "అవుతుంది", "అవుతాయి", "అవుతారు", "చేసారు", "చేశారు",
    "చెప్పారు", "చెప్పింది", "తెలిపారు", "తెలిపింది", "ప్రకటించారు", "ప్రకటించింది",
}

LATIN_STOPWORDS = {
    "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "of", "for",
    "with", "by", "from", "is", "are", "was", "were", "be", "been", "being",
    "has", "have", "had", "this", "that", "these", "those", "it", "its", "as",
    "not", "no", "so", "if", "then", "than", "will", "would", "could", "should",
    "he", "she", "they", "we", "you", "i", "his", "her", "their", "our", "your",
    "said", "says", "according", "per", "into", "over", "after", "before",
    "during", "between", "about", "also", "more", "most", "many", "much",
}

# Devanagari danda and common decorative punctuation seen in Telugu copy.
_SENTENCE_SPLIT = re.compile(r"(?<=[।॥.!?।॥])\s+|\n+")
_URL_RE = re.compile(r"https?://\S+|www\.\S+")
_MENTION_RE = re.compile(r"[@#]\S+")
_WHITESPACE_RE = re.compile(r"\s+")

# Python's `re` defines `\b` from `\w`, and `\w` follows `str.isalnum()`.
# Telugu vowel signs (U+0C3E etc.) and the anusvara (U+0C02) report False for
# that, so virtually every Telugu word is riddled with spurious "boundaries"
# and `\bword\b` silently never matches. Match script-aware edges instead.
_WORD_CHAR = "ఀ-౿A-Za-z0-9_’'"
WORD_START = rf"(?<![{_WORD_CHAR}])"
WORD_END = rf"(?![{_WORD_CHAR}])"


def word_boundary(pattern: str) -> str:
    """Wrap an alternation so it only matches at real word edges.

    ``word_boundary("ప్రకారం|according to")`` is the Telugu-safe replacement
    for ``\\b(?:ప్రకారం|according to)\\b``.
    """
    return f"{WORD_START}(?:{pattern}){WORD_END}"


def is_telugu_char(char: str) -> bool:
    return bool(char) and TELUGU_START <= ord(char) <= TELUGU_END


def telugu_ratio(text: Optional[str]) -> float:
    """Fraction of alphabetic characters that belong to the Telugu block."""
    if not text:
        return 0.0
    total = 0
    telugu = 0
    for char in text:
        if char.isalpha():
            total += 1
            if is_telugu_char(char):
                telugu += 1
    return telugu / total if total else 0.0


def latin_ratio(text: Optional[str]) -> float:
    if not text:
        return 0.0
    total = sum(1 for ch in text if ch.isalpha())
    latin = sum(1 for ch in text if ch.isascii() and ch.isalpha())
    return latin / total if total else 0.0


def normalize_text(text: Optional[str]) -> str:
    """NFKC + URL/mention stripping + whitespace collapse. Does not lowercase."""
    if not text:
        return ""
    cleaned = unicodedata.normalize("NFKC", text)
    cleaned = _URL_RE.sub(" ", cleaned)
    cleaned = _MENTION_RE.sub(" ", cleaned)
    cleaned = _WHITESPACE_RE.sub(" ", cleaned)
    return cleaned.strip()


def split_sentences(text: Optional[str]) -> List[str]:
    """Sentence segmentation that works for Telugu and English alike.

    Telugu copy frequently omits the Latin full stop and uses । or newlines;
    abbreviations such as "డా." would otherwise create spurious boundaries, so
    a split is only accepted when the following token starts a new sentence.
    """
    if not text:
        return []
    text = normalize_text(text)
    parts = [part.strip() for part in _SENTENCE_SPLIT.split(text) if part.strip()]
    sentences: List[str] = []
    for part in parts:
        if sentences and _is_continuation(sentences[-1], part):
            sentences[-1] = f"{sentences[-1]} {part}"
        else:
            sentences.append(part)
    return sentences


_ABBREVIATIONS = {
    "డా", "డా.", "శ్రీ", "శ్రీ.", "ఎస్", "ఎం", "ఏపీ", "టీఎస్", "సి", "ఎంపీ",
    "ఎమ్మెల్యే", "ఐఏఎస్", "ఐపీఎస్", "జిహెచ్ఎంసి", "వై", "ఎంఎల్ఏ", "ఎల్లో",
    "vs", "dr", "mr", "mrs", "st", "jr", "sr", "no", "approx",
}


def _is_continuation(previous: str, current: str) -> bool:
    previous_stripped = previous.rstrip()
    if previous_stripped.endswith((".", "।")):
        token_before_dot = previous_stripped.rstrip(".।")
        if token_before_dot in _ABBREVIATIONS or len(token_before_dot) <= 1:
            return True
    # A single lowercase-ish fragment is not a new sentence.
    first_char = current[:1]
    if first_char and first_char.isalpha() and first_char.islower():
        return True
    # A new sentence starting with a Telugu consonant cluster is normal; a
    # fragment starting with a lowercase Latin letter is not.
    return False


def content_tokens(text: Optional[str], min_len: int = 2) -> List[str]:
    """Content-word tokens with stopwords removed, script-agnostic."""
    if not text:
        return []
    text = normalize_text(text).lower()
    raw = re.findall(r"[ఀ-౿a-z0-9]+", text)
    stopwords = TELUGU_STOPWORDS | LATIN_STOPWORDS
    return [tok for tok in raw if len(tok) >= min_len and tok not in stopwords]


def telugu_tokens(text: Optional[str], min_len: int = 2) -> List[str]:
    if not text:
        return []
    text = normalize_text(text)
    raw = re.findall(r"[ఀ-౿]+", text)
    return [tok for tok in raw if len(tok) >= min_len and tok not in TELUGU_STOPWORDS]


def latin_tokens(text: Optional[str], min_len: int = 2) -> List[str]:
    if not text:
        return []
    text = normalize_text(text).lower()
    raw = re.findall(r"[a-z0-9]+", text)
    return [tok for tok in raw if len(tok) >= min_len and tok not in LATIN_STOPWORDS]


def char_ngrams(text: Optional[str], n: int = 4) -> List[str]:
    """Character n-grams -- the script-agnostic signal used for cross-language
    near-duplicate detection, since Telugu words rarely tokenise identically
    across two publishers' transliterations."""
    if not text:
        return []
    cleaned = normalize_text(text).lower().replace(" ", "_")
    if len(cleaned) < n:
        return [cleaned] if cleaned else []
    return [cleaned[i : i + n] for i in range(len(cleaned) - n + 1)]


def trigram_set(text: Optional[str]) -> set[str]:
    return set(char_ngrams(text, 3))


_TELUGU_TO_LATIN = {
    "అ": "a", "ఆ": "aa", "ఇ": "i", "ఈ": "ee", "ఉ": "u", "ఊ": "oo", "ఋ": "ru",
    "ఎ": "e", "ఏ": "ee", "ఐ": "ai", "ఒ": "o", "ఓ": "oo", "ఔ": "au",
    "క": "k", "ఖ": "kh", "గ": "g", "ఘ": "gh", "ఙ": "ng",
    "చ": "ch", "ఛ": "chh", "జ": "j", "ఝ": "jh", "ఞ": "ny",
    "ట": "t", "ఠ": "th", "డ": "d", "ఢ": "dh", "ణ": "n",
    "త": "t", "థ": "th", "ద": "d", "ధ": "dh", "న": "n",
    "ప": "p", "ఫ": "ph", "బ": "b", "భ": "bh", "మ": "m",
    "య": "y", "ర": "r", "ల": "l", "వ": "v", "శ": "sh", "ష": "sh",
    "స": "s", "హ": "h", "ళ": "l", "క్ష": "ksh", "ఱ": "r",
    "ా": "a", "ి": "i", "ీ": "ee", "ు": "u", "ూ": "oo",
    "ె": "e", "ే": "e", "ై": "ai", "ొ": "o", "ో": "o", "ౌ": "au",
    "ం": "n", "ః": "h", "్": "",
}


def transliterate_to_tenglish(text: Optional[str]) -> str:
    """Approximate Telugu -> Latin transliteration for Tenglish display.

    Deliberately lossy and human-familiar rather than ISO-15919 precise: the
    target readership reads Telugu words written in Latin script the way they
    are typed in chat, e.g. "హైదరాబాద్" -> "Hyderabad"-ish.
    """
    if not text:
        return ""
    out: List[str] = []
    for char in text:
        mapped = _TELUGU_TO_LATIN.get(char)
        if mapped is None:
            out.append(char if char.isascii() or not is_telugu_char(char) else "")
        else:
            out.append(mapped)
    result = "".join(out)
    result = re.sub(r"(.)\1{2,}", r"\1\1", result)  # collapse triplets (vowel signs)
    return _WHITESPACE_RE.sub(" ", result).strip()


def dedupe_preserving_order(items: Iterable[str]) -> List[str]:
    seen: set[str] = set()
    result: List[str] = []
    for item in items:
        key = item.strip().lower()
        if key and key not in seen:
            seen.add(key)
            result.append(item)
    return result


def word_count(text: Optional[str]) -> int:
    if not text:
        return 0
    return len(normalize_text(text).split())


def truncate_sentences(text: Optional[str], max_sentences: int) -> str:
    sentences = split_sentences(text)
    return " ".join(sentences[:max_sentences])


def strip_dangling_vowel_signs(text: Optional[str]) -> str:
    """Remove vowel signs that have no consonant to attach to.

    Occurs when text is sliced mid-word (common in RSS summaries); the result
    renders as a stray combining mark on mobile devices.
    """
    if not text:
        return ""
    out: List[str] = []
    previous_was_consonant = False
    for char in text:
        if char in TELUGU_VOWEL_SIGNS and not previous_was_consonant:
            if char in TELUGU_INDEPENDENT_VOWELS:  # unreachable, kept for clarity
                out.append(char)
            continue
        out.append(char)
        previous_was_consonant = is_telugu_char(char) and char not in TELUGU_VOWEL_SIGNS
    return "".join(out)
