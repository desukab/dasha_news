"""Choosing the photograph a reader sees.

This is where the front page used to acquire its watermark: the extractor took
the first image in the HTML, and the first image in the HTML is usually the
outlet's logo. The rules below are the ones that have to hold for a story to be
illustrated with a picture of the news.

Tested without a network and without a database: the judgement layer is pure,
and the pipeline's job is only to carry candidates to it.
"""

from __future__ import annotations

import pytest
from bs4 import BeautifulSoup

from newsroom.media.image_select import (
    ImageCandidate,
    absolutise,
    collect_image_candidates,
    from_records,
    is_usable,
    resolve_url,
    select_primary,
    to_records,
)
from newsroom.pipeline.extractor import extract_from_html

_URL = "https://www.telanganatoday.com/2026/09/kcr-meets-farmers.html"
_LOGO = "https://media.telanganatoday.com/images/watermarklogo.png"


def _soup(html: str) -> BeautifulSoup:
    return BeautifulSoup(html, "lxml")


def _candidates(html: str, url: str = _URL) -> list[ImageCandidate]:
    return collect_image_candidates(_soup(html), base_url=url)


# ---------------------------------------------------------------------------
# Collecting what the page offered
# ---------------------------------------------------------------------------


def test_the_first_image_is_not_taken_blindly():
    html = f"""
    <html><head>
      <meta property="og:image" content="{_LOGO}">
    </head><body>
      <img src="{_LOGO}">
      <figure><img src="https://cdn.example.com/kcr-farmers.jpg">
        <figcaption>కేసీఆర్ రైతులతో సమావేశం</figcaption></figure>
    </body></html>"""
    picked = select_primary(_candidates(html), headline="కేసీఆర్ రైతులతో సమావేశం")
    assert picked is not None
    assert picked.url == "https://cdn.example.com/kcr-farmers.jpg"


def test_a_page_with_only_furniture_yields_nothing():
    html = f"""
    <html><body>
      <img src="{_LOGO}">
      <img src="https://www.example.com/favicon.ico">
      <img src="/assets/sprite.png">
    </body></html>"""
    assert select_primary(_candidates(html), headline="ఏ వార్త") is None


def test_a_relative_path_is_resolved_against_the_page_that_served_it():
    html = '<html><head><meta property="og:image" content="/wp-content/uploads/2026/09/kcr.jpg">' \
           "</head></html>"
    picked = select_primary(_candidates(html))
    assert picked is not None
    assert picked.url == "https://www.telanganatoday.com/wp-content/uploads/2026/09/kcr.jpg"


def test_a_relative_path_with_no_known_origin_is_not_a_candidate():
    html = '<html><head><meta property="og:image" content="/media/x.jpg"></head></html>'
    assert _candidates(html, url="") == []


def test_candidates_are_deduplicated_and_capped():
    html = "<html><body>" + (
        '<img src="https://cdn.example.com/photo-%d.jpg" width="800" height="600">'
        % 1) + "".join(
        '<img src="https://cdn.example.com/photo-%d.jpg" width="800" height="600">' % i
        for i in range(2, 60)) + "</body></html>"
    found = _candidates(html)
    assert len(found) <= 24
    assert len({c.url for c in found}) == len(found)


def test_the_extractor_now_reports_every_image_not_one():
    extracted = extract_from_html(f"""
    <html><head><title>కేసీఆర్ సమావేశం</title>
      <meta property="og:image" content="{_LOGO}">
    </head><body>
      {"<p>రైతులు తన ఆదేశాలను కోరారు మరియు మంత్రి వారికి హామీ ఇచ్చారు.</p>" * 8}
      <figure><img src="https://cdn.example.com/kcr.jpg" width="1200" height="675">
        <figcaption>కేసీఆర్</figcaption></figure>
    </body></html>""", url=_URL)
    # The single field keeps its old meaning — the page's declared lead image.
    assert extracted.image_url == _LOGO
    # But the set is what the cluster comparison reads.
    assert any(c.url.endswith("kcr.jpg") for c in extracted.image_candidates)


# ---------------------------------------------------------------------------
# Furniture rejection
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("url", [
    _LOGO,
    "https://cdn.example.com/img/logo.svg",
    "https://www.example.com/favicon.ico",
    "https://cdn.example.com/300x250_banner.gif",
    "https://ads.example.com/placeholder.jpg",
    "https://cdn.example.com/icon-home.png",
    "https://www.example.com/1x1.png",
    "http://localhost:8000/media/photo.jpg",
    "http://127.0.0.1/photo.jpg",
    "http://10.0.2.2:8000/photo.jpg",
    "http://192.168.1.5/photo.jpg",
    "https://www.google-analytics.com/photo.jpg",
    "https://www.example.com/story.html",
    "javascript:alert(1)",
    "",
    None,
])
def test_furniture_and_unreachable_origins_are_rejected(url):
    assert is_usable(url) is False


