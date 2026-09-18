"""Optional Scrapling fetch backends.

Scrapling (BSD-3) is an *optional* dependency. Importing this module costs
nothing; the library is imported lazily inside each method, so the newsroom
boots, runs a full sweep and passes its test suite without the
``scrapling[fetchers]`` extra ever being installed. A source that asks for one
of these backends gets a clear, actionable error instead of a silent fallback
to a slower path.

Two backends are offered, and only two:

``scrapling``
    curl_cffi-based HTTP with browser TLS fingerprinting and HTTP/3. For an
    outlet that returns 403 to httpx's Python fingerprint but serves a browser.
    This is a transport choice, not an access-control defeat: the outlet is
    still free to say no, and its robots.txt is still obeyed.

``scrapling-dynamic``
    a real Chromium through Playwright, for outlets whose article bodies are
    built by JavaScript. Requires both the extra and ``scrapling install``,
    *and* an explicit ``ACQUISITION_BROWSER_ENABLED=1`` from the operator. A
    browser is the most expensive thing this newsroom can do per article, so it
    never starts by default.

Deliberately absent: ``StealthyFetcher``. Its purpose is to defeat Cloudflare
Turnstile and similar challenges and to spoof fingerprints. That is bypassing an
access control, which the newsroom does not do regardless of capability.
"""

from __future__ import annotations

import logging
from typing import Optional
from urllib.parse import urljoin

from newsroom.acquisition.backends import (
    BackendUnavailable,
    FetchResult,
)
from newsroom.config import get_settings, env_flag
from newsroom.security.guards import (
    FetchLimitExceeded,
    UnsafeUrlError,
    assert_safe_url,
    is_safe_url,
)

logger = logging.getLogger(__name__)

_SCRAPLING_MIN_VERSION = (0, 4, 0)
_MAX_REDIRECTS = 4
# The browser path is opt-in twice: the source must ask for it *and* the
# operator must enable browsers on this instance.
_BROWSER_FLAG = "ACQUISITION_BROWSER_ENABLED"

# No TLS impersonation by default. An outlet that needs a browser-shaped
# fingerprint can be given one per source once that is measured to matter;
# impersonation is a politeness claim, not a right of access.
_DEFAULT_IMPERSONATE: Optional[str] = None


def _scrapling_version() -> tuple[int, ...]:
    version = getattr(__import__("scrapling"), "__version__", "0")
    parts = []
    for chunk in str(version).split(".")[:3]:
        digits = "".join(ch for ch in chunk if ch.isdigit())
        parts.append(int(digits) if digits else 0)
    return tuple(parts)


def _require_scrapling(backend: str, *, need_browser: bool = False) -> None:
    """Import scrapling or explain precisely how to get it."""
    try:
        import scrapling  # noqa: F401
    except ImportError as exc:
        raise BackendUnavailable(
            backend, f"the scrapling package is not installed ({exc})") from exc
    if _scrapling_version() < _SCRAPLING_MIN_VERSION:
        raise BackendUnavailable(
            backend,
            f"scrapling {_SCRAPLING_MIN_VERSION} or newer is required, "
            f"found {getattr(scrapling, '__version__', '?')}")
    if need_browser and not env_flag(_BROWSER_FLAG):
        raise BackendUnavailable(
            backend,
            f"{_BROWSER_FLAG} is not set; browser fetching is disabled by default")


