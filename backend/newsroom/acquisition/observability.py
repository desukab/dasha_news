"""Acquisition observability.

One row per outbound attempt, so that "this outlet has not given us a usable
article body in three days" is a question the admin console can answer rather
than something an editor has to notice.

This is the acquisition counterpart of ``AiCall``: the same discipline applied to
the other half of the pipeline. Recording is best-effort by contract. An
observability failure must never cause an acquisition failure — that would make
the cure worse than the disease.
"""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any, Optional

from sqlalchemy.orm import Session

logger = logging.getLogger(__name__)

# Bumped when the extraction logic changes materially, so a row's confidence
# stays interpretable next to an older row's.
PARSER_VERSION = "dasha-1.0"


def record_event(
    session: Optional[Session],
    *,
    source_id: Optional[int],
    url: str,
    stage: str,
    fetch_method: str,
    http_status: int = 0,
    extraction_ok: bool = False,
    extraction_confidence: float = 0.0,
    latency_ms: int = 0,
    retries: int = 0,
    parser_version: Optional[str] = None,
    error_kind: Optional[str] = None,
) -> None:
    """Persist one acquisition attempt. Never raises."""
    if session is None:
        return
    try:
        from newsroom.db.models import AcquisitionEvent

        session.add(AcquisitionEvent(
            source_id=source_id,
            url=(url or "")[:1000],
            stage=stage,
            fetch_method=fetch_method,
            http_status=int(http_status or 0),
            extraction_ok=bool(extraction_ok),
            extraction_confidence=round(float(extraction_confidence or 0.0), 3),
            latency_ms=int(latency_ms or 0),
            retries=int(retries or 0),
            parser_version=parser_version or PARSER_VERSION,
            error_kind=(error_kind or None) and str(error_kind)[:120],
            created_at=datetime.now(timezone.utc),
        ))
        session.flush()
    except Exception as exc:  # noqa: BLE001 - observability must not break the pipeline
        logger.info("could not record acquisition event (%s)", exc)


def error_kind_of(error: Optional[BaseException]) -> Optional[str]:
    """A short, stable label for an error, for grouping in the console."""
    if error is None:
        return None
    name = type(error).__name__
    status = getattr(error, "status", None)
    if status:
        return f"{name}:{status}"
    return name


def summarise_source(session: Optional[Session], source_id: int, *,
                     limit: int = 20) -> list[dict[str, Any]]:
    """Recent acquisition events for one source, newest first."""
    if session is None:
        return []
    try:
        from sqlalchemy import select

        from newsroom.db.models import AcquisitionEvent

        rows = session.execute(
            select(AcquisitionEvent)
            .where(AcquisitionEvent.source_id == source_id)
            .order_by(AcquisitionEvent.created_at.desc())
            .limit(limit)
        ).scalars().all()
        return [
            {
                "stage": row.stage,
                "fetch_method": row.fetch_method,
                "http_status": row.http_status,
                "ok": row.extraction_ok,
                "confidence": row.extraction_confidence,
                "latency_ms": row.latency_ms,
                "retries": row.retries,
                "error_kind": row.error_kind,
                "url": row.url,
                "at": row.created_at.isoformat() if row.created_at else None,
            }
            for row in rows
        ]
    except Exception as exc:  # noqa: BLE001
        logger.info("could not read acquisition events (%s)", exc)
        return []
