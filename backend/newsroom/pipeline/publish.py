"""Update Engine and the publishing gate.

The Update Engine is append-only: a story is never edited in place without
leaving a record of what changed, when, and why. Corrections are first-class
citizens, not deletions.

The publishing gate decides whether a story may go out without a human. It is
an explicit, inspectable policy, and it errs towards holding anything
sensitive.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any, Dict, List, Optional

from newsroom.config import get_settings
from newsroom.domain.sections import is_sensitive
from newsroom.pipeline.engines import ImportanceScore

logger = logging.getLogger(__name__)

PUBLISHED_STATUSES = {"published", "auto_published", "developing", "breaking", "corrected"}


@dataclass
class PublishDecision:
    publish: bool
    status: str
    reason: str
    score: Optional[float] = None

    def to_dict(self) -> Dict[str, Any]:
        return {
            "publish": self.publish,
            "status": self.status,
            "reason": self.reason,
            "score": self.score,
        }


def decide_publication(*, importance: ImportanceScore, evidence_score: float,
                       num_sources: int, section: str, has_facts: bool,
                       language_coverage: Optional[List[str]] = None,
                       settings=None) -> PublishDecision:
    """Apply the auto-publish policy.

    Three independent brakes, any one of which is sufficient to hold a story:
    the global switch, the evidence threshold, and the sensitive-section rule.
    """
    settings = settings or get_settings()

    if not settings.auto_publish_enabled:
        return PublishDecision(False, "draft", "auto-publish is disabled globally")
    if not has_facts:
        return PublishDecision(False, "draft", "no facts extracted yet")

    coverage = set(language_coverage or [])
    if not ({"te", "en"} & coverage):
        return PublishDecision(False, "draft",
                               "no Telugu or English rendering available yet")

    if section in settings.sensitive_category_set or is_sensitive(section):
        return PublishDecision(
            False, "held",
            f"section '{section}' requires human review before publication")

    if evidence_score < settings.auto_publish_min_evidence:
        return PublishDecision(
            False, "draft",
            f"evidence score {evidence_score:.2f} below threshold "
            f"{settings.auto_publish_min_evidence:.2f}",
            score=evidence_score)

    status = "developing" if num_sources < 2 and importance.components.get("recency", 0) > 0.6 \
        else "auto_published"
    return PublishDecision(
        True, status,
        f"evidence {evidence_score:.2f}, {num_sources} source(s), importance "
        f"{importance.score:.2f}",
        score=evidence_score)


# ---------------------------------------------------------------------------
# Update / correction engine
# ---------------------------------------------------------------------------

UPDATE_KINDS = {"update", "correction", "verification", "escalation", "note"}


@dataclass
class StoryChange:
    kind: str
    headline: Optional[str]
    text_te: Optional[str]
    text_en: Optional[str]
    article_id: Optional[int]
    applied_by: str = "pipeline"
    note: Optional[str] = None

    def to_dict(self) -> Dict[str, Any]:
        return {
            "kind": self.kind,
            "headline": self.headline,
            "text_te": self.text_te,
            "text_en": self.text_en,
            "article_id": self.article_id,
            "applied_by": self.applied_by,
            "note": self.note,
        }


def record_update(session, story, change: StoryChange) -> Any:
    """Append an update row. Bumps the story version and corrections counter."""
    from newsroom.db.models import StoryUpdate

    if change.kind not in UPDATE_KINDS:
        raise ValueError(f"unknown update kind: {change.kind}")

    update = StoryUpdate(
        kind=change.kind,
        headline=change.headline,
        text_te=change.text_te,
        text_en=change.text_en,
        article_id=change.article_id,
        applied_by=change.applied_by,
    )
    story.updates.append(update)
    story.version = (story.version or 1) + 1
    story.updated_at = datetime.utcnow()
    if change.kind == "correction":
        story.corrections_count = (story.corrections_count or 0) + 1
        if story.status in PUBLISHED_STATUSES:
            story.status = "corrected"
    elif change.kind == "escalation" and story.status in PUBLISHED_STATUSES:
        story.is_breaking = True
        story.status = "breaking"
    elif change.kind == "verification":
        story.needs_review = False
    session.flush()
    return update


def correct_story(session, story, *, text_te: Optional[str],
                  text_en: Optional[str], applied_by: str,
                  note: Optional[str] = None) -> Any:
    """Issue a correction. The previous version remains in the update history."""
    return record_update(session, story, StoryChange(
        kind="correction", headline=None, text_te=text_te, text_en=text_en,
        article_id=None, applied_by=applied_by, note=note,
    ))


def needs_correction(old_text: Optional[str], new_text: Optional[str]) -> bool:
    """Did a substantive fact change, requiring a visible correction?"""
    if not old_text or not new_text:
        return False
    from newsroom.nlp.similarity import token_overlap_score
    return token_overlap_score(old_text, new_text) < 0.6


@dataclass
class RetentionPolicy:
    """How long raw captured HTML is kept before pruning."""
    retention_days: int = 14

    def expired(self, captured_at: Optional[datetime], now: Optional[datetime] = None) -> bool:
        if not captured_at:
            return False
        now = now or datetime.utcnow()
        return (now - captured_at).days >= self.retention_days


def prune_raw_html(session, *, retention_days: Optional[int] = None,
                   now: Optional[datetime] = None, limit: int = 200) -> int:
    """Delete stale raw bodies. Facts and stories are never pruned."""
    from sqlalchemy import select
    from newsroom.db.models import Article

    now = now or datetime.utcnow()
    days = retention_days if retention_days is not None else get_settings().raw_retention_days
    horizon = now - __import__("datetime").timedelta(days=days)

    rows = session.execute(
        select(Article).where(Article.ingested_at < horizon)
        .where(Article.body_html.isnot(None)).limit(limit)
    ).scalars().all()
    pruned = 0
    for article in rows:
        article.body_html = None
        pruned += 1
    if pruned:
        session.flush()
    return pruned
