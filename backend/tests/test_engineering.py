"""Importance scoring, location classification and section taxonomy."""

from __future__ import annotations

from datetime import datetime, timedelta

from newsroom.domain.geo import ALL_DISTRICTS, resolve_location
from newsroom.domain.sections import (
    ALL_SLUGS,
    BY_SLUG,
    PRIMARY_SLUGS,
    is_sensitive,
    section_for_slug,
)
from newsroom.pipeline.engines import classify_section, locate_story, score_importance


# ---------------------------------------------------------------------------
# Importance
# ---------------------------------------------------------------------------

def _importance(**kwargs):
    base = dict(evidence_score=0.8, num_sources=3, source_trust=0.7,
                published_at=datetime.utcnow(), is_breaking=False,
                is_developing=False, district="Hyderabad", section="politics")
    base.update(kwargs)
    return score_importance(**base)


def test_importance_in_range():
    score = _importance()
    assert 0.0 <= score.score <= 1.0
    assert score.level in {"lead", "major", "standard", "brief", "wire"}


def test_breaking_beats_quiet():
    quiet = _importance()
    breaking = _importance(is_breaking=True)
    assert breaking.score > quiet.score


def test_corroboration_helps():
    one = _importance(num_sources=1)
    many = _importance(num_sources=6)
    assert many.score > one.score


def test_recency_decay():
    old = _importance(published_at=datetime.utcnow() - timedelta(hours=72))
    fresh = _importance()
    assert fresh.score > old.score


def test_held_story_low_importance_stays_low():
    weak = _importance(evidence_score=0.1, num_sources=1, source_trust=0.3,
                       is_breaking=False)
    assert weak.score < _importance().score


def test_importance_components_accounted():
    score = _importance()
    assert set(score.components) >= {"evidence", "corroboration", "recency",
                                    "breaking", "hyperlocal", "source_trust"}
    assert score.reason


# ---------------------------------------------------------------------------
# Location
# ---------------------------------------------------------------------------

def test_all_districts_present():
    assert len(ALL_DISTRICTS) >= 33
    for name in ("Hyderabad", "Warangal Rural", "Medchal-Malkajgiri"):
        assert name in ALL_DISTRICTS


def test_resolve_district_from_text():
    match = resolve_location("హైదరాబాద్ నగరంలో జరిగిన సంఘటన")
    assert match is not None
    assert match.district == "Hyderabad"


def test_resolve_district_from_telugu_script():
    """A Telangana-first product must resolve Telugu copy, not only English."""
    cases = {
        "ఖమ్మం జిల్లా": "Khammam",
        "కరీంనగర్": "Karimnagar",
        "వరంగల్ నగరం": "Warangal Urban",
        "నిజామాబాద్": "Nizamabad",
    }
    for text, expected in cases.items():
        match = resolve_location(text)
        assert match.district == expected, f"{text} -> {match.district}"


def test_resolve_english_name():
    match = resolve_location("Khammam collectorate")
    assert match is not None
    assert match.district == "Khammam"


def test_resolve_alias():
    match = resolve_location("Secunderabad")
    assert match is not None
    assert match.district == "Hyderabad"


def test_resolve_unknown_is_state_level():
    """Nothing recognised must never mean "some plausible district"."""
    match = resolve_location("అసలు పేరు లేని ఊరిలో జరిగింది")
    assert match is not None
    assert match.district is None
    assert match.state == "Telangana"
    assert match.matched_terms == []


def test_resolve_empty():
    match = resolve_location(None)
    assert match is not None
    assert match.state == "Telangana" or match.state is None


def test_locate_story_prefers_text_over_origin():
    result = locate_story("హైదరాబాద్‌లో ప్రమాదం", None,
                          feed_title="వరంగల్ లైవ్")
    assert result.geo.district == "Hyderabad"


def test_locate_story_falls_back_to_origin():
    result = locate_story("పథకం గురించి వివరాలు", None,
                          feed_title="నిజామాబాద్ న్యూస్")
    assert result.geo.district == "Nizamabad" or result.is_telangana


def test_locate_story_other_state_is_not_forced_local():
    result = locate_story("మహారాష్ట్రలో ప్రకటన", None, feed_title=None)
    assert result.is_telangana is False


def test_locate_story_none_input():
    result = locate_story(None, None)
    assert result.confidence >= 0.0


def test_location_confidence_increases_with_specificity():
    state_level = locate_story("తెలంగాణ ప్రభుత్వ నిర్ణయం", None)
    district_level = locate_story("హైదరాబాద్ నగరంలో సమావేశం", None)
    assert district_level.confidence >= state_level.confidence


# ---------------------------------------------------------------------------
# Sections
# ---------------------------------------------------------------------------

def test_taxonomy_shape():
    assert PRIMARY_SLUGS, "primary nav must not be empty"
    assert set(PRIMARY_SLUGS).issubset(set(ALL_SLUGS))
    for slug in ALL_SLUGS:
        section = BY_SLUG[slug]
        assert section.slug == slug
        assert section.te, f"{slug} needs a Telugu label"
        assert section.en, f"{slug} needs an English label"


def test_required_sections_exist():
    required = {"telangana", "hyderabad", "politics", "crime", "courts",
                "accidents", "sports", "cinema", "entertainment", "business",
                "markets", "technology", "science", "health", "weather",
                "agriculture", "infrastructure", "civic", "education", "jobs",
                "elections", "government", "national", "world"}
    assert required.issubset(set(ALL_SLUGS)), \
        sorted(required - set(ALL_SLUGS))


def test_section_lookup():
    section = section_for_slug("politics")
    assert section is not None
    assert section.slug == "politics"
    assert section.te and section.ten and section.en


def test_sensitive_sections():
    assert is_sensitive("crime") is True
    assert is_sensitive("courts") is True
    assert is_sensitive("accidents") is True
    assert is_sensitive("unverified") is True
    assert is_sensitive("sports") is False
    assert is_sensitive("business") is False


def test_classify_section_breaking_first():
    assert classify_section("బ్రేకింగ్: పెద్ద ప్రకటన") == "breaking"


def test_classify_section_from_keywords():
    assert classify_section("క్రికెట్ మ్యాచ్ ఫలితం") == "sports"
    assert classify_section("షేర్ మార్కెట్ గణాంకాలు") == "markets"


def test_classify_section_fallback():
    section = classify_section("సాధారణ ప్రకటన వివరాలు")
    assert section in ALL_SLUGS


def test_classify_section_from_source_default():
    assert classify_section("కొత్త పథకం", source_section="agriculture") == "agriculture"
