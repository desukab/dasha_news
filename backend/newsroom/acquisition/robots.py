"""robots.txt compliance for outbound acquisition.

The newsroom reads an outlet's robots.txt before it reads the outlet's news, and
it does what the file says. This is both the correct thing to do as a guest on
someone else's server and a precondition of aggregating at all.

Semantics follow RFC 9309:

* 2xx  - the file is parsed and obeyed, including ``Crawl-delay``.
* 4xx  - there is no robots policy; the site is treated as fully allowed.
* 5xx / unreachable - the site is treated as *disallowed* for that cycle, on the
  principle that we do not know we are welcome. A flaky robots server is a
  symptom worth an operator's attention, and the admin console shows it.

Policies are cached per host with a TTL, so a sweep that fetches fifty articles
from one outlet makes one robots request, not fifty-one.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from enum import Enum
from threading import Lock
from typing import Optional
from urllib.parse import urlsplit
from urllib.robotparser import RobotFileParser

from newsroom.security.guards import assert_safe_url

logger = logging.getLogger(__name__)

DEFAULT_USER_AGENT = "DashaNewsBot"
_ROBOTS_CACHE_TTL_SECONDS = 3600


class RobotsVerdict(Enum):
    ALLOWED = "allowed"
    DISALLOWED = "disallowed"
    UNAVAILABLE = "unavailable"   # robots itself could not be read


@dataclass
class RobotsEntry:
    parser: Optional[RobotFileParser]
    verdict: RobotsVerdict
    crawl_delay: Optional[float] = None


class RobotsPolicy:
    """Per-host robots.txt policy, cached and never blocking on failure."""

    def __init__(self, fetch_text, *, user_agent: str = DEFAULT_USER_AGENT,
                 ttl_seconds: int = _ROBOTS_CACHE_TTL_SECONDS) -> None:
        # ``fetch_text(url) -> (status, text)``; supplied by the acquisition
        # context so the policy never owns a transport of its own.
        self._fetch_text = fetch_text
        self._user_agent = user_agent
        self._ttl_seconds = ttl_seconds
        self._cache: dict[str, tuple[float, RobotsEntry]] = {}
        self._lock = Lock()

    def allowed(self, url: str) -> bool:
        """May this URL be fetched, according to the outlet's robots policy?"""
        entry = self._entry_for_url(url)
        if entry.verdict == RobotsVerdict.UNAVAILABLE:
            # RFC 9309: a server that cannot serve its policy is a server that
            # has not told us we are welcome.
            return False
        if entry.parser is None:
            return True
        return entry.parser.can_fetch(self._user_agent, url)

    def crawl_delay(self, url: str) -> Optional[float]:
        """The outlet's requested pause between requests, if it stated one."""
        entry = self._entry_for_url(url)
        if entry.parser is None:
            return None
        return entry.parser.crawl_delay(self._user_agent)

    def clear(self) -> None:
        """Drop cached policies; used by tests and by an operator refresh."""
        with self._lock:
            self._cache.clear()

    # -- internals ---------------------------------------------------------

    def _entry_for_url(self, url: str) -> RobotsEntry:
        try:
            robots_url = _robots_url_for(url)
        except ValueError:
            # Not a fetchable URL at all; let the caller's SSRF guard speak.
            return RobotsEntry(parser=None, verdict=RobotsVerdict.ALLOWED)
        if robots_url is None:
            return RobotsEntry(parser=None, verdict=RobotsVerdict.ALLOWED)

        import time

        now = time.time()
        with self._lock:
            cached = self._cache.get(robots_url)
        if cached and now - cached[0] < self._ttl_seconds:
            return cached[1]

        entry = self._load(robots_url)
        with self._lock:
            self._cache[robots_url] = (now, entry)
        return entry

    def _load(self, robots_url: str) -> RobotsEntry:
        try:
            status, text = self._fetch_text(robots_url)
        except Exception as exc:  # noqa: BLE001 - robots must never break the sweep
            logger.info("robots.txt unreadable for %s (%s); treating as unavailable",
                        robots_url, exc)
            return RobotsEntry(parser=None, verdict=RobotsVerdict.UNAVAILABLE)

        if status is not None and 400 <= status < 500:
            return RobotsEntry(parser=None, verdict=RobotsVerdict.ALLOWED)
        if status is None or status >= 500:
            return RobotsEntry(parser=None, verdict=RobotsVerdict.UNAVAILABLE)
        if not text:
            return RobotsEntry(parser=None, verdict=RobotsVerdict.ALLOWED)

        parser = RobotFileParser()
        parser.parse(text.splitlines())
        delay = parser.crawl_delay(self._user_agent)
        return RobotsEntry(parser=parser, verdict=RobotsVerdict.ALLOWED,
                           crawl_delay=delay)


def _robots_url_for(url: str) -> Optional[str]:
    if not url or not isinstance(url, str):
        return None
    parts = urlsplit(url)
    if parts.scheme.lower() not in ("http", "https") or not parts.netloc:
        raise ValueError(f"not an absolute http(s) URL: {url!r}")
    robots_url = f"{parts.scheme.lower()}://{parts.netloc.lower()}/robots.txt"
    # The SSRF guard applies to robots.txt too: it is still an outbound request
    # to an untrusted host.
    assert_safe_url(robots_url)
    return robots_url
