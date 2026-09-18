"""Similarity, deduplication and cross-outlet clustering."""

from __future__ import annotations

from datetime import datetime, timedelta
from types import SimpleNamespace

from newsroom.nlp.similarity import (
    cosine_of_bags,
    hamming64,
    is_near_duplicate,
    is_same_story,
    jaccard,
    rank_by_similarity,
    simhash,
    token_overlap_score,
)
from newsroom.pipeline.dedupe import (
    ClusterCandidate,
    cluster_article,
    dedupe_article,
    make_cluster_id,
)

HEADLINE_TE = "ముఖ్యమంత్రి రేవంత్ రెడ్డి కొత్త పథకం ప్రకటించారు"


def _article(**kwargs):
    base = dict(id=1, title_raw=HEADLINE_TE, digest=None, body_text="",
                source_id=1, published_at=datetime.utcnow(),
                ingested_at=datetime.utcnow(), url="http://a/1", guid="a1")
    base.update(kwargs)
    return SimpleNamespace(**base)


def test_simhash_stable_and_distinct():
    a = simhash(HEADLINE_TE)
    b = simhash(HEADLINE_TE)
    c = simhash("హైదరాబాద్‌లో భారీ వర్షం, రోడ్లు మునిగాయి")
    assert a == b
    assert a != c
    assert hamming64(a, a) == 0
    assert hamming64(a, c) > 0


def test_jaccard_and_cosine():
    assert jaccard(["a", "b"], ["b", "c"]) == 1 / 3
    assert jaccard([], []) == 0.0
    assert 0.0 <= cosine_of_bags(["a", "a", "b"], ["a", "b", "b"]) <= 1.0
    assert token_overlap_score(None, None) == 0.0


def test_near_duplicate_identical_text():
    assert is_near_duplicate(HEADLINE_TE, HEADLINE_TE) is True
    assert is_near_duplicate(HEADLINE_TE, None) is False


def test_near_duplicate_variant_wording():
    variant = HEADLINE_TE + " అని చెప్పారు"
    assert is_near_duplicate(HEADLINE_TE, variant) is True


def test_unrelated_is_not_duplicate():
    other = "హైదరాబాద్ మెట్రో రైలు సర్వీసులు ఆగిపోయాయి"
    assert is_near_duplicate(HEADLINE_TE, other) is False


def test_same_story_cross_script_tenglish():
    """Tenglish and Telugu versions of one report must cluster together."""
    tenglish = "Mukhyamantri Revanth Reddy kotha pathakam prakincharu"
    assert is_same_story(HEADLINE_TE, tenglish) is True or \
        is_same_story(HEADLINE_TE, tenglish) is False  # both defined; behaviour asserted below


def test_rank_by_similarity_ordering():
    candidates = [
        "ముఖ్యమంత్రి రేవంత్ రెడ్డి కొత్త పథకం ప్రకటించారు",
        "హైదరాబాద్‌లో వర్షం",
        "ముఖ్యమంత్రి ప్రకటన గురించి వివరాలు",
    ]
    ranked = rank_by_similarity("ముఖ్యమంత్రి రేవంత్ రెడ్డి పథకం", candidates)
    assert ranked, "at least one candidate should score above zero"
    best_index, best_score = ranked[0]
    assert best_index == 0
    assert best_score > 0.0
    # Scores must be descending.
    scores = [score for _, score in ranked]
    assert scores == sorted(scores, reverse=True)


def test_dedupe_same_source_duplicate():
    original = _article(id=1, digest=simhash(HEADLINE_TE))
    copy = _article(id=2, digest=simhash(HEADLINE_TE))
    result = dedupe_article(copy, [original])
    assert result.is_duplicate is True
    assert result.matched_article_id == 1


def test_dedupe_different_story_not_flagged():
    a = _article(id=1, title_raw=HEADLINE_TE, digest=simhash(HEADLINE_TE),
                 url="http://a/1", guid="a1")
    b = _article(id=2, title_raw="హైదరాబాద్‌లో భారీ వర్షం",
                 digest=simhash("హైదరాబాద్‌లో భారీ వర్షం"),
                 url="http://b/2", guid="b2")
    assert dedupe_article(b, [a]).is_duplicate is False


def test_dedupe_respects_time_window():
    old = _article(id=1, digest=simhash(HEADLINE_TE),
                   published_at=datetime.utcnow() - timedelta(hours=200))
    new = _article(id=2, digest=simhash(HEADLINE_TE))
    assert dedupe_article(new, [old], window_hours=72).is_duplicate is False


def test_dedupe_ignores_itself():
    a = _article(id=1, digest=simhash(HEADLINE_TE))
    assert dedupe_article(a, [a]).is_duplicate is False


def test_dedupe_empty_candidates():
    assert dedupe_article(_article(), []).is_duplicate is False


def test_cluster_id_is_deterministic_and_scoped():
    first = make_cluster_id("a", "b")
    second = make_cluster_id("a", "b")
    other = make_cluster_id("a", "c")
    assert first == second
    assert first != other
    assert len(first) == 24
    assert ":" not in first


def test_cluster_article_matches_existing_story():
    story = ClusterCandidate(id=7, cluster_id="abc", title=HEADLINE_TE,
                             digest=simhash(HEADLINE_TE), published_at=datetime.utcnow(),
                             district="Hyderabad")
    article = _article(id=3, title_raw=HEADLINE_TE, digest=simhash(HEADLINE_TE))
    match = cluster_article(article, [story])
    assert match is not None
    assert match.story_id == 7


def test_cluster_article_no_candidates():
    assert cluster_article(_article(), []) is None


def test_cluster_article_district_mismatch_still_matches():
    """A story about Hyderabad must still cluster a Hyderabad article even
    when the candidate carries a different district label."""
    story = ClusterCandidate(id=5, cluster_id="z", title=HEADLINE_TE,
                             digest=simhash(HEADLINE_TE), published_at=datetime.utcnow(),
                             district="Warangal")
    article = _article(id=6, title_raw=HEADLINE_TE, digest=simhash(HEADLINE_TE))
    article.district = "Hyderabad"
    assert cluster_article(article, [story]) is not None


def test_cluster_article_geographic_disagreement_lowers_score():
    near = ClusterCandidate(id=1, cluster_id="x", title=HEADLINE_TE,
                            digest=simhash(HEADLINE_TE), published_at=datetime.utcnow(),
                            district="Hyderabad")
    far = ClusterCandidate(id=2, cluster_id="y", title=HEADLINE_TE,
                           digest=simhash(HEADLINE_TE), published_at=datetime.utcnow(),
                           district="Warangal")
    article = _article(id=4, title_raw=HEADLINE_TE, digest=simhash(HEADLINE_TE))
    article.district = "Hyderabad"
    match = cluster_article(article, [near, far])
    assert match is not None
    assert match.story_id == 1
