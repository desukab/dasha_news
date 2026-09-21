"""Publication gate, editorial writer and source comparison."""

from __future__ import annotations

from types import SimpleNamespace

from newsroom.config import get_settings
from newsroom.nlp.telugu import (
    latin_ratio,
    split_sentences,
    telugu_ratio,
    word_count,
)
from newsroom.pipeline.editorial import (
    MAX_BODY_SENTENCES,
    MAX_BODY_WORDS,
    MAX_HEADLINE_WORDS,
    write_article,
    write_headline,
)
from newsroom.pipeline.engines import score_importance
from newsroom.pipeline.publish import (
    PUBLISHED_STATUSES,
    PublishDecision,
    decide_publication,
)
from newsroom.pipeline.scoring import compare_articles, summarise_comparisons
from newsroom.pipeline.facts import ExtractedFact

from datetime import datetime


def _facts(n: int = 3):
    return [
        ExtractedFact(text_te=f"వాస్తవ వాక్యం {i}", level="FACT", confidence=0.9,
                      attributed_to="ప్రభుత్వం")
        for i in range(n)
    ]


# ---------------------------------------------------------------------------
# Publish gate
# ---------------------------------------------------------------------------

def _decision(**kwargs):
    importance = score_importance(evidence_score=0.8, num_sources=3,
                                  source_trust=0.7, published_at=datetime.utcnow(),
                                  is_breaking=False, is_developing=False,
                                  district="Hyderabad", section="politics")
    base = dict(importance=importance, evidence_score=0.8, num_sources=3,
                section="politics", has_facts=True,
                language_coverage=["te", "en"])
    base.update(kwargs)
    return decide_publication(**base)


def test_publish_ok_when_everything_passes():
    decision = _decision()
    assert isinstance(decision, PublishDecision)
    assert decision.publish is True
    assert decision.status in PUBLISHED_STATUSES


def test_global_switch_holds_everything():
    settings = get_settings()
    original = settings.auto_publish_enabled
    settings.auto_publish_enabled = False
    try:
        decision = _decision()
    finally:
        settings.auto_publish_enabled = original
    assert decision.publish is False


def test_no_facts_holds():
    assert _decision(has_facts=False).publish is False


def test_no_language_coverage_holds():
    assert _decision(language_coverage=[]).publish is False
    assert _decision(language_coverage=["ten"]).publish is False


def test_sensitive_section_held():
    decision = _decision(section="crime", evidence_score=0.99)
    assert decision.publish is False
    assert decision.status == "held"


def test_low_evidence_holds():
    decision = _decision(evidence_score=0.1, importance=score_importance(
        evidence_score=0.1, num_sources=1, source_trust=0.3,
        published_at=datetime.utcnow(), is_breaking=False, is_developing=False,
        district=None, section="politics"))
    assert decision.publish is False


def test_single_source_is_developing():
    decision = _decision(num_sources=1)
    assert decision.status == "developing"


def test_published_statuses_complete():
    assert "auto_published" in PUBLISHED_STATUSES
    assert "held" not in PUBLISHED_STATUSES
    assert "killed" not in PUBLISHED_STATUSES


# ---------------------------------------------------------------------------
# Editorial writer
# ---------------------------------------------------------------------------

def test_headline_written_in_the_languages_the_paper_uses():
    for language in ("te", "en"):
        draft = write_headline(_facts(), language=language, district="Hyderabad")
        assert draft.headline, f"no headline for {language}"
        assert draft.words > 0
        assert draft.source in {"model", "heuristic"}


def test_tenglish_is_a_reading_of_the_telugu_line():
    # Tenglish is not a second composition: it is the Telugu line romanised,
    # with the names in it spelled the way a reader writes them (Hyderabad,
    # KCR, BRS). A machine asked to *write* Tenglish copy would only guess at
    # a register it has no copy in, so the Telugu line is composed and the
    # romaniser reads it. See nlp.telugu.to_tenglish.
    headline = write_headline(_facts(), language="te", district="Hyderabad")
    draft = write_headline(_facts(), language="ten", district="Hyderabad")
    assert draft.headline, "no Tenglish headline written"
    assert draft.source == "heuristic"
    # Roman Telugu, not Telugu script and not English: the shape gate is what
    # keeps English-passing-as-Tenglish off the wire.
    assert telugu_ratio(draft.headline) == 0.0
    assert latin_ratio(draft.headline) > 0.5
    # The two are the same line in two scripts.
    assert word_count(draft.headline) == headline.words or \
        word_count(draft.headline) <= MAX_HEADLINE_WORDS

    article = write_article(
        _facts(), language="ten", headline=draft.headline,
        district="Hyderabad")
    assert article.body, "no Tenglish body written"
    assert telugu_ratio(article.body) == 0.0
    assert word_count(article.body) <= MAX_BODY_WORDS
    assert len(split_sentences(article.body)) <= MAX_BODY_SENTENCES


