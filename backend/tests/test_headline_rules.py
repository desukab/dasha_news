"""Headline rules: no location inside the headline, no outlet furniture.

Spec: location belongs in the story's metadata, and the wire copy that reaches
the newsroom carries the outlet's own widgets -- cross-links, photo credits,
video prompts -- which are not news and must not reach the reader.
"""

from __future__ import annotations

from types import SimpleNamespace

import pytest

from newsroom.pipeline.editorial import (
    MAX_HEADLINE_WORDS,
    _clean_headline,
    strip_site_boilerplate,
    write_headline,
)


def _facts(text_te: str, text_en: str = "", source_title: str = "") -> list:
    return [SimpleNamespace(
        text_te=text_te, text_en=text_en or None, source_title=source_title,
        attributed_to=None, evidence_level="claim", confidence=0.6,
        source_article_id=1)]


# ---------------------------------------------------------------------------
# Location stays out of the headline
# ---------------------------------------------------------------------------


def test_a_telugu_headline_carries_no_location_suffix():
    """The story's own district column carries the place; the headline need not.

    Appending it consumed two of the ten words a headline may have and pushed
    the actual news to the tail, where a narrow phone screen truncates it.
    """
    draft = write_headline(_facts("హైదరాబాద్‌లో భారీ రోడ్డు ప్రమాదం"),
                           language="te", district="హైదరాబాద్")
    assert draft.headline
    assert "తెలంగాణ" not in draft.headline
    assert "|" not in draft.headline


def test_an_english_headline_carries_no_location_suffix():
    draft = write_headline(
        _facts("Minister announces new scheme", "Minister announces new scheme"),
        language="en", district="Hyderabad")
    assert draft.headline
    assert "Telangana" not in draft.headline
    assert "–" not in draft.headline


def test_a_headline_without_a_district_is_not_given_one():
    """The default place is the newsroom's, not the story's -- inventing it for
    every untied story is how `| తెలంగాణ` ended up on 269 stored headlines.
    """
    draft = write_headline(_facts("రాష్ట్రంలో వర్షాలు కొనసాగుతున్నాయి"),
                           language="te", district=None)
    assert draft.headline == "రాష్ట్రంలో వర్షాలు కొనసాగుతున్నాయి"


# ---------------------------------------------------------------------------
# Outlet furniture is stripped
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("chrome,news", [
    ("Also Read | ", "హైదరాబాద్‌లో భారీ రోడ్డు ప్రమాదం"),
    ("Watch: ", "మెట్రో రైలులో సంఘటన"),
    ("Read More: ", ""),
    ("Representational image: ", ""),
])
def test_leading_furniture_is_stripped(chrome, news):
    assert strip_site_boilerplate(chrome + news) == news


@pytest.mark.parametrize("news,trailer", [
    ("హైదరాబాద్‌లో భారీ రోడ్డు ప్రమాదం", " | ఫొటో క్రెడిట్: ANI"),
    ("మెట్రో రైలులో సంఘటన", " - ఫోటో క్రెడిట్: ANI"),
    ("వర్షాలు", " | ఫోటో క్రెడిట్"),
    ("మంత్రి ప్రకటన", " ఫోటో క్రెడిట్: ANI"),
])
def test_trailing_photo_credit_is_stripped_with_its_agency(news, trailer):
    """The agency belongs to the credit; keeping it leaves "ప్రమాదం | : ANI",
    which is a headline with nothing after the pipe.
    """
    assert strip_site_boilerplate(news + trailer) == news


def test_stacked_furniture_is_stripped_to_the_news():
    assert strip_site_boilerplate("Also Read | Watch: మెట్రో రైలులో సంఘటన") \
        == "మెట్రో రైలులో సంఘటన"


def test_a_credit_before_the_news_is_stripped():
    assert strip_site_boilerplate("Photo Credits: PTI | మంత్రి ప్రకటన") \
        == "మంత్రి ప్రకటన"


def test_a_headline_that_is_only_furniture_becomes_empty():
    """An empty result is the correct signal: the wire item had no headline,
    and the writer withholds rather than shipping a widget.
    """
    assert strip_site_boilerplate("మరిన్ని వార్తల కోసం క్లిక్ చేయండి") == ""


# ---------------------------------------------------------------------------
# The strip does not eat real headlines
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("headline", [
    "ప్రభుత్వం కొత్త పథకాన్ని ప్రారంభించింది",
    "ముఖ్యమంత్రి ప్రారంభించిన కొత్త పథకం",
    "KCR launches scheme in Hyderabad",
    "Budget watch: what changed for Telangana",
    "హైదరాబాద్‌లో భారీ రోడ్డు ప్రమాదం",
])
def test_a_clean_headline_is_left_alone(headline):
    """A phrase that can open a genuine headline costs us news; a phrase that
    can only open a widget costs nothing by being left in. The words that sit
    on the boundary are the ones this test exists for.
    """
    assert strip_site_boilerplate(headline) == headline


def test_a_prompt_word_is_not_stripped_from_the_tail():
    """"Watch" leads a chrome headline, but at the tail it is the story's own
    vocabulary. Cutting there destroyed "Budget watch:" to get "Budget".
    """
    assert strip_site_boilerplate("Telangana budget watch").endswith("watch")


def test_the_stripper_handles_an_empty_string():
    assert strip_site_boilerplate("") == ""


# ---------------------------------------------------------------------------
# The writer applies both rules
# ---------------------------------------------------------------------------


def test_write_headline_strips_furniture_from_the_source_title():
    """A single-source story reuses the outlet's title, which is exactly where
    the widgets live.
    """
    draft = write_headline(
        _facts("హైదరాబాద్‌లో భారీ రోడ్డు ప్రమాదం",
               source_title="Also Read | హైదరాబాద్‌లో భారీ రోడ్డు ప్రమాదం | ఫొటో క్రెడిట్: ANI"),
        language="te", district="హైదరాబాద్")
    assert draft.headline == "హైదరాబాద్‌లో భారీ రోడ్డు ప్రమాదం"


def test_a_stripped_headline_still_respects_the_word_limit():
    draft = write_headline(_facts(" ".join(["పదం"] * 14)), language="te", district=None)
    assert draft.headline
    assert len(draft.headline.split()) <= MAX_HEADLINE_WORDS


def test_clean_headline_returns_empty_for_pure_furniture():
    assert _clean_headline("మరిన్ని వార్తల కోసం క్లిక్ చేయండి") == ""