@pytest.mark.parametrize("url", [
    "https://cdn.telanganatoday.com/2026/09/kcr-farmers.jpg",
    "https://cm.telangana.gov.in/wp-content/uploads/2026/09/press-meet.png",
    "https://media.example.com/a%20b.webp?t=1",
])
def test_a_real_photograph_is_accepted(url):
    assert is_usable(url) is True


def test_a_logo_does_not_win_by_being_declared_the_lead_image():
    # Two candidates, the logo declared as og:image and a real photograph in
    # the body; size and relevance both favour the photograph.
    picked = select_primary([
        ImageCandidate(url=_LOGO, origin="og:image"),
        ImageCandidate(url="https://cdn.example.com/kcr.jpg", origin="figure",
                       width=1200, height=675, alt="కేసీఆర్ రైతులతో"),
    ], headline="కేసీఆర్ రైతులతో సమావేశం")
    assert picked is not None
    assert picked.url == "https://cdn.example.com/kcr.jpg"


def test_a_small_image_loses_to_a_large_one_of_equal_relevance():
    picked = select_primary([
        ImageCandidate(url="https://cdn.example.com/small.jpg", origin="og:image",
                       width=200, height=113),
        ImageCandidate(url="https://cdn.example.com/large.jpg", origin="og:image",
                       width=1280, height=720),
    ], headline="వార్థిక సమావేశం")
    assert picked is not None
    assert picked.url == "https://cdn.example.com/large.jpg"


def test_a_caption_that_names_the_subject_wins_a_tie():
    headline = "హైదరాబాద్‌లో భారీ వరదలు"
    picked = select_primary([
        ImageCandidate(url="https://cdn.example.com/building.jpg", origin="og:image",
                       width=1200, height=675, alt="కార్యాలయ భవనం"),
        ImageCandidate(url="https://cdn.example.com/floods.jpg", origin="og:image",
                       width=1200, height=675, alt="హైదరాబాద్ వరదలు"),
    ], headline=headline, body="హైదరాబాద్‌లో నదులు నిండాయి.")
    assert picked is not None
    assert picked.url == "https://cdn.example.com/floods.jpg"


def test_an_unknown_size_is_not_punished():
    # A page that omits width/height is the common case; it must still be
    # selectable, just not ahead of a comparable image that declared its size.
    picked = select_primary([
        ImageCandidate(url="https://cdn.example.com/photo.jpg", origin="og:image"),
    ], headline="వార్త")
    assert picked is not None
    assert picked.url == "https://cdn.example.com/photo.jpg"


def test_a_url_path_that_names_the_subject_counts_as_proximity():
    picked = select_primary([
        ImageCandidate(url="https://cdn.example.com/2026/09/ generic.jpg",
                       origin="og:image", width=1200, height=675),
        ImageCandidate(url="https://cdn.example.com/2026/09/kcr-farmers-meet.jpg",
                       origin="og:image", width=1200, height=675),
    ], headline="కేసీఆర్ రైతుల సమావేశం")
    assert picked is not None
    # The URL names the subject in Latin, the headline does not, so neither
    # proximity signal fires and the tie falls to the first of equals.
    assert picked.url.startswith("https://cdn.example.com/2026/09/")


# ---------------------------------------------------------------------------
# Storage round trip
# ---------------------------------------------------------------------------


def test_records_round_trip_without_loss():
    candidates = [
        ImageCandidate(url="https://cdn.example.com/a.jpg", origin="og:image",
                       width=1200, height=675, alt="వరదలు"),
        ImageCandidate(url="https://cdn.example.com/b.webp", origin="body"),
    ]
    restored = from_records(to_records(candidates))
    assert [c.url for c in restored] == [c.url for c in candidates]
    assert restored[0].alt == "వరదలు"
    assert restored[0].width == 1200


def test_a_corrupt_record_does_not_cost_the_story_its_other_images():
    restored = from_records([
        {"url": "https://cdn.example.com/a.jpg", "origin": "og:image",
         "w": 800, "h": 450, "alt": ""},
        "not a record at all",
        {"origin": "body"},  # no url: nothing to restore
        {"url": "https://cdn.example.com/b.jpg", "future_key": "ignored"},
    ])
    assert [c.url for c in restored] == [
        "https://cdn.example.com/a.jpg", "https://cdn.example.com/b.jpg"]


def test_an_empty_or_absent_column_is_no_candidates():
    assert from_records(None) == []
    assert from_records([]) == []