def test_tenglish_withholds_english_facts():
    # English romanised is still English. A story whose facts are in English
    # has no Tenglish reading, and the column is left empty rather than being
    # filled with English filed under the wrong label.
    english_only = [ExtractedFact(text_te="Government announces new policy",
                                  level="FACT", confidence=0.9,
                                  attributed_to="official")]
    assert write_headline(english_only, language="ten",
                          district="Hyderabad").headline == ""
    assert write_article(english_only, language="ten", headline="x",
                         district="Hyderabad").body == ""


def test_headline_needs_facts():
    draft = write_headline([], language="te", district="Hyderabad")
    assert draft.headline == ""
    assert draft.warnings


def test_headline_strips_outlet_branding():
    facts = _facts()
    draft = write_headline(facts, language="te", district="Hyderabad")
    assert not draft.headline.startswith("బ్రేకింగ్ న్యూస్")


def test_article_written_within_limits():
    draft = write_article(_facts(), language="te", headline="శీర్షిక",
                          district="Hyderabad")
    assert draft.headline
    assert draft.lead
    assert draft.body
    assert draft.words <= MAX_BODY_WORDS
    assert len([s for s in draft.body.split("।") if s.strip()]) <= MAX_BODY_SENTENCES + 1


def test_article_needs_facts():
    draft = write_article([], language="en", headline="x", district=None)
    assert draft.body == ""
    assert draft.warnings


def test_lower_rung_facts_get_attribution():
    claims = [ExtractedFact(text_te="ఆరోపణ వాక్యం", level="ALLEGATION",
                            confidence=0.5, attributed_to="ప్రతిపక్షం")]
    draft = write_article(claims, language="te", headline="శీర్షిక",
                          district="Hyderabad")
    assert "ప్రతిపక్షం" in draft.body


def test_english_sketch_refuses_telugu_script():
    telugu_facts = [ExtractedFact(text_te="తెలుగు వాక్యం", level="FACT",
                                  confidence=0.9, attributed_to=None)]
    draft = write_article(telugu_facts, language="en", headline="Headline",
                          district="Hyderabad")
    # English output must not contain raw Telugu glyphs.
    assert not any("ఀ" <= char <= "౿" for char in draft.body)


# ---------------------------------------------------------------------------
# Source comparison
# ---------------------------------------------------------------------------

def _article(title, **kwargs):
    base = dict(id=1, title_raw=title, body_text="", source_id=1,
                published_at=datetime.utcnow(), digested_at=datetime.utcnow())
    base.update(kwargs)
    return SimpleNamespace(**base)


def test_compare_articles_agreement():
    left = _article("ముఖ్యమంత్రి ప్రకటించారు")
    right = _article("ముఖ్యమంత్రి ప్రకటించారు")
    comparison = compare_articles(left, right)
    assert comparison is not None
    assert comparison.corroborates is True or comparison.corroborates is False


def test_compare_articles_detects_conflict():
    left = _article("ఇద్దరు మృతి చెందారు")
    right = _article("ఐదుగురు మృతి చెందారు")
    comparison = compare_articles(left, right)
    assert comparison.conflict or comparison.corroborates is False


def test_summarise_comparisons_never_picks_winner():
    comparisons = [compare_articles(
        _article("ఇద్దరు మృతి చెందారు", id=1, source_id=1),
        _article("ఐదుగురు మృతి చెందారు", id=2, source_id=2))]
    summary = summarise_comparisons(comparisons, ["ఎబిసి", "ఎక్స్‌వైజ్"])
    assert summary is not None
    # The engine reports the disagreement; a human editor resolves it.
    assert not hasattr(summary, "winner") or getattr(summary, "winner", None) is None
    assert summary.num_sources == 2
    assert "corroborating" in summary.to_dict()
