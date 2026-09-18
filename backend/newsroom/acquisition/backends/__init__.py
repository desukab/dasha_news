"""Fetch backends: the transport seam of the acquisition layer.

Every outbound request a source adapter makes goes through one of these, which
means the security policy lives in exactly one place regardless of transport:

* the SSRF guard runs before any request is issued;
* redirects are resolved and re-validated hop by hop, never followed blindly;
* the body is capped while streaming, not after buffering.

A backend that cannot satisfy those invariants is not a backend the newsroom
will use, however fast or clever it is.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Mapping, Optional, Protocol


@dataclass(frozen=True)
class FetchResult:
    """A completed fetch, transport-agnostic."""

    url: str
    final_url: str
    status: int
    body: bytes
    content_type: str
    elapsed_ms: int
    # Case-insensitive response headers, as (name, value) pairs. Pairs rather
    # than a dict so the frozen dataclass stays hashable and immutable.
    headers: tuple[tuple[str, str], ...] = ()

    def header(self, name: str) -> Optional[str]:
        """Case-insensitive header lookup."""
        wanted = (name or "").lower()
        for key, value in self.headers:
            if key.lower() == wanted:
                return value
        return None

    @property
    def text(self) -> str:
        """Body decoded as UTF-8, replacing undecodable bytes.

        Indian outlets frequently serve Telugu without a charset declaration, so
        a strict decode would turn a valid page into mojibake.
        """
        return (self.body or b"").decode("utf-8", "replace")

    @property
    def is_ok(self) -> bool:
        return self.status == 200 and bool(self.body)


class FetchBackend(Protocol):
    """A transport used to reach one or more sources."""

    name: str

    def fetch(self, url: str, *, max_bytes: Optional[int] = None,
              timeout_seconds: Optional[float] = None) -> FetchResult:
        """Fetch ``url`` under the newsroom's security policy."""
        ...

    def close(self) -> None:
        """Release any transport-level resources (connections, browser)."""
        ...


@dataclass
class BackendUnavailable(RuntimeError):
    """An optional backend was requested but its dependency is not installed.

    Raised rather than silently falling back, so an operator who configured a
    source for a browser backend finds out in the log instead of wondering why
    extraction quality dropped.
    """

    backend: str
    reason: str = ""

    def __str__(self) -> str:  # pragma: no cover - message only
        hint = f": {self.reason}" if self.reason else ""
        return (f"fetch backend {self.backend!r} is not available{hint}. "
                f"Install the optional acquisition extra to enable it.")


_BACKENDS: dict[str, str] = {
    "httpx": "newsroom.acquisition.backends.httpx_backend",
    "scrapling": "newsroom.acquisition.backends.scrapling_backend",
    "scrapling-dynamic": "newsroom.acquisition.backends.scrapling_backend",
}


def available_backends() -> Mapping[str, str]:
    """Backends the newsroom knows how to build, by name."""
    return dict(_BACKENDS)


def installed_backends() -> set[str]:
    """Backends whose dependencies are actually importable right now.

    httpx is part of the core install; the Scrapling backends need the optional
    acquisition extra. Surfaced in the admin console so an operator can see the
    difference between "configured" and "working" before blaming a source.
    """
    ready: set[str] = set()
    for name, module_name in _BACKENDS.items():
        try:
            __import__(module_name, fromlist=["__name__"])
        except ImportError:
            continue
        ready.add(name)
    return ready


def backend_module_name(name: str) -> Optional[str]:
    """The import path of a named backend, or ``None`` if unknown."""
    return _BACKENDS.get((name or "").strip().lower())


__all__: list[str] = ["BackendUnavailable", "FetchBackend", "FetchResult",
                      "available_backends", "backend_module_name",
                      "installed_backends"]
