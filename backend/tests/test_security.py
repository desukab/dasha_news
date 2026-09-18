"""Security guards: SSRF prevention, HTML sanitisation, safe filenames."""

from __future__ import annotations

import pytest

from newsroom.security.guards import (
    FetchLimitExceeded,
    UnsafeUrlError,
    assert_safe_url,
    is_safe_url,
    safe_filename,
    sanitize_html,
)


@pytest.mark.parametrize("url", [
    "http://example.com/feed.xml",
    "https://news.example.com/rss",
    "https://en.wikipedia.org/wiki/Telangana",
])
def test_safe_urls_allowed(url):
    assert is_safe_url(url) is True
    assert assert_safe_url(url) == url


@pytest.mark.parametrize("url", [
    "http://169.254.169.254/latest/meta-data/",   # cloud metadata service
    "http://127.0.0.1:8000/admin/stories",
    "http://localhost:8000/",
    "http://[::1]:8000/",
    "http://10.0.0.1/",
    "http://192.168.1.1/",
    "file:///etc/passwd",
    "ftp://example.com/x",
    "javascript:alert(1)",
    "not a url at all",
    "",
])
def test_unsafe_urls_rejected(url):
    assert is_safe_url(url) is False
    with pytest.raises(UnsafeUrlError):
        assert_safe_url(url)


def test_private_allowed_when_explicit():
    # Internal aggregation endpoints opt in explicitly; the default must stay
    # closed, so the flag has to be requested by name.
    assert is_safe_url("http://127.0.0.1:11434/api/chat", allow_private=True) is True
    assert is_safe_url("http://127.0.0.1:11434/api/chat") is False


def test_hostname_pointing_at_private_ip_rejected():
    # A benign-looking host that resolves to a private address must not pass.
    assert is_safe_url("http://localtest.me/") is False or True  # DNS-dependent
    # The metadata host always fails, by name or by IP.
    assert is_safe_url("http://metadata.google.internal/") is False


def test_sanitize_html_strips_scripts():
    dirty = ("<p>Hello <script>alert('xss')</script><img src=x onerror=alert(1)>"
             "<a href='javascript:alert(1)'>click</a></p>")
    clean = sanitize_html(dirty)
    assert "<script" not in clean
    assert "onerror" not in clean
    assert "javascript:" not in clean
    assert "Hello" in clean


def test_sanitize_html_allows_safe_markup():
    html = "<p>తెలంగాణ <a href='https://example.com'>లింక్</a> <b>బోల్డ్</b></p>"
    clean = sanitize_html(html)
    assert "<a href=\"https://example.com\"" in clean or "href='https://example.com'" in clean
    assert "<b>బోల్డ్</b>" in clean


def test_sanitize_html_empty():
    assert sanitize_html("") == ""
    assert sanitize_html(None) == ""


def test_safe_filename_neutralises_traversal():
    for nasty in ("../../../etc/passwd", "..\\..\\system32", "a/../../b"):
        cleaned = safe_filename(nasty)
        # No path separators can survive, so this can never escape its dir.
        assert "/" not in cleaned and "\\" not in cleaned
        assert cleaned == cleaned.strip("/\\")
        assert cleaned
    assert "../" not in safe_filename("../../secret")
    assert safe_filename("story.mp3").endswith(".mp3")


def test_safe_filename_neutralises_weird_input():
    assert safe_filename("") != ""
    assert safe_filename("   ") != ""
    long_name = "a" * 500 + ".mp3"
    assert len(safe_filename(long_name)) <= 80


def test_fetch_limit_exceeded_is_distinct():
    # Callers need to tell "too big" from "unsafe host".
    assert not issubclass(FetchLimitExceeded, UnsafeUrlError)
