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
    "స": "s", "హ": "h", "ళ": "l", "ఱ": "r",
    "ా": "a", "ి": "i", "ీ": "ee", "ు": "u", "ూ": "oo",
    "ె": "e", "ే": "e", "ై": "ai", "ొ": "o", "ో": "o", "ౌ": "au",
    "ం": "n", "ః": "h", "్": "",
}

# Consonant letters. A bare consonant letter carries an inherent "a" unless a
# vowel sign follows or a virama (్) explicitly kills it -- that is the whole
# of why "ప్రభుత్వం" used to come out as "prbhutvn" instead of "prabhutvam".
_TELUGU_CONSONANTS = set("కఖగఘఙచఛజఝఞటఠడఢణతథదధనపఫబభమయరలవశషసహళఱ")

_VIRAMA = "్"

_ANUSVARA = "ం"

# Labials: the anusvara before one of these is an "m", not an "n" -- "అంబ"
# is "amba", and Roman Telugu is typed the same way.
_LABIALS = set("పఫబభమయవ")

# క్ష is a conjunct the per-character loop below would otherwise render as
# "k" + virama + "sh"; it is common enough to spell as one unit.
_KSHA = ("క", _VIRAMA, "ష")


def transliterate_to_tenglish(text: Optional[str]) -> str:
    """Approximate Telugu -> Latin transliteration for Tenglish display.

    Deliberately lossy and human-familiar rather than ISO-15919 precise: the
    target readership reads Telugu words written in Latin script the way they
    are typed in chat, e.g. "హైదరాబాద్" -> "Hyderabad"-ish.

    The one rule that matters more than any other: a Telugu consonant letter
    with no vowel sign after it is pronounced with an inherent "a". Emitting
    the bare consonant turns every word into a consonant skeleton ("prbhutvn")
    that no Telugu reader can sound out, which is the mechanical
    transliteration this function exists to avoid.
    """
    if not text:
        return ""
    # Telugu web copy is larded with zero-width joiners and combining marks
    # that would otherwise reach the output as invisible garbage.
    chars = [c for c in text if unicodedata.category(c)[0] != "C"]
    out: List[str] = []
    n = len(chars)
    i = 0
    while i < n:
        char = chars[i]

        if tuple(chars[i : i + 3]) == _KSHA:
            out.append("ksh")
            i += 3
            continue

        mapped = _TELUGU_TO_LATIN.get(char)
        if mapped is None:
            # Unmapped Telugu (a rare sign or a numeral) has no Latin face; drop
            # it rather than emitting the original glyph into a Roman string.
            if is_telugu_char(char):
                i += 1
                continue
            out.append(char)
        elif char == _VIRAMA:
            # The virama silences the inherent vowel of the consonant before
            # it, which was already emitted bare. Contributes nothing itself.
            pass
        elif char == _ANUSVARA:
            nxt = chars[i + 1] if i + 1 < n else ""
            prev = chars[i - 1] if i > 0 else ""
            # At the end of a word, or before a labial, readers write "m":
            # "ప్రభుత్వం" is "prabhutvam", "అంబ" is "amba".
            if nxt == "" or not (is_telugu_char(nxt) or nxt.isalpha()) or nxt in _LABIALS:
                out.append("m")
            else:
                out.append("n")
        elif char in _TELUGU_CONSONANTS:
            nxt = chars[i + 1] if i + 1 < n else ""
            # The consonant is bare when a vowel sign supplies its vowel, or
            # when a virama after it explicitly silences the inherent "a". A
            # consonant that *follows* a virama is the live half of a conjunct
            # and keeps its vowel, which is why "ప్ర" is "pra" and "త్వ" is
            # "tva" -- one vowel per cluster, on its last consonant.
            if nxt in TELUGU_VOWEL_SIGNS or nxt == _VIRAMA:
                out.append(mapped)
            else:
                out.append(mapped + "a")
        else:
            out.append(mapped)
        i += 1

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


# ---------------------------------------------------------------------------
# Tenglish: Telugu text in the Roman alphabet
# ---------------------------------------------------------------------------