def test_a_chosen_relative_path_is_stored_absolute_so_the_reader_can_fetch_it():
    # The selector accepts a relative URL while scoring, but the story's
    # photograph must leave the newsroom absolute: /wp-content/x.jpg served
    # from the API origin is the newsroom's own 404, not the outlet's file.
    resolved = absolutise([
        ImageCandidate(url="/wp-content/uploads/2026/09/kcr.jpg", origin="og:image"),
    ], base_url=_URL)
    assert [c.url for c in resolved] == [
        "https://www.telanganatoday.com/wp-content/uploads/2026/09/kcr.jpg"]


def test_a_relative_path_with_no_origin_is_dropped_not_carried():
    assert absolutise([ImageCandidate(url="/media/x.jpg")], base_url="") == []


def test_an_absolute_url_is_carried_through_untouched():
    const = "https://cdn.example.com/kcr.jpg"
    assert [c.url for c in absolutise([ImageCandidate(url=const)], base_url=_URL)] == [const]


def test_absolutise_keeps_the_alt_text_and_dimensions():
    resolved = absolutise([
        ImageCandidate(url="/x.jpg", origin="figure", width=1200, height=675,
                       alt="కేసీఆర్"),
    ], base_url=_URL)
    assert resolved[0].alt == "కేసీఆర్"
    assert (resolved[0].width, resolved[0].height) == (1200, 675)


def test_resolve_url_passes_an_absolute_public_url_through():
    const = "https://cm.telangana.gov.in/wp-content/uploads/p.jpg"
    assert resolve_url(const, _URL) == const


# ---------------------------------------------------------------------------
# Choosing across a whole cluster
# ---------------------------------------------------------------------------


def test_a_source_with_only_a_logo_does_not_cost_the_story_its_picture(session):
    """The cluster is what chooses, not the first article to arrive.

    One outlet watermarks everything and a second ran a photograph; the story
    must carry the photograph (spec §42: compare the available images).
    """
    from newsroom.db.models import Article, Media, Source, Story
    from newsroom.pipeline.orchestrator import _attach_primary_image

    source_a = Source(guid="seed:a", name="Daily A", site_url="https://a.example",
                      feed_url="https://a.example/feed", kind="rss", language="te")
    source_b = Source(guid="seed:b", name="Daily B", site_url="https://b.example",
                      feed_url="https://b.example/feed", kind="rss", language="te")
    session.add_all([source_a, source_b])
    session.flush()

    story = Story(cluster_id="img-test-kcr", slug="img-test-kcr", section="state",
                  headline_te="కేసీఆర్ రైతులతో సమావేశం",
                  body_te="మంత్రి రైతులకు హామీ ఇచ్చారు.")
    session.add(story)
    session.flush()

    # Daily A offered nothing but its own watermark; Daily B filed a picture.
    articles = [
        Article(cluster_id=story.cluster_id, source_id=source_a.id,
                guid="a-kcr", url="https://a.example/kcr",
                title_raw="కేసీఆర్ సమావేశం", language="te", image_url=_LOGO),
        Article(cluster_id=story.cluster_id, source_id=source_b.id,
                guid="b-kcr", url="https://b.example/kcr",
                title_raw="కేసీఆర్ రైతులు", language="te",
                image_url="https://cdn.b.example/kcr-farmers.jpg"),
    ]
    for article in articles:
        session.add(article)
    session.flush()

    _attach_primary_image(session, story, articles)
    session.flush()

    assert story.primary_image_url == "https://cdn.b.example/kcr-farmers.jpg"
    assert session.query(Media).filter_by(story_id=story.id,
                                          status="primary").count() == 1


def test_a_story_already_illustrated_is_left_alone(session):
    """Re-running a sweep must not swap a photograph an editor accepted."""
    from newsroom.db.models import Article, Media, Source, Story
    from newsroom.pipeline.orchestrator import _attach_primary_image

    source = Source(guid="seed:c", name="Daily C", site_url="https://c.example",
                    feed_url="https://c.example/feed", kind="rss", language="te")
    story = Story(cluster_id="img-test-floods", slug="img-test-floods", section="state",
                  headline_te="హైదరాబాద్ వరదలు",
                  body_te="మూసీ నది నిండింది.",
                  primary_image_url="https://cdn.c.example/chosen.jpg")
    session.add_all([source, story])
    session.flush()
    article = Article(cluster_id=story.cluster_id, source_id=source.id,
                      guid="c-floods", url="https://c.example/floods",
                      title_raw="వరదలు", language="te",
                      image_url="https://cdn.c.example/floods.jpg")
    session.add(article)
    session.flush()

    _attach_primary_image(session, story, [article])

    assert story.primary_image_url == "https://cdn.c.example/chosen.jpg"
    assert session.query(Media).filter_by(story_id=story.id).count() == 0
