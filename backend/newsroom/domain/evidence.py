"""Evidence taxonomy and the canonical story model.

Generated prose is *never* the source of truth. Every story is grounded in a
list of `Fact` records, each carrying the evidence level that a human or
machine assigned to it, and each traceable back to the exact source article it
came from.

When sources disagree, the disagreement is preserved with attribution. The
system never resolves a conflict by picking a winner and silently discarding
the other side.
"""

from __future__ import annotations

from enum import Enum


class EvidenceLevel(str, Enum):
    """How well-supported a single fact is.

    Ordered from strongest to weakest. The numeric `weight` feeds the
    importance/evidence scoring used by the auto-publish gate.
    """

    FACT = "fact"                    # Verified by multiple independent sources / official record
    OFFICIAL_STATEMENT = "official"  # Said on the record by an authority
    CLAIM = "claim"                  # Asserted by a named party, not independently verified
    ALLEGATION = "allegation"        # Accusation, contested, legal exposure
    FORECAST = "forecast"            # Prediction, future tense
    OPINION = "opinion"              # Editorial / commentary
    UNVERIFIED = "unverified"        # Single-source, developing, could be wrong
    DISPUTED = "disputed"            # Sources contradict each other

    @property
    def weight(self) -> float:
        return _WEIGHTS[self]

    @property
    def label_en(self) -> str:
        return _LABELS_EN[self]

    @property
    def label_te(self) -> str:
        return _LABELS_TE[self]


_WEIGHTS: dict[EvidenceLevel, float] = {
    EvidenceLevel.FACT: 1.0,
    EvidenceLevel.OFFICIAL_STATEMENT: 0.85,
    EvidenceLevel.CLAIM: 0.55,
    EvidenceLevel.ALLEGATION: 0.4,
    EvidenceLevel.FORECAST: 0.35,
    EvidenceLevel.OPINION: 0.25,
    EvidenceLevel.UNVERIFIED: 0.3,
    EvidenceLevel.DISPUTED: 0.45,
}

_LABELS_EN: dict[EvidenceLevel, str] = {
    EvidenceLevel.FACT: "Verified fact",
    EvidenceLevel.OFFICIAL_STATEMENT: "Official statement",
    EvidenceLevel.CLAIM: "Claim",
    EvidenceLevel.ALLEGATION: "Allegation",
    EvidenceLevel.FORECAST: "Forecast",
    EvidenceLevel.OPINION: "Opinion",
    EvidenceLevel.UNVERIFIED: "Unverified report",
    EvidenceLevel.DISPUTED: "Sources disagree",
}

_LABELS_TE: dict[EvidenceLevel, str] = {
    EvidenceLevel.FACT: "నిర్ధారిత వాస్తవం",
    EvidenceLevel.OFFICIAL_STATEMENT: "అధికారిక ప్రకటన",
    EvidenceLevel.CLAIM: "వాదన",
    EvidenceLevel.ALLEGATION: "ఆరోపణ",
    EvidenceLevel.FORECAST: "అంచనా",
    EvidenceLevel.OPINION: "అభిప్రాయం",
    EvidenceLevel.UNVERIFIED: "నిర్ధారణ లేని వార్త",
    EvidenceLevel.DISPUTED: "వర్గాల మధ్య భిన్నాభిప్రాయం",
}


def story_status_label_te(status: str) -> str:
    return _STATUS_LABELS_TE.get(status, status)


_STATUS_LABELS_TE = {
    "draft": "చిత్తరు",
    "auto_published": "ప్రచురితం",
    "published": "ప్రచురితం",
    "developing": "కొనసాగుతున్న వార్త",
    "breaking": "బ్రేకింగ్",
    "held": "సమీక్షలో",
    "corrected": "సవరించబడింది",
    "killed": "ఉపసంహరించబడింది",
}
