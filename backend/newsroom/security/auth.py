"""Rate limiting, password verification and request authentication.

No paid dependencies. Two kinds of caller reach the API:

* **Readers** never authenticate. Their personalisation hangs off an anonymous
  device id, and their endpoints are rate-limited per IP.
* **The newsroom** authenticates as a user with a role. Passwords are stored
  only as PBKDF2 hashes with per-row salts; a request carries a signed session
  token whose payload names the user and an expiry, and role checks happen
  server-side on every mutating endpoint -- the app hiding a button is
  decoration, not authorisation.

The legacy single admin key remains for the operator console and for scripts;
it is not what the editor app uses.
"""

from __future__ import annotations

import hashlib
import hmac
import logging
import secrets
import threading
import time
from collections import defaultdict, deque
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import Depends, Header, HTTPException, Request, status
from sqlalchemy import select

from newsroom.config import get_settings
from newsroom.db.engine import get_db

logger = logging.getLogger(__name__)

_ALGORITHM = "pbkdf2_sha256"
_TOKEN_SEP = "|"
_LOGIN_FAILURE_LIMIT = 10


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
    # Fail closed. The shipped placeholders are published in the source tree,
    # so while they are still in force the admin boundary does not exist at
    # all: the key is guessable, and a signed token is forgeable with the known
    # secret. A startup warning says the same thing, but a warning that still
    # lets the request through is not a control. The newsroom keeps serving
    # readers; only admin access is refused until the operator sets real ones.
    if settings.admin_key_is_placeholder() or settings.newsroom_secret_is_placeholder():
        logger.error(
            "Refusing admin access: ADMIN_API_KEY and/or NEWSROOM_SECRET are still "
            "the shipped placeholders. Set both before the newsroom can be "
            "administered through this API."
        )
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="The newsroom is not configured for admin access.",
        )
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


# ---------------------------------------------------------------------------
# Passwords: stored only as a salted PBKDF2 hash.
# ---------------------------------------------------------------------------

def hash_password(password: str, *, iterations: Optional[int] = None) -> str:
    """Salt and stretch a password. Never returns or logs the plaintext."""
    if not password:
        raise ValueError("a password is required")
    settings = get_settings()
    iterations = iterations or settings.pbkdf2_iterations
    salt = secrets.token_hex(16)
    digest = hashlib.pbkdf2_hmac(
        "sha256", password.encode("utf-8"), salt.encode("utf-8"), iterations)
    return f"{_ALGORITHM}${iterations}${salt}${digest.hex()}"


def verify_password(password: str, stored: Optional[str]) -> bool:
    """Check a password against a stored hash, in constant time.

    Returns False for any stored value that is not in the format we write --
    including a plaintext someone may have pasted into the column by mistake,
    which is never accepted as a match.
    """
    if not password or not stored:
        return False
    parts = stored.split("$")
    if len(parts) != 4 or parts[0] != _ALGORITHM:
        return False
    try:
        iterations = int(parts[1])
    except ValueError:
        return False
    salt, expected = parts[2], parts[3]
    digest = hashlib.pbkdf2_hmac(
        "sha256", password.encode("utf-8"), salt.encode("utf-8"), iterations)
    return hmac.compare_digest(digest.hex(), expected)


# ---------------------------------------------------------------------------
# Session tokens: signed, expiry-bound, revocable.
# ---------------------------------------------------------------------------

def issue_token(user_id: int, *, ttl_hours: Optional[int] = None) -> tuple[str, datetime]:
    """A signed token for a user, plus the moment it stops being valid.

    The token is what the editor app keeps, so it carries no password and no
    role: the role is read from the user row on every request, which is why
    promoting or suspending someone takes effect immediately instead of when
    their token happens to expire. The issue time is in the payload so that a
    revocation can invalidate tokens already in the field.
    """
    settings = get_settings()
    now = datetime.now(timezone.utc)
    expires_at = now + timedelta(
        hours=ttl_hours if ttl_hours is not None else settings.session_token_ttl_hours)
    payload = f"{user_id}{_TOKEN_SEP}{int(now.timestamp())}{_TOKEN_SEP}{int(expires_at.timestamp())}"
    return f"{payload}{_TOKEN_SEP}{_signature(payload)}", expires_at


def _signature(payload: str) -> str:
    return hmac.new(get_settings().newsroom_secret.encode("utf-8"),
                    payload.encode("utf-8"), hashlib.sha256).hexdigest()


def decode_token(token: Optional[str]):
    """(user_id, issued_at, expires_at) for a valid, unexpired token, else None."""
    if not token:
        return None
    payload, _, signature = token.rpartition(_TOKEN_SEP)
    if not signature or not hmac.compare_digest(signature, _signature(payload)):
        return None
    parts = payload.split(_TOKEN_SEP)
    if len(parts) != 3:
        return None
    try:
        user_id = int(parts[0])
        issued_at = datetime.fromtimestamp(int(parts[1]), tz=timezone.utc)
        expires_at = datetime.fromtimestamp(int(parts[2]), tz=timezone.utc)
    except ValueError:
        return None
    if expires_at <= datetime.now(timezone.utc):
        return None
    return user_id, issued_at, expires_at


