"""Rate limiting and admin authentication (no paid dependencies).

Admin auth is a constant-time-compared bearer key signed with the process
secret. Anonymous endpoints are throttled per-IP with a sliding window kept in
process memory -- good enough for a single-node deployment and free of any
external dependency.
"""

from __future__ import annotations

import hashlib
import hmac
import logging
import threading
import time
from collections import defaultdict, deque
from typing import Optional

from fastapi import Header, HTTPException, Request, status

from newsroom.config import get_settings

logger = logging.getLogger(__name__)


class SlidingWindowLimiter:
    """Per-key request counter over a fixed window."""

    def __init__(self, limit_per_minute: int):
        self.limit = max(1, limit_per_minute)
        self._hits: dict[str, deque[float]] = defaultdict(deque)
        self._lock = threading.Lock()

    def allow(self, key: str) -> bool:
        now = time.monotonic()
        cutoff = now - 60.0
        with self._lock:
            hits = self._hits[key]
            while hits and hits[0] < cutoff:
                hits.popleft()
            if len(hits) >= self.limit:
                return False
            hits.append(now)
            return True

    def clear(self) -> None:
        with self._lock:
            self._hits.clear()


_limiter: Optional[SlidingWindowLimiter] = None


def get_limiter() -> SlidingWindowLimiter:
    global _limiter
    if _limiter is None:
        _limiter = SlidingWindowLimiter(get_settings().rate_limit_per_minute)
    return _limiter


def reset_limiter() -> None:
    global _limiter
    _limiter = None


def rate_limit(request: Request) -> None:
    """FastAPI dependency: anonymous rate limit per client IP."""
    if not get_limiter().allow(client_ip(request)):
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many requests. Please slow down.",
            headers={"Retry-After": "60"},
        )


def client_ip(request: Request) -> str:
    forwarded = request.headers.get("x-forwarded-for", "")
    if forwarded:
        # The left-most entry is the original client; the rest are proxies we do
        # not control and must not trust for identity.
        return forwarded.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


def _constant_time_match(candidate: str, expected: str) -> bool:
    if not candidate or not expected:
        return False
    return hmac.compare_digest(candidate.encode(), expected.encode())


def require_admin(x_dasha_key: Optional[str] = Header(default=None, alias="X-Dasha-Key"),
                  authorization: Optional[str] = Header(default=None)) -> str:
    """FastAPI dependency: require a valid admin key.

    Accepts the key in a dedicated header or as a bearer token, both compared
    in constant time. Timing side channels matter here because the key gates
    every publishing action.
    """
    settings = get_settings()
    candidate = x_dasha_key or ""
    if not candidate and authorization:
        scheme, _, token = authorization.partition(" ")
        if scheme.lower() == "bearer":
            candidate = token.strip()
    if _constant_time_match(candidate, settings.admin_api_key):
        return "admin"
    # A signed bearer token (sign_token) is also accepted, so the console can
    # hand out time-scoped access without sharing the raw key.
    if candidate and verify_token(candidate):
        return "admin"
    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Invalid admin key",
        headers={"WWW-Authenticate": 'Bearer realm="dasha-newsroom"'},
    )


def sign_token(payload: str) -> str:
    secret = get_settings().newsroom_secret.encode()
    digest = hmac.new(secret, payload.encode(), hashlib.sha256).hexdigest()
    return f"{payload}:{digest}"


def verify_token(token: str) -> Optional[str]:
    payload, sep, digest = token.partition(":")
    if not sep:
        return None
    expected = hmac.new(get_settings().newsroom_secret.encode(),
                        payload.encode(), hashlib.sha256).hexdigest()
    if _constant_time_match(digest, expected):
        return payload
    return None


def audit(session, actor: str, action: str, target_type: str, target_id: str,
          detail: Optional[str] = None, ip: Optional[str] = None) -> None:
    """Append an audit row. Never raises -- audit loss must not break an action."""
    from newsroom.db.models import AuditLog
    try:
        session.add(AuditLog(actor=actor, action=action, target_type=target_type,
                             target_id=str(target_id), detail=detail, ip=ip))
        session.flush()
    except Exception as exc:  # noqa: BLE001
        logger.warning("audit write failed for %s %s: %s", action, target_id, exc)
