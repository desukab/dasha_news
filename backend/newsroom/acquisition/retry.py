"""Retry, backoff and failure policy for outbound acquisition.

One retrying wrapper for every fetch path, so that "we asked twice, the second
time after a polite pause" is a property of the system rather than something
each call site remembers to do.

The policy is deliberately conservative about *what* it retries:

* transient transport failures and the usual "come back later" statuses are
  retried, with ``Retry-After`` honoured when the outlet sends it;
* an SSRF refusal or an oversized body is never retried — retrying a refused
  URL is both pointless and a way to turn a guard into a load test.

Backoff is exponential with jitter, so a fleet of sources that all hit a
slow CDN do not synchronise their retries into a second spike.
"""

from __future__ import annotations

import logging
import random
from dataclasses import dataclass, field
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from typing import Callable, Optional, TypeVar

logger = logging.getLogger(__name__)

T = TypeVar("T")

# Statuses that mean "the outlet is unhappy or overloaded", not "this URL does
# not exist". A 404 is permanent and is not in the list.
RETRYABLE_STATUSES = frozenset({429, 500, 502, 503, 504})

# Never retried: a policy refusal or a hostile response is not transient.
_NEVER_RETRY = ("UnsafeUrlError", "FetchLimitExceeded", "ForbiddenUrl")


@dataclass(frozen=True)
class FailurePolicy:
    max_retries: int = 2
    backoff_base_seconds: float = 2.0
    backoff_max_seconds: float = 30.0
    timeout_seconds: float = 20.0
    respect_retry_after: bool = True
    retryable_statuses: frozenset[int] = field(default_factory=lambda: RETRYABLE_STATUSES)

    @classmethod
    def conservative(cls) -> "FailurePolicy":
        return cls()

    @classmethod
    def for_tests(cls) -> "FailurePolicy":
        return cls(max_retries=1, backoff_base_seconds=0.0, backoff_max_seconds=0.0)


class RetryExhausted(RuntimeError):
    """Every attempt failed; the last error is attached."""

    def __init__(self, message: str, *, attempts: int, last_error: Optional[BaseException]):
        super().__init__(message)
        self.attempts = attempts
        self.last_error = last_error


def backoff_seconds(attempt: int, policy: FailurePolicy) -> float:
    """Exponential backoff with full jitter for the given attempt index."""
    if attempt <= 0:
        return 0.0
    raw = policy.backoff_base_seconds * (2 ** (attempt - 1))
    capped = min(raw, policy.backoff_max_seconds)
    return round(capped * random.random(), 3)


def parse_retry_after(header_value: Optional[str], *, now: Optional[datetime] = None
                      ) -> Optional[float]:
    """Interpret a ``Retry-After`` header as seconds.

    The header may be a delay in seconds or an HTTP date. Returns ``None`` when
    the header is absent or unreadable, in which case the normal backoff applies.
    """
    if not header_value or not isinstance(header_value, str):
        return None
    value = header_value.strip()
    try:
        return max(0.0, float(value))
    except ValueError:
        pass
    try:
        moment = parsedate_to_datetime(value)
    except (TypeError, ValueError):
        return None
    if moment is None:
        return None
    if moment.tzinfo is None:
        moment = moment.replace(tzinfo=timezone.utc)
    reference = now or datetime.now(timezone.utc)
    return max(0.0, (moment - reference).total_seconds())


def retrying(
    operation: Callable[[int], T],
    policy: FailurePolicy,
    *,
    is_retryable: Optional[Callable[[BaseException], bool]] = None,
    on_attempt: Optional[Callable[[int, Optional[float], Optional[BaseException]], None]] = None,
) -> T:
    """Run ``operation(attempt)`` with retries.

    ``operation`` receives the 1-based attempt number and should raise to signal
    failure. ``on_attempt(attempt, slept_seconds, error)`` is called after each
    failed attempt and is where observability hooks in.
    """
    last_error: Optional[BaseException] = None
    attempt = 0
    while True:
        attempt += 1
        try:
            return operation(attempt)
        except BaseException as exc:  # noqa: BLE001 - the caller decides what is fatal
            last_error = exc
            if _is_never_retry(exc) or attempt > policy.max_retries:
                break
            if is_retryable is not None and not is_retryable(exc):
                break
            slept = _sleep_before_retry(attempt, policy, exc)
            if on_attempt is not None:
                on_attempt(attempt, slept, exc)

    raise RetryExhausted(
        f"gave up after {attempt} attempt(s): {type(last_error).__name__}: {last_error}",
        attempts=attempt, last_error=last_error,
    )


def _is_never_retry(error: BaseException) -> bool:
    return type(error).__name__ in _NEVER_RETRY or any(
        cls.__name__ in _NEVER_RETRY for cls in type(error).__mro__
    )


def _sleep_before_retry(attempt: int, policy: FailurePolicy, error: BaseException) -> float:
    import time

    delay = backoff_seconds(attempt, policy)
    if policy.respect_retry_after:
        header = getattr(error, "retry_after", None)
        instructed = parse_retry_after(header)
        if instructed is not None:
            delay = max(delay, min(instructed, policy.backoff_max_seconds * 3))
    if delay <= 0:
        return 0.0
    logger.info("acquisition retry in %.1fs (%s: %s)",
                delay, type(error).__name__, error)
    time.sleep(delay)
    return delay


class TransientFetchError(RuntimeError):
    """A fetch that may succeed if tried again.

    Carries the ``Retry-After`` header, when the outlet sent one, so the retry
    loop can honour the outlet's own requested pause instead of guessing.
    """

    def __init__(self, message: str, *, status: int = 0,
                 retry_after: Optional[str] = None) -> None:
        super().__init__(message)
        self.status = status
        self.retry_after = retry_after


class PermanentFetchError(RuntimeError):
    """A fetch that will not succeed on retry (404, 403, malformed content)."""
