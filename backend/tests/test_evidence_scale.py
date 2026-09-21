"""The publish gate must be reachable, and its floor must hold.

These two properties are the whole reason the feed ever read as stale while
ingestion ran healthy: the score formula and the threshold are two ends of one
arithmetic, and a change to either without the other silently empties the front
page. `conftest` pins the threshold to 0.5 for the rest of the suite, so these
tests read the value shipped in the source -- the invariant is about what
actually ships, not what the suite happens to set.
"""

from __future__ import annotations

from types import SimpleNamespace

import pytest

from newsroom.config import Settings
from newsroom.domain.evidence import EvidenceLevel
from newsroom.pipeline.engines import ImportanceScore
from newsroom.pipeline.orchestrator import _evidence_score
from newsroom.pipeline.publish import decide_publication
from newsroom.pipeline.scoring import ComparisonSummary

# The mean confidence the extractor assigns in practice. Using the observed
# value rather than 1.0 is what makes "reachable" mean reachable on real wire
# copy instead of reachable only in the limit.
MEAN_CONFIDENCE = 0.6

SHIPPED_THRESHOLD = Settings.model_fields["auto_publish_min_evidence"].get_default()


def _fact(level: EvidenceLevel, confidence: float = MEAN_CONFIDENCE) -> SimpleNamespace:
    return SimpleNamespace(evidence_level=level.value, confidence=confidence)


def _score(levels, *, num_sources: int = 1, conflicts: int = 0) -> float:
    summary = ComparisonSummary(num_sources=num_sources, conflicting=["x"] * conflicts)
    return _evidence_score([_fact(level) for level in levels], summary,
                           list(range(num_sources)))


def _gate(threshold: float) -> Settings:
    """A Settings at a chosen threshold, the init arg winning over any env var."""
    return Settings(auto_publish_min_evidence=threshold)


# ---------------------------------------------------------------------------
# Reachability: can the modal evidence class ever get out?
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("level", [EvidenceLevel.CLAIM, EvidenceLevel.OFFICIAL_STATEMENT])
def test_the_modal_evidence_classes_can_clear_the_gate(level):
    """A claim, corroborated once, must be able to leave the draft pile.

    Before this fix a `claim` story with two corroborating outlets scored 0.547
    against a 0.55 threshold: reachable in theory, unreachable in practice, and
    94% of the room sat in `draft` because of it.
    """
    score = _score([level], num_sources=3)
    assert score >= SHIPPED_THRESHOLD, (
        f"{level.value} corroborated 2x scores {score:.3f} but the shipped "
        f"threshold is {SHIPPED_THRESHOLD:.2f}; the gate is unreachable again"
    )


def test_single_source_claim_publishes_as_developing():
    """One source at mean confidence is honest about being developing, not held."""
    assert _score([EvidenceLevel.CLAIM], num_sources=1) >= SHIPPED_THRESHOLD


@pytest.mark.parametrize("level", [EvidenceLevel.FACT, EvidenceLevel.OFFICIAL_STATEMENT])
def test_strong_evidence_publishes_alone(level):
    """A verified fact or an on-the-record statement does not wait for company."""
    assert _score([level], num_sources=1) >= SHIPPED_THRESHOLD


# ---------------------------------------------------------------------------
# The floor: what must never get out unsupervised
# ---------------------------------------------------------------------------


def test_a_lone_unverified_report_is_held():
    """One unverified source is exactly the case the floor exists for."""
    score = _score([EvidenceLevel.UNVERIFIED], num_sources=1)
    assert score < SHIPPED_THRESHOLD, (
        f"an unverified single-source report scores {score:.3f} and would clear "
        f"the {SHIPPED_THRESHOLD:.2f} threshold on its own"
    )


def test_unverified_with_echo_is_labelled_developing_not_held():
    """Four outlets repeating one unverified claim is repetition, not verification --
    but it is also not nothing, and the gate's answer is to send it out labelled
    `developing` rather than to hold it.

    Corroboration is capped at 0.25 so no amount of echo can rescue a weak claim
    on its own; here the echo gets it to 0.48, over the bar, and the honest
    label is what the reader sees. The classification, not the gate, is the
    thing to tighten if that is too permissive: `unverified` with four
    independent outlets behind it is a stale classification.
    """
    score = _score([EvidenceLevel.UNVERIFIED], num_sources=4)
    assert score >= SHIPPED_THRESHOLD
    assert score <= 0.25 + EvidenceLevel.UNVERIFIED.weight  # the cap is doing its job


def test_opinion_and_allegation_do_not_self_publish():
    """Contested or subjective copy needs an editor, not a threshold it can beat."""
    for level in (EvidenceLevel.OPINION, EvidenceLevel.ALLEGATION):
        assert _score([level], num_sources=1) < SHIPPED_THRESHOLD


def test_conflict_pushes_a_claim_back_below_the_bar():
    """Sources contradicting each other costs enough to hold a claim that would
    otherwise ship.

    Two conflicts only dent a corroborated claim -- 0.44 + 0.16 - 0.20 lands on
    the bar, and the gate's comparison is strict, so that story still goes out.
    Three conflicts take it to 0.22, which is the assertion that matters: a
    story the outlets disagree about does not leave the room unsupervised.
    """
    clean = _score([EvidenceLevel.CLAIM], num_sources=2)
    dented = _score([EvidenceLevel.CLAIM], num_sources=3, conflicts=2)
    conflicted = _score([EvidenceLevel.CLAIM], num_sources=2, conflicts=3)

    assert clean >= SHIPPED_THRESHOLD
    assert dented > conflicted
    assert conflicted < SHIPPED_THRESHOLD


# ---------------------------------------------------------------------------
# The gate decides on the same arithmetic the formula computes
# ---------------------------------------------------------------------------


def test_decide_publication_reads_the_configured_threshold():
    """A story over the bar is published; the same story under it is held.

    The decision must read `settings`, not a baked-in constant, or a threshold
    change in config would be silently ignored by the desk that ships it.
    """
    importance = ImportanceScore(score=0.7, components={"recency": 0.7})

    published = decide_publication(
        importance=importance, evidence_score=0.55, num_sources=2,
        section="politics", has_facts=True, language_coverage=["te"],
        settings=_gate(0.30),
    )
    held = decide_publication(
        importance=importance, evidence_score=0.55, num_sources=2,
        section="politics", has_facts=True, language_coverage=["te"],
        settings=_gate(0.90),
    )

    assert published.publish, published.reason
    assert not held.publish
    assert held.status == "draft"


def test_the_threshold_sits_between_the_reportable_and_the_unreportable():
    """The relationship, not the number: the shipped default sits at or below
    the ceiling of every class the desk treats as reportable, and above the
    classes it does not.

    This is the assertion that survives a future re-tuning of the weights -- if
    someone moves a weight, this test says which way the threshold has to move
    with it. It is checked against full confidence, so it is about the ceiling
    rather than about the mean.
    """
    reportable = [EvidenceLevel.FACT, EvidenceLevel.OFFICIAL_STATEMENT, EvidenceLevel.CLAIM]
    unreportable = [EvidenceLevel.UNVERIFIED, EvidenceLevel.OPINION]

    for level in reportable:
        assert level.weight >= SHIPPED_THRESHOLD, (
            f"{level.value} can never reach {SHIPPED_THRESHOLD:.2f} even at "
            f"full confidence (weight {level.weight:.2f})"
        )
    for level in unreportable:
        assert level.weight < SHIPPED_THRESHOLD, (
            f"{level.value} can clear {SHIPPED_THRESHOLD:.2f} on weight alone "
            f"({level.weight:.2f})"
        )
