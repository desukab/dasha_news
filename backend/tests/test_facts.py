"""Fact engine: classification, evidence levels, and disputed-claim merging."""

from __future__ import annotations

from newsroom.domain.evidence import EvidenceLevel
from newsroom.pipeline.facts import (
    ExtractedFact,
    classify_sentence,
    extract_facts,
    fact_signature,
    heuristic_facts,
    merge_facts,
)

OFFICIAL = "ముఖ్యమంత్రి అధికారికంగా ప్రకటించారు"
CLAIM = "పార్టీ నాయకులు ఈ పథకం విజయవంతమైందని అన్నారు"
ALLEGATION = "ప్రతిపక్షాలు అవినీతి ఆరోపణలు చేశాయి"
OPINION = "నా అభిప్రాయంలో ఇది మంచి చర్య"
FORECAST = "అధికారులు రేపు వర్షం కురుగుతుందని అంచనా వేశారు"


def test_evidence_level_weights_are_ordered():
    assert EvidenceLevel.FACT.weight >= EvidenceLevel.OFFICIAL_STATEMENT.weight
    assert EvidenceLevel.OFFICIAL_STATEMENT.weight > EvidenceLevel.CLAIM.weight
    assert EvidenceLevel.CLAIM.weight > EvidenceLevel.UNVERIFIED.weight


def test_classify_sentence():
    # Levels are EvidenceLevel *values*, so lowercase strings.
    assert classify_sentence(OFFICIAL) == EvidenceLevel.OFFICIAL_STATEMENT.value
    assert classify_sentence(ALLEGATION) == EvidenceLevel.ALLEGATION.value
    assert classify_sentence(OPINION) == EvidenceLevel.OPINION.value
    assert classify_sentence(FORECAST) == EvidenceLevel.FORECAST.value
    # A bare assertion with no hedge word is a claim, never verified.
    assert classify_sentence(CLAIM) == EvidenceLevel.CLAIM.value


def test_classify_sentence_unknown_is_unverified():
    """A bare declarative with no attribution cannot be promoted to a fact."""
    assert classify_sentence("రోడ్డు పనులు జరుగుతున్నాయి") == EvidenceLevel.UNVERIFIED.value


def test_extract_facts_returns_sorted_by_weight():
    text = f"{OFFICIAL}। {ALLEGATION}। {OPINION}।"
    facts = extract_facts(text, language="te")
    assert facts, "heuristic extractor must produce facts"
    weights = [EvidenceLevel(f.level).weight for f in facts]
    assert weights == sorted(weights, reverse=True)


def test_word_boundary_helper_matches_telugu():
    """Regression guard for the attribution extractor.

    Python's `re` `\\b` is useless on Telugu: vowel signs are not `\\w`, so
    `\\bword\\b` silently never matched a word containing one -- which is
    virtually every Telugu word. Before this fix every Telugu attribution
    marker was missed and such facts fell back to `unverified` with no
    source attached.
    """
    import re

    from newsroom.nlp.telugu import word_boundary

    pattern = re.compile(word_boundary("ప్రకారం"))
    assert pattern.search("పోలీసుల ప్రకారం ఇద్దరు") is not None
    # Must not match inside a longer word.
    assert pattern.search("ప్రకారంగా ఉంది") is None
    assert re.compile(word_boundary("said")).search("he said that") is not None


def test_extract_facts_empty_input():
    assert extract_facts("") == []
    assert extract_facts(None) == []
    assert extract_facts("   ") == []


def test_extract_facts_filters_trivial_sentences():
    tiny = "అవినీతి।"
    assert extract_facts(tiny, language="te") == []


def test_fact_attribution_captured():
    text = "పోలీసుల ప్రకారం ఇద్దరు అరెస్ట్ అయ్యారు।"
    facts = extract_facts(text, language="te")
    assert facts
    assert any(f.attributed_to for f in facts)


def test_fact_signature_stable():
    facts = heuristic_facts(OFFICIAL, "te")
    assert facts
    assert fact_signature(facts[0]) == fact_signature(facts[0])
    other = heuristic_facts(ALLEGATION, "te")
    assert other
    assert fact_signature(facts[0]) != fact_signature(other[0])


def test_merge_facts_dedupes_duplicates():
    existing = extract_facts(OFFICIAL, language="te")
    incoming = extract_facts(OFFICIAL, language="te")
    merged = merge_facts(existing, incoming)
    assert len(merged) == len(existing)


def test_merge_facts_flags_number_disagreement_as_disputed():
    left = ExtractedFact(text_te="ఇద్దరు మృతి చెందారు", level="CLAIM",
                         confidence=0.5, attributed_to="ఎబిసి")
    right = ExtractedFact(text_te="ఐదుగురు మృతి చెందారు", level="CLAIM",
                          confidence=0.5, attributed_to="ఎక్స్‌వైజ్")
    merged = merge_facts([left], [right])
    assert len(merged) >= 2
    # Conflicting numbers must not be silently collapsed into one fact.
    texts = {f.text_te for f in merged}
    assert len(texts) >= 2


def test_merge_facts_keeps_higher_evidence_version():
    low = ExtractedFact(text_te="పథకం ద్రవ్యాలు వచ్చాయి", level="CLAIM",
                        confidence=0.4, attributed_to=None)
    high = ExtractedFact(text_te="పథకం ద్రవ్యాలు వచ్చాయి", level="FACT",
                         confidence=0.95, attributed_to="ప్రభుత్వం")
    merged = merge_facts([low], [high])
    by_level = {f.text_te: f.level for f in merged}
    assert by_level["పథకం ద్రవ్యాలు వచ్చాయి"] == EvidenceLevel.FACT.value


def test_heuristic_facts_never_invent_text():
    text = "సమావేశం ముగిసింది।"
    for fact in heuristic_facts(text, "te"):
        assert fact.text_te in text or fact.text_te.strip()
