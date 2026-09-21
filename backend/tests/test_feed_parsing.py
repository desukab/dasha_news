"""Reading what a feed actually says.

A feed is a machine interface, and the machine lies sometimes: a CMS that never
titled an item ships an empty or punctuation-only ``<title>``, and that reaches
the reader as a headline of ".". The rules below are about what is accepted as a
headline at the door, before it costs a story its title.
"""

from __future__ import annotations

import pytest

from newsroom.pipeline.scout import parse_feed


def _rss(*titles: str, base: str = "https://www.sakshi.com") -> str:
    items = "".join(
        f"<item><title>{title}</title>"
        f"<link>{base}/news/{index}</link>"
        f"<guid>{base}/news/{index}</guid>"
        f"<description>మంత్రి రైతులతో సమావేశం నిర్వహించారు.</description>"
        f"</item>"
        for index, title in enumerate(titles)
    )
    return f'<rss><channel><title>సాక్షి</title>{items}</channel></rss>'


def test_a_titled_item_keeps_its_title():
    parsed = parse_feed(_rss("కేసీఆర్ రైతులతో సమావేశం"))
    assert [item.title for item in parsed] == ["కేసీఆర్ రైతులతో సమావేశం"]


@pytest.mark.parametrize("junk", [".", "..", "…", "---", " - ", "…"])
def test_a_punctuation_only_title_falls_back_to_the_summary(junk):
    # A real Sakshi item carries <title>.</title> for entries the CMS never
    # titled. Publishing it put a bare full stop on the front page.
    parsed = parse_feed(_rss(junk))
    assert parsed, "an item with a real body must not be dropped for a junk title"
    assert parsed[0].title == "మంత్రి రైతులతో సమావేశం నిర్వహించారు."


def test_the_summary_falls_back_to_its_first_sentence_only():
    parsed = parse_feed(_rss("..."), base_url="https://www.sakshi.com")
    assert parsed[0].title == "మంత్రి రైతులతో సమావేశం నిర్వహించారు."


def test_a_junk_title_and_no_summary_uses_the_url_slug():
    raw = (
        '<rss><channel><item><title>.</title>'
        '<link>https://www.sakshi.com/news/kcr-meets-farmers</link>'
        '<guid>https://www.sakshi.com/news/kcr-meets-farmers</guid>'
        "</item></channel></rss>"
    )
    parsed = parse_feed(raw)
    assert parsed[0].title == "kcr meets farmers"


def test_an_item_with_no_title_and_nothing_to_fall_back_on_is_dropped():
    raw = (
        '<rss><channel><item><title>.</title>'
        '<link>https://www.sakshi.com/</link>'
        '<guid>https://www.sakshi.com/</guid>'
        "</item></channel></rss>"
    )
    # Nothing in the item says what it is about, so it is not published as a
    # story at all rather than titled with the site's host.
    assert parse_feed(raw) == []


def test_an_empty_title_is_treated_like_a_junk_one():
    parsed = parse_feed(_rss(""))
    assert parsed and parsed[0].title.startswith("మంత్రి")
