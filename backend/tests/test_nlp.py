"""Telugu text handling: script detection, sentence splitting, Tenglish."""

from __future__ import annotations

from newsroom.nlp.language import Language, detect_language
from newsroom.nlp.telugu import (
    char_ngrams,
    content_tokens,
    is_telugu_char,
    latin_ratio,
    normalize_text,
    split_sentences,
    telugu_ratio,
    transliterate_to_tenglish,
    word_count,
)


def test_telugu_char_detection():
    assert is_telugu_char("అ") is True
    assert is_telugu_char("A") is False
    assert is_telugu_char("ి") is True  # vowel sign is still Telugu


def test_ratios():
    assert telugu_ratio("తెలంగాణ ముఖ్యమంత్రి") > 0.9
    assert latin_ratio("తెలంగాణ ముఖ్యమంత్రి") < 0.1
    mixed = "తెలంగాణ CM రేవంత్ రెడ్డి"
    assert 0.0 < telugu_ratio(mixed) < 1.0
    assert telugu_ratio("") == 0.0
    assert telugu_ratio(None) == 0.0


def test_detect_language():
    assert detect_language("తెలంగాణ ప్రభుత్వం ప్రకటన") == Language.TELUGU
    assert detect_language("The government announced a new policy for the state") == Language.ENGLISH
    assert detect_language("Revanth Reddy garu new scheme announce chesaru") == Language.TENGLISH
    assert detect_language("") == Language.UNKNOWN
    assert detect_language(None) == Language.UNKNOWN


def test_sentence_split_danda():
    text = "ముఖ్యమంత్రి ప్రకటించారు। ఇది రెండవ వాక్యం। మూడవది."
    parts = split_sentences(text)
    assert len(parts) == 3
    assert parts[0].startswith("ముఖ్యమంత్రి")
    assert parts[1].startswith("ఇది")


def test_sentence_split_english():
    text = "First sentence. Second one! And the third?"
    assert len(split_sentences(text)) == 3


def test_sentence_split_preserves_decimals_and_urls():
    # A full stop inside a number or URL must not become a sentence boundary.
    parts = split_sentences("The rate is 3.5 percent. Visit example.com for more.")
    assert len(parts) == 2
    assert "3.5" in parts[0]
    assert "example.com" in parts[1]


def test_normalize_and_tokens():
    messy = "అన్ని\tరకాల\n\nఖాళీలు"
    assert "\n" not in normalize_text(messy)
    assert "ఖాళీలు" in content_tokens(messy)


def test_ngrams_are_contiguous():
    grams = char_ngrams("abcdef", n=3)
    assert grams == ["abc", "bcd", "cde", "def"]


def test_transliteration_to_tenglish():
    out = transliterate_to_tenglish("తెలంగాణ")
    assert out
    assert all(not is_telugu_char(c) for c in out)


def test_word_count_and_empties():
    assert word_count("one two three") == 3
    assert word_count("") == 0
    assert word_count(None) == 0
    assert split_sentences(None) == []