# Names a Telugu reader writes in one fixed Roman form. Transliteration is a
# syllable-by-syllable process and cannot know that "హైదరాబాద్" is *Hyderabad*
# and not "haidarabad", or that "కేసీఆర్" is *KCR* and not "keseeaar": both are
# single words in Telugu script and both come out of the letter loop as
# themselves. A reader who writes Tenglish writes the established spelling, so
# the lexicon is applied before transliteration and only the rest of the
# sentence is romanised. Scope is deliberately what a Telangana paper writes
# about -- the state's places, its parties, its politicians and the acronyms
# its institutions go by.
_NAMED_ENTITIES: dict[str, str] = {
    # Telangana: state, capital, districts and the towns that lead the wire.
    "తెలంగాణా": "Telangana", "తెలంగాణ": "Telangana",
    "హైదరాబాదు": "Hyderabad", "హైదరాబాద్": "Hyderabad",
    "హైదరాబాద": "Hyderabad",
    "సికింద్రాబాదు": "Secunderabad", "సికింద్రాబాద్": "Secunderabad",
    "హుస్సేన్‌సాగర్": "Hussain Sagar", "హుస్సేన్సాగర్": "Hussain Sagar",
    "చార్మినార్": "Charminar", "గోల్కొండ": "Golconda",
    "వరంగల్లు": "Warangal", "వరంగల్": "Warangal", "హనుమకొండ": "Hanamkonda",
    "నిజామాబాదు": "Nizamabad", "నిజామాబాద్": "Nizamabad",
    "ఖమ్మం": "Khammam", "కరీంనగర్": "Karimnagar", "కరీంనగరం": "Karimnagar",
    "మహబూబ్‌నగర్": "Mahabubnagar", "మహబూబ్నగర్": "Mahabubnagar",
    "మెదక్": "Medak", "నల్గొండ": "Nalgonda", "నల్గొండజిల్లా": "Nalgonda",
    "ఆదిలాబాద్": "Adilabad", "రంగారెడ్డి": "Ranga Reddy",
    "మేడ్చల్": "Medchal", "వికారాబాద్": "Vikarabad",
    "జగిత్యాల": "Jagtial", "పెద్దపల్లి": "Peddapalli",
    "సూర్యాపేట": "Suryapet", "కామారెడ్డి": "Kamareddy",
    "భువనగిరి": "Bhuvanagiri", "సిరిసిల్ల": "Sircilla",
    "కొత్తగూడెం": "Kothagudem", "గద్వాల్": "Gadwal",
    "నారాయణపేట": "Narayanpet", "ములుగు": "Mulugu",
    "సంగారెడ్డి": "Sangareddy", "సంగారెడ్డిజిల్లా": "Sangareddy",
    "సిద్దిపేట": "Siddipet", "సిద్ధిపేట": "Siddipet",
    "మెదక్‌జిల్లా": "Medak", "నిజామాబాద్జిల్లా": "Nizamabad",
    # Rivers and hills that a district story is filed from.
    "గోదావరి": "Godavari", "కృష్ణా": "Krishna", "మూసీ": "Musi",
    "తుంగభద్ర": "Tungabhadra", "నాగార్జునసాగర్": "Nagarjuna Sagar",
    "శ్రీశైలం": "Srisailam", "భద్రాచలం": "Bhadrachalam",
    # Parties: their Telugu names are long enough that a reader abbreviates.
    "భారతీయజనతాపార్టీ": "BJP", "బీజేపీ": "BJP",
    "భారతీయ జనతా పార్టీ": "BJP", "బీజేపీకి": "BJP",
    "కాంగ్రెస్పార్టీ": "Congress", "కాంగ్రెస్": "Congress",
    "కాంగ్రెస్‌పార్టీ": "Congress",
    "తెలంగాణరాష్ట్రసమితి": "BRS", "తెలంగాణ రాష్ట్ర సమితి": "BRS",
    "బీఆర్ఎస్": "BRS", "బీఆర్‌ఎస్": "BRS",
    "టీఆర్ఎస్": "TRS", "టీడీపీ": "TDP", "తెలుగుదేశంపార్టీ": "TDP",
    "వైసీపీ": "YCP", "వైఎస్ఆర్": "YSR", "వైఎస్ఆర్కాంగ్రెస్": "YSR Congress",
    "జనసేన": "Jana Sena", "జనసేనపార్టీ": "Jana Sena",
    "ఎంఐఎం": "MIM", "సిపిఎం": "CPM", "సిపిఐ": "CPI", "ఎఎంసీ": "AIMIM",
    # Politicians, by the names they are filed under.
    "కేసీఆర్": "KCR", "కేసీఆర్‌": "KCR",
    "కల్వకుంట్లచంద్రశేఖరరావు": "K. Chandrasekhar Rao",
    "కల్వకుంట్ల చంద్రశేఖర్ రావు": "K. Chandrasekhar Rao",
    "చంద్రశేఖరరావు": "Chandrasekhar Rao",
    "కేటీఆర్": "KTR", "కేటీఆర్‌": "KTR",
    "కేటీఆర్రామారావు": "K. T. Rama Rao",
    "హరీష్రావు": "Harish Rao", "హరీష్ రావు": "Harish Rao",
    "రేవంత్రెడ్డి": "Revanth Reddy", "రేవంత్ రెడ్డి": "Revanth Reddy",
    "అనుములరేవంత్రెడ్డి": "A. Revanth Reddy",
    "ముఖ్యమంత్రిరేవంత్రెడ్డి": "CM Revanth Reddy",
    "జగన్": "Jagan", "జగన్మోహన్రెడ్డి": "Jagan Mohan Reddy",
    "చంద్రబాబు": "Chandrababu", "నారాచంద్రబాబు": "N. Chandrababu",
    "పవన్కళ్యాణ్": "Pawan Kalyan", "పవన్ కళ్యాణ్": "Pawan Kalyan",
    "లోకేష్": "Lokesh", "నారాలోకేష్": "Nara Lokesh",
    "అసదుద్దీన్ఒవైసీ": "Asaduddin Owaisi",
    "అసదుద్దీన్ ఒవైసీ": "Asaduddin Owaisi",
    # Institutions, by the initials every report uses.
    "జీహెచ్ఎంసీ": "GHMC", "జీహెచ్ఎంసీకి": "GHMC",
    "ఆర్టీసీ": "RTC", "టీఎస్ఆర్టీసీ": "TSRTC",
    "హైకోర్టు": "High Court", "సుప్రీంకోర్టు": "Supreme Court",
    "కోర్టు": "Court", "జైలు": "Jail", "జైలుకు": "Jail",
    "శాసనసభ": "Assembly", "పార్లమెంట్": "Parliament",
    "ఎన్నికలు": "Elections", "ఎన్నికలకు": "Elections",
    "పార్టీ": "party", "పార్టీలు": "parties",
    "మృతి": "mrithi", "మృతిచెందారు": "died", "మరణించారు": "passed away",
    "నియోజకవర్గం": "Constituency",
    "పంచాయతీ": "Panchayat", "పంచాయతి": "Panchayat",
    "మున్సిపాలిటీ": "Municipality", "మున్సిపల్": "Municipality",
    "ఎస్పీ": "SP", "డీఎస్పీ": "DSP", "ఎస్ఐ": "SI", "సిఐ": "CI",
    "ఎంపీ": "MP", "ఎమ్మెల్యే": "MLA", "ఎమ్మెల్సీ": "MLC",
    "పోలీసులు": "Police", "పోలీస్": "Police", "పోలీసు": "Police",
    "అరెస్ట్": "arrest", "వారంట్": "warrant", "కేసు": "case",
    "పోలీస్‌స్టేషన్": "Police Station", "పోలీస్స్టేషన్": "Police Station",
    "ప్రభుత్వం": "Government", "ప్రభుత్వము": "Government",
    "ముఖ్యమంత్రి": "CM", "మంత్రి": "Minister",
    "అధికారులు": "Officials", "అధికారి": "Official",
    "ఇంజనీర్లు": "Engineers", "విద్యార్థులు": "Students",
    "రైతులు": "Farmers", "కార్మికులు": "Workers",
    "విద్యుత్": "Power", "నీటిపారుదల": "Irrigation", "రాహిత్యం": "Health",
    # Money, measures and the calendar: numbers are where a reader most needs
    # the familiar word, because the numeral itself never transliterates.
    "రూపాయలు": "rupees", "రూపాయలను": "rupees", "రూపాయలుగా": "rupees",
    "రూ": "Rs",
    "రూపాయి": "rupee", "లక్షలు": "lakh", "లక్ష": "lakh",
    "కోట్లు": "crore", "కోటి": "crore", "కోట్లరూపాయలు": "crore rupees",
    "వేలం": "auction", "వేలు": "thousand", "వేల": "thousand",
    "శాతం": "percent", "శాతాలు": "percent",
    "కిలోమీటర్లు": "km", "మీటర్లు": "metres",
    "ఎకరాలు": "acres", "టన్నులు": "tonnes",
    "జనవరి": "January", "ఫిబ్రవరి": "February", "మార్చి": "March",
    "ఏప్రిల్": "April", "మే": "May", "జూన్": "June", "జులై": "July",
    "ఆగస్టు": "August", "సెప్టెంబర్": "September", "అక్టోబర్": "October",
    "నవంబర్": "November", "డిసెంబర్": "December",
    "సోమవారం": "Monday", "మంగళవారం": "Tuesday", "బుధవారం": "Wednesday",
    "గురువారం": "Thursday", "శుక్రవారం": "Friday",
    "శనివారం": "Saturday", "ఆదివారం": "Sunday",
    "నేటి": "today", "నిన్న": "yesterday", "రేపు": "tomorrow",
    "ఈరోజు": "today", "నెల": "month", "సంవత్సరం": "year",
    "వారం": "week", "గంటలు": "hours", "నిమిషాలు": "minutes",
}

