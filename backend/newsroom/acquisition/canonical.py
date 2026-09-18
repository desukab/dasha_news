"""URL canonicalisation.

Two articles about the same event are often reachable at several URLs: an AMP
variant, a tracking-parameter-laden social share, a case-differing host. The
deduplicator needs one comparable form per URL.

The canonical form is a *comparison key*, not the URL the newsroom links back
to. The original URL is always preserved on the Article, because the reader must
be sent to the outlet's own page and the outlet is the copyright holder.
"""

from __future__ import annotations

from urllib.parse import urljoin, urlsplit, urlunsplit

# Parameters that identify a *distribution channel*, not an article. Removing
# them merges social shares, newsletters and AMP redirects with the canonical
# page. Anything not in this set is kept, because query strings are often the
# only thing distinguishing two genuinely different articles on one outlet.
_TRACKING_PARAMETERS = frozenset({
    "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
    "utm_id", "utm_name", "utm_referrer", "utm_social", "utm_social-type",
    "fbclid", "gclid", "gclsrc", "dclid", "msclkid", "yclid", "twclid",
    "mc_cid", "mc_eid", "_hsenc", "_hsmi", "hsCtaTracking", "ref", "ref_src",
    "ref_url", "source", "cmpid", "cmp", "sr_share", "elqTrackId", "feature",
    "output", "amp", "__twitter_impression", "soc_src", "social-type",
    "share", "shared", "from", "isMobile", "ncid", "cid", "em", "tp",
})

# A path ending in one of these is an alternate *rendering* of the same article
# rather than a different article.
_AMP_SUFFIXES = ("/amp", "/amp/", "/amp.html", "/mobile/", "/m/")
_DEFAULT_PORTS = {"http": 80, "https": 443}


def canonicalise_url(url: str, *, base: str = "") -> str:
    """Reduce ``url`` to a form that is stable across distribution variants.

    Returns an empty string for input that is not a usable absolute URL, so
    callers can treat it as "no opinion" rather than catching an exception.
    """
    if not url or not isinstance(url, str):
        return ""

    candidate = url.strip()
    if base and not candidate.startswith(("http://", "https://")):
        candidate = urljoin(base, candidate)
    if not candidate.startswith(("http://", "https://")):
        return ""

    parts = urlsplit(candidate)
    if not parts.netloc:
        return ""

    scheme = parts.scheme.lower()
    host = parts.netloc.lower()
    # Strip the default port so example.com:443 == example.com, but keep a
    # non-default one, which may genuinely be a different site.
    if ":" in host:
        name, _, port = host.partition(":")
        if _is_default_port(scheme, port):
            host = name

    path = _de_amp(parts.path)
    query = _drop_tracking(parts.query)
    return urlunsplit((scheme, host, path, query, ""))  # fragment always dropped


def _is_default_port(scheme: str, port: str) -> bool:
    try:
        return _DEFAULT_PORTS.get(scheme) == int(port)
    except ValueError:
        return False


def _de_amp(path: str) -> str:
    if not path or path == "/":
        return path
    lowered = path.lower()
    for suffix in _AMP_SUFFIXES:
        if lowered.endswith(suffix):
            stripped = path[: -len(suffix)]
            return stripped if stripped else "/"
    # /news/amp/story -> /news/story
    if "/amp/" in lowered:
        segments = path.split("/")
        cleaned = [s for s in segments if s.lower() != "amp"]
        path = "/".join(cleaned)
    return path if path.startswith("/") else "/" + path


def _drop_tracking(query: str) -> str:
    if not query:
        return ""
    kept = [
        pair for pair in query.split("&")
        if pair and pair.split("=", 1)[0].lower() not in _TRACKING_PARAMETERS
    ]
    return "&".join(kept)


def urls_equivalent(left: str, right: str, *, base: str = "") -> bool:
    """True when two URLs are distribution variants of one another."""
    canonical_left = canonicalise_url(left, base=base)
    canonical_right = canonicalise_url(right, base=base)
    if canonical_left and canonical_right:
        return canonical_left == canonical_right
    # Fall back to the legacy behaviour so a URL that cannot be canonicalised
    # is still compared rather than silently treated as distinct.
    return bool(left and right and left.split("?")[0] == right.split("?")[0])
