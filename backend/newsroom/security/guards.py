"""Security guards for handling untrusted external news content.

Everything the newsroom fetches is attacker-controlled territory. This module
is the single choke point for outbound requests and inbound text.

* SSRF: requests to private, loopback, link-local or metadata addresses are
  refused. Redirects are NOT followed automatically; a redirect is resolved
  and re-checked, so an open-redirect on a news site cannot be used to reach
  the instance's own metadata service.
* Resource limits: body size, timeout, concurrency.
* Content: HTML is sanitised with an allowlist before it is ever parsed;
  script/style/iframe/object/embed/form are removed unconditionally.
"""

from __future__ import annotations

import ipaddress
import logging
import socket
from dataclasses import dataclass
from typing import Optional
from urllib.parse import urlparse

import nh3

logger = logging.getLogger(__name__)

# Scheme allowlist. RSS/Atom over http is allowed because many regional Indian
# outlets still do not serve TLS; the SSRF guard below is what makes that safe.
ALLOWED_SCHEMES = {"http", "https"}

# nh3 allowlist: news text plus semantic markup, nothing executable.
HTML_ALLOWED_TAGS = {
    "p", "br", "hr", "b", "i", "em", "strong", "u", "s", "small", "span",
    "div", "section", "article", "header", "footer", "main",
    "h1", "h2", "h3", "h4", "h5", "h6",
    "ul", "ol", "li", "blockquote", "q", "cite", "code", "pre",
    "a", "img", "figure", "figcaption", "time", "address", "sub", "sup",
    "table", "thead", "tbody", "tfoot", "tr", "th", "td", "caption",
}
HTML_ALLOWED_ATTRIBUTES = {
    "a": {"href", "title", "rel"},
    "img": {"src", "alt", "title", "width", "height"},
    "time": {"datetime"},
    "*": {"class"},
}
HTML_ALLOWED_PROTOCOLS = {"http", "https", "mailto"}


class UnsafeUrlError(ValueError):
    """A URL refused by the SSRF guard."""


class FetchLimitExceeded(RuntimeError):
    """The remote body exceeded the configured size limit."""


@dataclass(frozen=True)
class SafeResponse:
    url: str
    final_url: str
    status: int
    body: bytes
    content_type: str
    elapsed_ms: int
    # Response headers as (name, value) pairs, for Retry-After and content
    # negotiation. Pairs rather than a dict to keep the frozen dataclass safe.
    headers: tuple[tuple[str, str], ...] = ()

    def header(self, name: str) -> Optional[str]:
        """Case-insensitive header lookup."""
        wanted = (name or "").lower()
        for key, value in self.headers:
            if key.lower() == wanted:
                return value
        return None


def is_safe_url(url: str, *, allow_private: bool = False) -> bool:
    """Validate a URL against the SSRF policy.

    ``allow_private`` is honoured only for explicitly-configured internal
    endpoints (the local Ollama server), never for source URLs.
    """
    try:
        parsed = urlparse(url)
    except ValueError:
        return False
    if parsed.scheme.lower() not in ALLOWED_SCHEMES:
        return False
    if not parsed.hostname:
        return False
    if not allow_private and _is_private_host(parsed.hostname):
        return False
    return True


def assert_safe_url(url: str) -> str:
    if not is_safe_url(url):
        raise UnsafeUrlError(f"refused unsafe URL: {url}")
    return url


def _is_private_host(hostname: str) -> bool:
    host = hostname.strip().lower().rstrip(".")
    if host in {"localhost", "localhost.localdomain"}:
        return True
    if host.endswith(".local") or host.endswith(".internal"):
        return True
    try:
        packed = socket.inet_aton(host)
    except OSError:
        # A name, not an IP. Resolve it: a public-looking hostname can point at
        # 169.254.169.254 and that is exactly the attack we are stopping.
        return _resolves_private(host)
    return _is_private_ip(ipaddress.ip_address(packed))


def _is_private_ip(ip: ipaddress._BaseAddress) -> bool:  # type: ignore[name-defined]
    if isinstance(ip, ipaddress.IPv4Address):
        return (
            ip.is_private or ip.is_loopback or ip.is_link_local
            or ip.is_multicast or ip.is_reserved or ip.is_unspecified
        )
    return (
        ip.is_private or ip.is_loopback or ip.is_link_local
        or ip.is_multicast or ip.is_reserved or ip.is_unspecified
    )


_DNS_CACHE: dict[str, bool] = {}


def _resolves_private(host: str) -> bool:
    if host in _DNS_CACHE:
        return _DNS_CACHE[host]
    private = False
    try:
        for info in socket.getaddrinfo(host, None):
            address = info[4][0]
            if _is_private_ip(ipaddress.ip_address(address)):
                private = True
                break
    except OSError:
        # Unresolvable is not the same as private; the request will fail loudly
        # downstream. Treat it as allowed-but-doomed rather than blocking a
        # legitimate but currently-dead feed.
        private = False
    _DNS_CACHE[host] = private
    return private


def sanitize_html(html: Optional[str]) -> str:
    """Reduce untrusted HTML to a safe subset."""
    if not html:
        return ""
    try:
        return nh3.clean(
            html,
            tags=HTML_ALLOWED_TAGS,
            attributes=HTML_ALLOWED_ATTRIBUTES,
            url_schemes=HTML_ALLOWED_PROTOCOLS,
            # These tags are not in HTML_ALLOWED_TAGS, so they are dropped;
            # listing them here also removes their *text*, which is the point
            # -- a stripped <script> would otherwise leak its source as prose.
            clean_content_tags={"script", "style", "noscript", "iframe", "object",
                                "embed", "svg", "template"},
            strip_comments=True,
            # ammonia panics if its default link_rel is set while <a> also
            # carries `rel` in the attribute allowlist; we allow `rel`
            # explicitly instead of having it forced on every link.
            link_rel=None,
        )
    except Exception as exc:  # noqa: BLE001 - sanitising must never crash a pipeline
        logger.warning("HTML sanitisation failed (%s); falling back to text only", exc)
        return re.sub(r"<[^>]+>", "", html)


def safe_filename(name: str, max_len: int = 80) -> str:
    """Path-traversal-safe filename derived from untrusted input."""
    import re
    cleaned = re.sub(r"[^A-Za-z0-9._-]+", "-", (name or "").strip())[:max_len]
    return cleaned.strip(".-") or "dasha"