class LoginRateLimiter:
    """Per-account throttle on guesses, because PBKDF2 is slow but not slow
    enough to stop an unbounded online attack.

    Held in process memory like the anonymous limiter: single-node, free, and
    reset by a restart, which is fine -- the password is the secret, this just
    blunts brute force against one account.
    """

    def __init__(self) -> None:
        self._failures: dict[str, list[float]] = defaultdict(list)
        self._lock = threading.Lock()

    def is_blocked(self, key: str) -> bool:
        now = time.monotonic()
        cutoff = now - 3600.0
        with self._lock:
            hits = [h for h in self._failures.get(key, ()) if h > cutoff]
            self._failures[key] = hits
            return len(hits) >= _LOGIN_FAILURE_LIMIT

    def record_failure(self, key: str) -> None:
        with self._lock:
            self._failures.setdefault(key, []).append(time.monotonic())

    def record_success(self, key: str) -> None:
        with self._lock:
            self._failures.pop(key, None)


_login_limiter = LoginRateLimiter()


def login_rate_limiter() -> LoginRateLimiter:
    return _login_limiter


def reset_login_limiter() -> None:
    global _login_limiter
    _login_limiter = LoginRateLimiter()


# ---------------------------------------------------------------------------
# Request authentication: who is asking, and may they?
# ---------------------------------------------------------------------------

def _request_token(request: Request) -> Optional[str]:
    """A token arrives as a bearer credential or in our own header.

    The dedicated header matters because a browser fetch cannot always set
    ``Authorization`` from a mobile webview, and the editor app runs there.
    """
    authorization = request.headers.get("authorization") or ""
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() == "bearer" and token:
        return token.strip()
    header = request.headers.get("x-dasha-token")
    return header.strip() if header else None


def current_user(request: Request, session=Depends(get_db)) -> Optional["User"]:
    """Resolve the signed token to a live user row, or None.

    A token that verifies still authorises nothing if the account was
    suspended, if every token for it was revoked after it was issued, or if
    this specific token was killed by a logout -- the revocation wall clock
    must reach tokens already in the field, not only ones issued later.
    """
    from newsroom.db.models import RevokedToken, User

    token = _request_token(request)
    decoded = decode_token(token)
    if decoded is None:
        return None
    user_id, issued_at, expires_at = decoded
    user = session.get(User, user_id)
    if user is None or not user.is_active:
        return None
    if user.tokens_revoked_at is not None:
        # The datastore stores wall-clock UTC without a timezone, as the rest
        # of the codebase does; the token carries an aware timestamp, so the
        # comparison happens in one zone before anything is rejected.
        revoked = user.tokens_revoked_at
        if revoked.tzinfo is None:
            revoked = revoked.replace(tzinfo=timezone.utc)
        if issued_at <= revoked:
            return None
    signature = _signature_of(token)
    if signature is not None and session.execute(
        select(RevokedToken.id).where(RevokedToken.signature == signature)
    ).first() is not None:
        return None
    return user


def revoke_token(request: Request, session) -> bool:
    """Kill the token on this request, so logout actually logs out.

    Returns whether a revokable token was present.
    """
    from newsroom.db.models import RevokedToken

    token = _request_token(request)
    decoded = decode_token(token)
    if decoded is None:
        return False
    signature = _signature_of(token)
    if signature is None:
        return False
    session.add(RevokedToken(
        signature=signature, user_id=decoded[0],
        expires_at=datetime.fromtimestamp(decoded[2].timestamp(), tz=timezone.utc)
        if decoded[2].tzinfo else decoded[2]))
    return True


def sweep_expired_tokens(session) -> int:
    """Drop revocations whose tokens have already expired on their own."""
    from newsroom.db.models import RevokedToken

    result = session.execute(
        RevokedToken.__table__.delete().where(
            RevokedToken.expires_at <= datetime.now(timezone.utc))
    )
    return result.rowcount or 0


def _signature_of(token: Optional[str]) -> Optional[str]:
    """A short, irreversible handle for a token, for the revocation index."""
    if not token:
        return None
    return hashlib.sha256(token.encode("utf-8")).hexdigest()[:64]


def require_user(request: Request, session=Depends(get_db)):
    """Any authenticated newsroom account."""
    user = current_user(request, session)
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="A valid newsroom session is required",
            headers={"WWW-Authenticate": 'Bearer realm="dasha-newsroom"'},
        )
    return user


def require_editor(request: Request, session=Depends(get_db)):
    """An account allowed to change what the newsroom publishes.

    Enforced here, in the request path, because it must not depend on the app
    choosing to hide a control. An editor can write and edit; managing
    accounts and sources is admin-only.
    """
    user = require_user(request, session)
    if not user.is_editor:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="This action needs editor privileges",
        )
    return user


def require_admin_user(request: Request, session=Depends(get_db)):
    """An account allowed to manage accounts and sources."""
    user = require_user(request, session)
    if not user.is_admin:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="This action needs administrator privileges",
        )
    return user
