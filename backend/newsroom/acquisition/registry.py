"""Adapter registry: which adapter speaks to which source.

Selection is a two-question lookup, and both answers live on the Source row:

* ``Source.kind`` — the adapter: what shape does this outlet's content come in?
* ``Source.fetch_backend`` — the transport: how do we reach it?

Neither is global state. A newsroom can run RSS, plain-HTML and browser-backed
sources side by side in the same sweep, and adding a new outlet is a
configuration change, not a code change.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from typing import Any, Optional

from newsroom.acquisition.context import AcquisitionContext, context_for_source
from newsroom.acquisition.html_adapter import HtmlAdapter
from newsroom.acquisition.retry import FailurePolicy
from newsroom.acquisition.rss_adapter import RssAdapter
from newsroom.acquisition.source_adapter import (
    ListingItem,
    SourceAdapter,
)

logger = logging.getLogger(__name__)

# An adapter for every declared source kind. ``web`` means "no usable feed; read
# the site itself". Unknown kinds fall back to RSS rather than failing, because a
# typo in the admin console must not silently disable an outlet.
_ADAPTERS: dict[str, str] = {
    "rss": "rss",
    "atom": "rss",
    "feed": "rss",
    "web": "web",
    "html": "web",
}


def adapter_for_kind(kind: Optional[str]) -> SourceAdapter:
    """The adapter for a source kind, defaulting to RSS."""
    key = _ADAPTERS.get((kind or "rss").strip().lower(), "rss")
    if key == "web":
        return HtmlAdapter()
    return RssAdapter()


@dataclass
class Acquisition:
    """An adapter bound to the context it is allowed to use.

    The pipeline asks for one of these and then talks to a source without ever
    learning whether it is RSS or web, httpx or browser.
    """

    adapter: SourceAdapter
    ctx: AcquisitionContext

    def discover(self, source: Any) -> list[ListingItem]:
        return self.adapter.discover(source, self.ctx)

    def extract(self, source: Any, url: str) -> Any:
        return self.adapter.extract(source, url, self.ctx)

    @property
    def fetch_method(self) -> str:
        return getattr(self.ctx.backend, "name", "unknown")


def acquire(source: Any, *, session: Optional[Any] = None,
            settings: Optional[Any] = None) -> Acquisition:
    """Build the acquisition handle for one source."""
    return Acquisition(
        adapter=adapter_for_kind(getattr(source, "kind", None)),
        ctx=context_for_source(source, session=session, settings=settings),
    )


def policy_for(source: Any) -> FailurePolicy:
    return adapter_for_kind(getattr(source, "kind", None)).failure_policy(source)


__all__: list[str] = ["Acquisition", "acquire", "adapter_for_kind", "policy_for"]