# Telugu case endings a name carries inside a sentence: "హైదరాబాదులో" is
# Hyderabad-in, "హైదరాబాదుకు" is Hyderabad-to. Matched on their own so the
# name keeps the Roman spelling a reader writes and only the ending romanises
# -- "Hyderabad lo", not "Hyderabadlo".
_TELUGU_ENDINGS = (
    "లోని", "లోను", "లోపల", "లో", "కే", "కు", "ని", "నె", "ను",
    "పైన", "పై", "తో", "చేత", "వలన", "వలె", "వంటి", "కంటే",
    "గురించి", "ద్వారా", "బయట", "లు", "న", "ఆ",
)

_TELUGU_ENDINGS_RE = "|".join(sorted(_TELUGU_ENDINGS, key=len, reverse=True))

# Names are matched against a whitespace-stripped copy of the text (see
# [_replace_named_entities]) because outlets write the same name joined
# ("సుప్రీంకోర్టు") and split ("సుప్రీం కోర్టు"), and the lexicon can only
# list one spelling of each. A name's internal spacing is not information --
# the match is replaced as a unit -- so the keys are stored joined too.
_ENTITY_KEYS = {"".join(key.split()): value for key, value in _NAMED_ENTITIES.items()}
# The leading word-boundary guard is applied in [_replace_named_entities],
# against the source's own spacing rather than the compact copy the pattern
# sees -- otherwise two names the source kept apart would read as one word and
# the second would be rejected as mid-word.
_ENTITY_RE = re.compile(
    r"("
    + "|".join(sorted(_ENTITY_KEYS, key=len, reverse=True))
    + r")(?:(" + _TELUGU_ENDINGS_RE + r")(?![ఀ-౿]))?",
    re.UNICODE,
)
_ZWNJ_RE = re.compile("‌")


