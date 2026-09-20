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


def test_transliteration_keeps_the_inherent_vowel():
    # A Telugu consonant letter with no vowel sign after it carries an inherent
    # "a". Emitting the bare consonant rendered every word as an unspeakable
    # consonant skeleton, which is the mechanical transliteration the reader
    # must never be shown.
    assert transliterate_to_tenglish("ప్రభుత్వం") == "prabhutvam"
    assert transliterate_to_tenglish("మరి") == "mari"
    assert transliterate_to_tenglish("కథ") == "katha"


def test_transliteration_virama_silences_the_vowel():
    # బాద్ is "bad" -- the virama kills the inherent vowel, it does not add one.
    assert transliterate_to_tenglish("హైదరాబాద్") == "haidarabad"


def test_transliteration_anusvara_reads_as_m():
    # Before a labial and at a word's end, Roman Telugu writes "m": "అంబ" is
    # "amba", "మనం" is "manam".
    assert transliterate_to_tenglish("అంబ") == "amba"
    assert transliterate_to_tenglish("మనం") == "manam"


def test_transliteration_ksha_is_one_unit():
    assert "ksh" in transliterate_to_tenglish("క్షేత్రం")


def test_transliteration_strips_zero_width_characters():
    # Web copy carries zero-width joiners; they must not survive into a Roman
    # string, where they render as invisible garbage.
    out = transliterate_to_tenglish("హైదరాబాద్‌లో")
    assert "‌" not in out and "‍" not in out
    # The locative postposition fuses onto the stem, as it does in Telugu.
    assert out == "haidarabadlo"


def test_transliteration_passes_latin_through_untouched():
    # A name or abbreviation inside Telugu copy keeps its Latin letters.
    out = transliterate_to_tenglish("RTC బస్సులు")
    assert out.startswith("RTC ")


def test_word_count_and_empties():
    assert word_count("one two three") == 3
    assert word_count("") == 0
    assert word_count(None) == 0
    assert split_sentences(None) == []


# ---------------------------------------------------------------------------
# Language quality gate
# ---------------------------------------------------------------------------

from newsroom.nlp.language import validate_language  # noqa: E402


def test_language_gate_accepts_real_telugu_script():
    verdict = validate_language(
        "హైదరాబాద్‌లో భారీ వర్షాలతో పలు ప్రాంతాల్లో ట్రాఫిక్‌కు అంతరాయం", "te")
    assert verdict.ok, verdict.reason


def test_language_gate_accepts_telugu_with_a_latin_name():
    # "RTC" and "BRS" inside a Telugu sentence are correct Telugu, not a leak.
    verdict = validate_language(
        "హైదరాబాద్‌లో భారీ వర్షాలతో RTC బస్సులకు అంతరాయం", "te")
    assert verdict.ok, verdict.reason


def test_language_gate_rejects_english_in_the_telugu_column():
    verdict = validate_language("Heavy rain disrupted traffic in Hyderabad.", "te")
    assert not verdict.ok
    assert "Latin" in verdict.reason


def test_language_gate_rejects_transliteration_as_telugu():
    # Telugu written in Latin letters is not Telugu script.
    verdict = validate_language(
        "haidrabad lo bhaari varshalatho palu praanthallo traffic ki antharaayam", "te")
    assert not verdict.ok


def test_language_gate_accepts_natural_tenglish():
    verdict = validate_language(
        "Hyderabad lo bhaari varshalu.. palu areas lo traffic slow ayyindi.", "ten")
    assert verdict.ok, verdict.reason


def test_language_gate_accepts_transliterated_telugu_as_tenglish():
    # What the fixed transliterator emits is genuine Roman Telugu.
    verdict = validate_language(
        "haidarabadalo bharee varashalato palu parantalalo taraphikaku antarayam", "ten")
    assert verdict.ok, verdict.reason


def test_language_gate_rejects_english_as_tenglish():
    # This is the leak that filled the ten column: transliteration is a no-op
    # on Latin input, so English copy was published as Tenglish.
    verdict = validate_language(
        "Heavy rain in Hyderabad disrupted traffic across several areas.", "ten")
    assert not verdict.ok
    assert "English" in verdict.reason


def test_language_gate_rejects_telugu_script_as_tenglish():
    verdict = validate_language(
        "హైదరాబాద్‌లో భారీ వర్షాలతో ట్రాఫిక్‌కు అంతరాయం", "ten")
    assert not verdict.ok
    assert "Telugu script" in verdict.reason


def test_language_gate_accepts_plain_english():
    verdict = validate_language(
        "Heavy rain in Hyderabad disrupted traffic across several areas.", "en")
    assert verdict.ok, verdict.reason


def test_language_gate_rejects_telugu_in_the_english_column():
    verdict = validate_language(
        "హైదరాబాద్‌లో భారీ వర్షాలతో ట్రాఫిక్‌కు అంతరాయం", "en")
    assert not verdict.ok


def test_language_gate_rejects_empty_and_unknown_languages():
    assert not validate_language("", "te").ok
    assert not validate_language(None, "en").ok
    assert not validate_language("   ", "ten").ok
    assert not validate_language("anything", "klingon").ok


def test_language_gate_does_not_flag_english_as_its_own_leak():
    # An English sentence scores high on English function words and low on
    # vowel-ending tokens; it must not be mistaken for Roman Telugu.
    for sentence in (
        "The state government announced a new scheme for farmers in the district.",
        "Police arrested three people in connection with the robbery on Monday night.",
        "According to the representatives, the committee conducted a physical survey.",
    ):
        verdict = validate_language(sentence, "en")
        assert verdict.ok, f"{sentence!r}: {verdict.reason}"


def test_language_gate_verdict_is_serialisable():
    verdict = validate_language("తెలంగాణ ముఖ్యమంత్రి", "te")
    assert verdict.to_dict() == {
        "ok": True, "detected": "te", "reason": "telugu script"}
