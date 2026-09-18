"""Safe outbound fetching with redirect re-validation and size caps."""

from __future__ import annotations

import logging
import threading
import time
from typing import Optional

import httpx

from newsroom.config import get_settings
from newsroom.security.guards import (
    FetchLimitExceeded,
    SafeResponse,
    UnsafeUrlError,
    assert_safe_url,
    is_safe_url,
)

logger = logging.getLogger(__name__)

USER_AGENT = "DashaNewsBot/1.0 (+https://dashanews.com; newsroom aggregator)"
_MAX_REDIRECTS = 4
_CONNECT_TIMEOUT = 10.0

_client: Optional[httpx.Client] = None
_client_lock = threading.Lock()


def _client_pool() -> httpx.Client:
    """The shared connection pool.

    The sweep runs sources concurrently and the scheduler may overlap two
    sweeps, so the lazy construction is under a lock: without it two threads
    could each build a client and leak one (and its sockets) silently.
    """
    global _client
    if _client is None:
        with _client_lock:
            if _client is None:
                _client = httpx.Client(
                    timeout=httpx.Timeout(_CONNECT_TIMEOUT,
                                          read=get_settings().fetch_timeout_seconds),
                    headers={"User-Agent": USER_AGENT, "Accept-Language": "te, en;q=0.8"},
                    follow_redirects=False,
                )
    return _client


def close_client() -> None:
    global _client
    if _client is not None:
        _client.close()
        _client = None


def fetch(url: str, *, max_bytes: Optional[int] = None) -> SafeResponse:
    """Fetch a URL under the newsroom's security policy.

    Redirects are followed manually so that every hop is re-checked against the
    SSRF guard. The body is truncated at ``max_bytes`` rather than buffered to
    completion, which bounds memory against a hostile multi-gigabyte response.
    """
    settings = get_settings()
    limit = max_bytes if max_bytes is not None else settings.fetch_max_bytes
    current = assert_safe_url(url)
    started = time.monotonic()
    client = _client_pool()

    for hop in range(_MAX_REDIRECTS + 1):
        try:
            with client.stream("GET", current) as response:
                content_type = response.headers.get("content-type", "").split(";")[0].strip()
                if response.is_redirect or response.status_code in (301, 302, 303, 307, 308):
                    location = response.headers.get("location", "")
                    if not location:
                        raise UnsafeUrlError(f"redirect without location: {current}")
                    from urllib.parse import urljoin
                    target = urljoin(current, location)
                    if not is_safe_url(target):
                        raise UnsafeUrlError(f"refused redirect target: {target}")
                    logger.debug("redirect %s -> %s", current, target)
                    current = target
                    continue
                if response.status_code != 200:
                    return SafeResponse(url, current, response.status_code, b"",
                                        content_type,
                                        int((time.monotonic() - started) * 1000),
                                        _headers(response))
                body = bytearray()
                for chunk in response.aiter_bytes(64 * 1024):
                    body.extend(chunk)
                    if len(body) > limit:
                        raise FetchLimitExceeded(
                            f"body exceeded {limit} bytes at {current}")
                return SafeResponse(url, current, 200, bytes(body), content_type,
                                    int((time.monotonic() - started) * 1000),
                                    _headers(response))
        except httpx.HTTPError as exc:
            logger.info("fetch failed for %s: %s", current, exc)
            raise FetchError(str(exc)) from exc
        except UnsafeUrlError:
            raise
    raise UnsafeUrlError(f"too many redirects from {url}")


class FetchError(RuntimeError):
    """Transport-level fetch failure."""


def _headers(response) -> tuple[tuple[str, str], ...]:
    """Snapshot the response headers as pairs for the Retry-After policy."""
    try:
        return tuple(response.headers.multi_items())
    except Exception:  # noqa: BLE001 - headers are observability, not control flow
        return ()
