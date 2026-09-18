"""Per-source acquisition context: transport, politeness, robots and retries.

One object a source adapter receives, holding everything it is allowed to touch
outside its own parsing. Building it here rather than in each adapter is what
keeps "how we ask" in one place and "what we ask for" in another.

Politeness is a first-class citizen. The newsroom paces itself per host, honours
an outlet's own ``Crawl-delay`` when it states one, and never overlaps requests
to the same host. That is both basic good citizenship and, practically, the
cheapest way to stop being blocked in the first place.
"""

from __future__ import annotations

import logging
import threading
import time
from dataclasses import dataclass, field
from typing import Optional

from newsroom.acquisition.backends import (
    BackendUnavailable,
    FetchResult,
    backend_module_name,
)
from newsroom.acquisition.robots import RobotsPolicy
from newsroom.acquisition.retry import (
    FailurePolicy,
    PermanentFetchError,
    RetryExhausted,
    TransientFetchError,
    retrying,
)
from newsroom.config import get_settings
from newsroom.pipeline.fetch import USER_AGENT

logger = logging.getLogger(__name__)

# Generous default pause between requests to one host: a news sweep running every
# five minutes is in no hurry, and a slow news day is not a reason to be rude.
DEFAULT_POLITENESS_SECONDS = 6.0
# ``Crawl-delay`` values above this are honoured by spreading the sweep rather
# than by stalling a single sweep for minutes.
MAX_CRAWL_DELAY_SECONDS = 60.0


@dataclass
class PolitenessGate:
    """Enforces a minimum interval between requests to the same host."""

    interval_seconds: float = DEFAULT_POLITENESS_SECONDS
    enabled: bool = True
    _last_request: dict[str, float] = field(default_factory=dict)
    _lock: threading.Lock = field(default_factory=threading.Lock)

    def wait(self, url: str, *, extra_delay: Optional[float] = None) -> float:
        """Sleep as long as needed to respect the interval. Returns the wait."""
        if not self.enabled or self.interval_seconds <= 0:
            return 0.0
        host = _host_of(url)
        if not host:
            return 0.0
        delay = extra_delay if extra_delay is not None else self.interval_seconds
        with self._lock:
            last = self._last_request.get(host)
            now = time.monotonic()
            if last is not None:
                remaining = delay - (now - last)
            else:
                remaining = 0.0
            # Record the *planned* moment so a second caller queues behind it
            # rather than both waiting for the same gap.
            self._last_request[host] = now + max(0.0, remaining)
        if remaining > 0:
            time.sleep(remaining)
            return remaining
        return 0.0

    def clear(self) -> None:
        with self._lock:
            self._last_request.clear()


