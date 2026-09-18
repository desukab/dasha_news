"""Background automation: the periodic newsroom sweep and the job queue.

Both are optional: the API boots and serves stories without this module ever
running. That keeps the reader path simple and makes the newsroom easy to
operate from the admin console alone.
"""

from __future__ import annotations

import logging
import threading
import time
from datetime import datetime, timezone
from typing import Optional

from sqlalchemy import select, update

from newsroom.config import get_settings
from newsroom.db.engine import db_scope
from newsroom.db.models import Job
from newsroom.pipeline.orchestrator import run_sweep

logger = logging.getLogger(__name__)

MAX_JOB_ATTEMPTS = 3


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def enqueue(stage: str, payload: Optional[dict] = None, priority: int = 0) -> int:
    """Queue a unit of newsroom work. Returns the job id."""
    import json

    with db_scope() as session:
        job = Job(stage=stage, payload_json=json.dumps(payload) if payload else None,
                  status="queued", priority=priority)
        session.add(job)
        session.commit()
        return job.id


def _claim_next_job(session) -> Optional[Job]:
    """Claim the highest-priority queued job.

    SQLite has no `SELECT ... FOR UPDATE`, so the claim is a plain select plus
    a status write. Only one worker is expected per process; the `running`
    transition is what prevents double-handling.
    """
    job = session.execute(
        select(Job).where(Job.status == "queued")
        .order_by(Job.priority.desc(), Job.created_at.asc()).limit(1)
    ).scalar_one_or_none()
    if job is None:
        return None
    job.status = "running"
    job.started_at = _utcnow()
    session.commit()
    return job


def run_pending_jobs(limit: int = 20) -> int:
    """Work off the queue. Returns the number of jobs processed."""
    import json

    from newsroom.db.models import Story
    from newsroom.pipeline.orchestrator import regenerate_story

    processed = 0
    for _ in range(limit):
        with db_scope() as session:
            job = _claim_next_job(session)
            if job is None:
                return processed
            job_id = job.id
            attempts = (job.attempts or 0) + 1
            stage = job.stage
            payload = json.loads(job.payload_json) if job.payload_json else {}

        with db_scope() as session:
            session.execute(
                update(Job).where(Job.id == job_id)
                .values(status="running", attempts=attempts, started_at=_utcnow())
            )
            session.commit()

        try:
            if stage == "sweep":
                with db_scope() as session:
                    report = run_sweep(session)
                result = f"new={report.articles_new} stories={report.stories_created}"
            elif stage == "regenerate":
                story_id = int(payload.get("story_id", 0))
                with db_scope() as session:
                    story = session.get(Story, story_id)
                    if story is None:
                        raise ValueError(f"story {story_id} not found")
                    regenerate_story(session, story)
                result = f"story={story_id}"
            else:
                raise ValueError(f"no handler for job stage {stage!r}")

            _finish_job(job_id, "done", None)
            logger.info("job %d (%s) done: %s", job_id, stage, result)
        except Exception as exc:  # noqa: BLE001 - a bad job must not kill the loop
            logger.exception("job %d (%s) failed", job_id, stage)
            status = "failed" if attempts < MAX_JOB_ATTEMPTS else "dead"
            _finish_job(job_id, status, f"{type(exc).__name__}: {exc}"[:500])
        processed += 1
    return processed


def _finish_job(job_id: int, status: str, note: Optional[str]) -> None:
    with db_scope() as session:
        session.execute(
            update(Job).where(Job.id == job_id)
            .values(status=status, error=note, finished_at=_utcnow())
        )
        session.commit()


def sweep_once(fetch_bodies: bool = True) -> dict:
    """Run a single newsroom sweep in its own session."""
    with db_scope() as session:
        report = run_sweep(session, fetch_bodies=fetch_bodies)
        session.commit()
    return report.to_dict()


class NewsroomScheduler:
    """Thin wrapper over APScheduler, or a plain thread when it is unavailable."""

    def __init__(self, interval_seconds: Optional[int] = None):
        self.interval = interval_seconds or get_settings().pipeline_interval_seconds
        self._thread: Optional[threading.Thread] = None
        self._stop = threading.Event()
        self._scheduler = None

    def start(self) -> None:
        if self.interval <= 0:
            logger.info("pipeline scheduler disabled (interval=0)")
            return
        try:
            from apscheduler.schedulers.background import BackgroundScheduler
            from apscheduler.triggers.interval import IntervalTrigger

            self._scheduler = BackgroundScheduler(daemon=True)
            self._scheduler.add_job(
                self._tick, IntervalTrigger(seconds=self.interval),
                id="dasha-sweep", max_instances=1, coalesce=True,
            )
            self._scheduler.start()
            logger.info("newsroom sweep scheduled every %ss", self.interval)
            return
        except Exception as exc:  # noqa: BLE001
            logger.warning("apscheduler unavailable (%s); using thread loop", exc)
            self._scheduler = None

        self._thread = threading.Thread(target=self._loop, daemon=True, name="dasha-sweep")
        self._thread.start()

    def _loop(self) -> None:
        while not self._stop.wait(self.interval):
            try:
                self._tick()
            except Exception:  # noqa: BLE001
                logger.exception("scheduled sweep failed")

    def _tick(self) -> None:
        started = time.monotonic()
        try:
            report = sweep_once()
            logger.info("sweep done in %.1fs: %s", time.monotonic() - started, report)
        except Exception:  # noqa: BLE001
            logger.exception("sweep failed")

    def shutdown(self, wait: bool = False) -> None:
        self._stop.set()
        if self._scheduler is not None:
            try:
                self._scheduler.shutdown(wait=wait)
            except Exception:  # noqa: BLE001
                pass
        if self._thread is not None and wait:
            self._thread.join(timeout=10)