class ScraplingFetchBackend:
    """curl_cffi HTTP fetcher, under the newsroom's own SSRF policy."""

    name = "scrapling"

    def fetch(self, url: str, *, max_bytes: Optional[int] = None,
              timeout_seconds: Optional[float] = None) -> FetchResult:
        from newsroom.acquisition.retry import TransientFetchError

        _require_scrapling(self.name)
        from scrapling.fetchers import Fetcher

        settings = get_settings()
        limit = max_bytes if max_bytes is not None else settings.fetch_max_bytes
        timeout = timeout_seconds if timeout_seconds is not None else settings.fetch_timeout_seconds
        current = assert_safe_url(url)

        # Redirects are handled here rather than by curl so that every hop is
        # re-checked by *our* guard, which also refuses .local/.internal names
        # and resolves a public-looking host that points at a private address.
        for _hop in range(_MAX_REDIRECTS + 1):
            try:
                response = Fetcher.get(
                    current,
                    follow_redirects=False,
                    retries=0,               # the acquisition layer owns retry policy
                    timeout=timeout,
                    impersonate=_DEFAULT_IMPERSONATE,
                    headers={
                        "User-Agent": _user_agent(),
                        "Accept-Language": "te, en;q=0.8",
                    },
                )
            except Exception as exc:  # noqa: BLE001 - surfaced as a transport error
                raise TransientFetchError(f"scrapling fetch failed for {current}: {exc}") from exc

            if response.status in (301, 302, 303, 307, 308):
                location = _header(response, "location")
                if not location:
                    raise UnsafeUrlError(f"redirect without location: {current}")
                target = urljoin(current, location)
                if not is_safe_url(target):
                    raise UnsafeUrlError(f"refused redirect target: {target}")
                logger.debug("scrapling redirect %s -> %s", current, target)
                current = target
                continue

            body = response.body or b""
            if len(body) > limit:
                raise FetchLimitExceeded(f"body exceeded {limit} bytes at {current}")

            return FetchResult(
                url=url,
                final_url=response.url or current,
                status=int(response.status or 0),
                body=body,
                content_type=(_header(response, "content-type") or "").split(";")[0].strip(),
                elapsed_ms=int(getattr(response, "elapsed_ms", 0) or 0),
                headers=tuple(_all_headers(response)),
            )
        raise UnsafeUrlError(f"too many redirects from {url}")

    def fetch_text(self, url: str, *, max_bytes: int = 262_144
                   ) -> tuple[Optional[int], str]:
        """Fetch robots.txt-sized text through the same guarded path."""
        try:
            result = self.fetch(url, max_bytes=max_bytes)
        except Exception as exc:  # noqa: BLE001 - robots must never break the sweep
            logger.info("scrapling text fetch failed for %s: %s", url, exc)
            return None, ""
        return result.status, result.text

    def close(self) -> None:
        # curl_cffi clients are owned by Scrapling's module-level instances.
        pass


class ScraplingDynamicBackend:
    """A real browser, for outlets whose content JavaScript builds."""

    name = "scrapling-dynamic"

    def fetch(self, url: str, *, max_bytes: Optional[int] = None,
              timeout_seconds: Optional[float] = None) -> FetchResult:
        _require_scrapling(self.name, need_browser=True)
        from scrapling.fetchers import DynamicFetcher

        current = assert_safe_url(url)
        settings = get_settings()
        timeout_ms = int(
            (timeout_seconds if timeout_seconds is not None else settings.fetch_timeout_seconds)
            * 1000
        )

        try:
            response = DynamicFetcher.fetch(
                current,
                headless=True,
                load_dom=True,
                network_idle=True,
                block_ads=True,
                timeout=timeout_ms,
            )
        except Exception as exc:  # noqa: BLE001
            from newsroom.acquisition.retry import TransientFetchError

            raise TransientFetchError(f"browser fetch failed for {current}: {exc}") from exc

        # A page's own JavaScript can redirect somewhere the guard would have
        # refused; check where we actually landed before reading anything.
        final_url = str(getattr(response, "url", "") or current)
        if final_url and not is_safe_url(final_url):
            raise UnsafeUrlError(f"browser landed on an unsafe url: {final_url}")

        body = response.body or b""
        if len(body) > (max_bytes if max_bytes is not None else settings.fetch_max_bytes):
            raise FetchLimitExceeded(f"body exceeded the configured limit at {final_url}")

        return FetchResult(
            url=url,
            final_url=final_url,
            status=int(response.status or 0),
            body=body,
            content_type=(_header(response, "content-type") or "").split(";")[0].strip(),
            elapsed_ms=int(getattr(response, "elapsed_ms", 0) or 0),
            headers=tuple(_all_headers(response)),
        )

    def fetch_text(self, url: str, *, max_bytes: int = 262_144
                   ) -> tuple[Optional[int], str]:
        # robots.txt has no JavaScript; the static backend is the right tool.
        return ScraplingFetchBackend().fetch_text(url, max_bytes=max_bytes)

    def close(self) -> None:
        pass


def _header(response, name: str) -> Optional[str]:
    try:
        headers = response.headers or {}
        for key, value in headers.items():
            if key.lower() == name.lower():
                return value
    except Exception:  # noqa: BLE001
        pass
    return None


def _all_headers(response) -> tuple[tuple[str, str], ...]:
    try:
        return tuple((str(k), str(v)) for k, v in (response.headers or {}).items())
    except Exception:  # noqa: BLE001
        return ()


def _user_agent() -> str:
    from newsroom.pipeline.fetch import USER_AGENT

    return USER_AGENT