def _replace_named_entities(text: str) -> str:
    """Swap in the Roman forms a reader writes, leaving the sentence to romanise."""
    if not text:
        return text
    # ZWNJs between a name and its ending are typography, not speech; the char
    # loop drops them but the pattern has to see the letters adjacent.
    source = _ZWNJ_RE.sub("", text)

    # The compact copy the pattern sees, with the original position of every
    # surviving character so the replacement can be stitched back onto the
    # source's own spacing.
    chars: List[str] = []
    origin: List[int] = []
    for position, char in enumerate(source):
        if not char.isspace():
            chars.append(char)
            origin.append(position)
    compact = "".join(chars)
    if not compact:
        return source

    def substitute(match: "re.Match[str]") -> str:
        ending = match.group(2)
        return _ENTITY_KEYS[match.group(1)] + (" " + ending if ending else "")

    out: List[str] = []
    copied = 0
    for match in _ENTITY_RE.finditer(compact):
        begin = origin[match.start()]
        # A name is only a name where it starts a word. The compact copy would
        # let it match mid-word, which turns a longer compound into an English
        # name plus a leftover stump, so the guard uses the source instead: a
        # name preceded by a letter is part of that word and is left alone.
        if begin and source[begin - 1].isalnum():
            continue
        out.append(source[copied:begin])
        out.append(substitute(match))
        copied = origin[match.end() - 1] + 1
    out.append(source[copied:])
    return "".join(out)


def to_tenglish(text: Optional[str]) -> str:
    """Telugu script written the way a Telugu reader types it.

    Roman Telugu with the names readers actually use: *Hyderabad*, *KCR*,
    *BRS*, *Warangal*. Anything mechanical transliteration cannot spell is
    fixed by [_NAMED_ENTITIES] first, then the rest of the sentence is
    romanised by [transliterate_to_tenglish].

    Returns an empty string when the source is not Telugu script: Tenglish is a
    *reading* of Telugu, so an English sentence has no Roman-Telugu form and
    serving it as one is how English reached this column before. The caller
    withholds the field.
    """
    if not text:
        return ""
    if telugu_ratio(text) < 0.3:
        return ""
    return transliterate_to_tenglish(_replace_named_entities(text))
