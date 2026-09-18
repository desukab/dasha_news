"""The default fetch backend: httpx under the newsroom's security policy.

No extra dependency, no browser, no fingerprint tricks. This is the transport
every source uses unless it has a specific reason not to, which is the right
default for an aggregator that wants to be a well-behaved guest.
"""

from __future__ import annotations

import logging
from typing import Optional

from newsroom.acquisition.backends import FetchResult
from newsroom.config import get_settings
from newsroom.pipeline.fetch import FetchError, close_client, fetch

logger = logging.getLogger(__name__)

# robots.txt is small; a generous cap still bounds memory if a hostile host
# serves something enormous at that path.
_ROBOTS_MAX_BYTES = 262_144


class HttpxFetchBackend:
    """httpx fetcher with manual redirect re-validation and a byte cap."""

    name = "httpx"

    def fetch(self, url: str, *, max_bytes: Optional[int] = None,
              timeout_seconds: Optional[float] = None) -> FetchResult:
        response = fetch(url, max_bytes=max_bytes)
        return FetchResult(
            url=response.url,
            final_url=response.final_url,
            status=response.status,
            body=response.body,
            content_type=response.content_type,
            elapsed_ms=response.elapsed_ms,
            headers=response.headers,
        )

    def fetch_text(self, url: str, *, max_bytes: int = _ROBOTS_MAX_BYTES
                   ) -> tuple[Optional[int], str]:
        """Fetch a text resource, returning (status, text).

        A transport failure reports ``(None, "")`` so callers can distinguish
        "the server said 404" from "the server did not answer".
        """
        try:
            response = fetch(url, max_bytes=max_bytes)
        except FetchError as exc:
            logger.info("text fetch failed for %s: %s", url, exc)
            return None, ""
        return response.status, response.body.decode("utf-8", "replace")

    def close(self) -> None:
        close_client()


def default_max_bytes() -> int:
    return get_settings().fetch_max_bytes