@dataclass
class AcquisitionContext:
    """Everything an adapter may use to reach its source."""

    backend: object
    robots: RobotsPolicy
    politeness: PolitenessGate
    policy: FailurePolicy = field(default_factory=FailurePolicy)
    # Optional DB session for observability recording. Absent during tests and
    # during dry runs, and nothing may depend on its presence.
    session: Optional[object] = None
    source_id: Optional[int] = None

    # -- fetch --------------------------------------------------------------

    def fetch(self, url: str, *, stage: str, max_bytes: Optional[int] = None,
              timeout_seconds: Optional[float] = None) -> FetchResult:
        """Fetch ``url`` with politeness, robots and retries applied.

        Raises ``PermissionError`` when the outlet's robots policy refuses us,
        and ``RetryExhausted`` when every attempt failed. Both are for the
        caller to record, not to catch silently.
        """
        self._check_allowed(url)
        self.politeness.wait(url, extra_delay=self._crawl_delay(url))

        attempts = {"count": 0}
        last_error: list[BaseException] = []

        def _do(attempt: int) -> FetchResult:
            attempts["count"] = attempt
            result = self.backend.fetch(  # type: ignore[attr-defined]
                url, max_bytes=max_bytes, timeout_seconds=timeout_seconds)
            if result.status in self.policy.retryable_statuses:
                raise TransientFetchError(
                    f"HTTP {result.status} for {url}", status=result.status,
                    retry_after=result.header("retry-after"))
            return result

        try:
            return retrying(_do, self.policy,
                           on_attempt=lambda n, slept, exc: last_error.append(exc))
        except RetryExhausted as exc:
            self._record(url=url, stage=stage, status=0, ok=False,
                         retries=attempts["count"] - 1,
                         error_kind=type(exc.last_error).__name__)
            raise

    def fetch_text(self, url: str, *, stage: str = "discover",
                   max_bytes: Optional[int] = None) -> tuple[Optional[int], str]:
        """Fetch a small text resource (a feed, a robots file) with the same
        policy, but without retrying: a missing feed is reported, not fought."""
        self._check_allowed(url)
        status, text = self.backend.fetch_text(  # type: ignore[attr-defined]
            url, max_bytes=max_bytes or 262_144)
        self._record(url=url, stage=stage, status=status or 0,
                     ok=status == 200 and bool(text), retries=0)
        return status, text

    # -- policy -------------------------------------------------------------

    def is_allowed(self, url: str) -> bool:
        """Would the outlet's robots policy let us fetch this URL?"""
        try:
            return self.robots.allowed(url)
        except Exception:  # noqa: BLE001 - robots must never block by crashing
            return True

    def _check_allowed(self, url: str) -> None:
        if not self.is_allowed(url):
            logger.info("robots.txt disallows %s", url)
            raise PermissionError(f"robots.txt disallows {url}")

    def _crawl_delay(self, url: str) -> Optional[float]:
        try:
            delay = self.robots.crawl_delay(url)
        except Exception:  # noqa: BLE001
            return None
        if delay is None:
            return None
        return min(float(delay), MAX_CRAWL_DELAY_SECONDS)

    # -- observability ------------------------------------------------------

    def _record(self, *, url: str, stage: str, status: int, ok: bool,
                retries: int = 0, confidence: float = 0.0,
                error_kind: Optional[str] = None) -> None:
        from newsroom.acquisition.observability import record_event

        record_event(
            self.session, source_id=self.source_id, url=url, stage=stage,
            fetch_method=getattr(self.backend, "name", "unknown"),
            http_status=status, extraction_ok=ok,
            extraction_confidence=confidence, retries=retries,
            error_kind=error_kind,
        )


def build_backend(name: str) -> object:
    """Instantiate a named fetch backend, importing its module lazily."""
    module_name = backend_module_name(name)
    if module_name is None:
        raise BackendUnavailable(name or "", "unknown backend name")
    if module_name.endswith("scrapling_backend"):
        module = __import__(module_name, fromlist=["__name__"])
        if name == "scrapling-dynamic":
            return module.ScraplingDynamicBackend()
        return module.ScraplingFetchBackend()
    module = __import__(module_name, fromlist=["__name__"])
    return module.HttpxFetchBackend()


def context_for_source(source, *, session: Optional[object] = None,
                       settings: Optional[object] = None) -> AcquisitionContext:
    """Build the context a particular source should be acquired through."""
    settings = settings or get_settings()
    backend_name = getattr(source, "fetch_backend", None) or "httpx"
    backend = build_backend(backend_name)

    fetch_text = getattr(backend, "fetch_text", None)
    robots = RobotsPolicy(fetch_text or _no_robots,
                          user_agent=_ROBOTS_AGENT)
    if not settings.respect_robots_txt:
        robots = _PermissiveRobotsPolicy()

    interval = getattr(source, "politeness_seconds", None)
    if interval is None or interval < 0:
        interval = settings.politeness_min_interval_seconds

    return AcquisitionContext(
        backend=backend,
        robots=robots,
        politeness=PolitenessGate(
            interval_seconds=float(interval),
            enabled=settings.politeness_min_interval_seconds > 0,
        ),
        policy=_policy_for(source, settings),
        session=session,
        source_id=getattr(source, "id", None),
    )


_ROBOTS_AGENT = USER_AGENT.split("/")[0] if USER_AGENT else "DashaNewsBot"


def _policy_for(source, settings) -> FailurePolicy:
    return FailurePolicy(
        max_retries=settings.fetch_max_retries,
        timeout_seconds=settings.fetch_timeout_seconds,
    )


def _no_robots(_url: str) -> tuple[Optional[int], str]:
    return None, ""


class _PermissiveRobotsPolicy:
    """Used only when an operator has explicitly disabled robots compliance.

    Exists so a hermetic test run never reaches the network; it is never the
    production policy.
    """

    def allowed(self, _url: str) -> bool:
        return True

    def crawl_delay(self, _url: str) -> Optional[float]:
        return None

    def clear(self) -> None:
        pass


def _host_of(url: str) -> str:
    from urllib.parse import urlsplit

    try:
        return (urlsplit(url).netloc or "").lower()
    except ValueError:
        return ""
