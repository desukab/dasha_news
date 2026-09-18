"""Application configuration.

Every setting has a working default, so the newsroom boots with no paid
credentials and no external services. Secrets are read from the environment
only -- never from the repository.
"""

from __future__ import annotations

import os
from functools import lru_cache
from pathlib import Path
from typing import List

from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

REPO_ROOT = Path(__file__).resolve().parents[2]
BACKEND_ROOT = Path(__file__).resolve().parents[1]


_SHIPPED_PLACEHOLDER = "change-me"


class Settings(BaseSettings):
    """Strongly-typed view of the process environment."""

    model_config = SettingsConfigDict(
        env_file=str(BACKEND_ROOT / ".env"),
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    # ---- Runtime datastore -------------------------------------------------
    database_kind: str = "sqlite"
    database_url: str = "postgresql+psycopg://user:password@localhost:5432/dasha_news"

    # ---- Server ------------------------------------------------------------
    host: str = "0.0.0.0"
    port: int = 8000
    public_base_url: str = "http://localhost:8000"
    cors_origins: str = "*"

    # ---- Security ----------------------------------------------------------
    newsroom_secret: str = "change-me-to-a-long-random-string"
    admin_api_key: str = "change-me-admin-key"
    fetch_max_bytes: int = 5_242_880
    fetch_timeout_seconds: int = 20
    fetch_max_retries: int = 2
    rate_limit_per_minute: int = 120
    # How long an editor session token is worth. The editor app holds a token,
    # not a password, and a stolen token should expire while the phone it was
    # issued to is still in use.
    session_token_ttl_hours: int = 720  # 30 days
    # Password stretching iterations. PBKDF2-HMAC-SHA256 at 200k is roughly
    # 100ms on this VM, which is a deliberate cost: the editor accounts are the
    # high-value target, and the login rate limit means an honest user never
    # notices it.
    pbkdf2_iterations: int = 200_000

    # ---- Editorial bootstrap ----------------------------------------------
    # The first editor account is created from these *only* when the users
    # table is empty, and never again after. Nothing is hard-coded: without
    # both values the newsroom simply starts with no editors and the operator
    # makes one out of band.
    bootstrap_editor_email: str = ""
    bootstrap_editor_password: str = ""

    # ---- Acquisition politeness -------------------------------------------
    # The newsroom is a guest on someone else's server. robots.txt is read and
    # obeyed before any content request, and requests to one host are paced.
    # Both can be turned off for a hermetic test run; neither should be off in
    # production.
    respect_robots_txt: bool = True
    politeness_min_interval_seconds: float = 6.0
    # Browser automation (Scrapling's DynamicFetcher) is opt-in twice: a source
    # must set requires_js AND the operator must enable it here. It is the most
    # expensive thing the newsroom can do per article, so it never starts
    # unless someone has explicitly asked for it.
    browser_fetch_enabled: bool = False

    # ---- AI provider -------------------------------------------------------
    ai_provider: str = "heuristic"
    ollama_base_url: str = "http://localhost:11434"
    ollama_model: str = "qwen2.5:7b"
    openai_base_url: str = "https://api.openai.com/v1"
    openai_model: str = "gpt-4o-mini"
    openai_api_key: str = ""

    # ---- Newsroom automation ----------------------------------------------
    pipeline_interval_seconds: int = 300
    auto_publish_enabled: bool = True
    auto_publish_min_evidence: float = 0.55
    sensitive_categories_hold: str = "crime,courts,accidents,unverified"
    raw_retention_days: int = 14

    # ---- Media -------------------------------------------------------------
    media_dir: str = "backend/media"
    image_sources: str = "wikimedia,unsplash,pexels,generated"

    # ---- Audio -------------------------------------------------------------
    tts_engine: str = "espeak"
    tts_voice_te: str = "female"
    tts_voice_en: str = "male"
    tts_rate: int = 160

    # ---- Notifications -----------------------------------------------------
    notifier_transport: str = "none"
    fcm_server_key: str = ""

    # ---- Optional stock-photo credentials ---------------------------------
    pexels_api_key: str = ""
    unsplash_access_key: str = ""

    # ---- Derived -----------------------------------------------------------
    @property
    def resolved_media_dir(self) -> Path:
        path = Path(self.media_dir)
        if not path.is_absolute():
            path = REPO_ROOT / path
        path.mkdir(parents=True, exist_ok=True)
        (path / "audio").mkdir(exist_ok=True)
        (path / "shorts").mkdir(exist_ok=True)
        (path / "images").mkdir(exist_ok=True)
        return path

    @property
    def sqlite_path(self) -> Path:
        # An explicit sqlite URL wins: it lets tests (and operators) place the
        # file anywhere without changing the media-relative default.
        url = self.database_url.strip()
        if url.lower().startswith("sqlite:///") and self.database_kind.lower() != "postgresql":
            path = url.split("///", 1)[1]
            if path:
                return Path(path)
        data_dir = BACKEND_ROOT / "data"
        data_dir.mkdir(parents=True, exist_ok=True)
        return data_dir / "dasha_news.db"

    @property
    def effective_database_url(self) -> str:
        if self.database_kind.lower() == "postgresql":
            return self.database_url
        return f"sqlite:///{self.sqlite_path}"

    @property
    def cors_origin_list(self) -> List[str]:
        if self.cors_origins.strip() in ("*", ""):
            return ["*"]
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]

    @property
    def sensitive_category_set(self) -> set:
        return {c.strip() for c in self.sensitive_categories_hold.split(",") if c.strip()}

    @field_validator("ai_provider")
    @classmethod
    def _validate_provider(cls, value: str) -> str:
        allowed = {"heuristic", "ollama", "openai"}
        normalized = (value or "heuristic").strip().lower()
        if normalized not in allowed:
            raise ValueError(f"ai_provider must be one of {sorted(allowed)}")
        return normalized

    def admin_key_is_placeholder(self) -> bool:
        """The admin key is the value shipped in the public source tree.

        A placeholder here is not merely weak -- it is published. Anyone who
        reads this repository knows it, so it cannot authenticate anything.
        """
        return self.admin_api_key.startswith(_SHIPPED_PLACEHOLDER)

    def newsroom_secret_is_placeholder(self) -> bool:
        """The HMAC secret is the value shipped in the public source tree.

        Token signatures are only worth anything if the secret is private; with
        the shipped value, a signed admin token is forgeable from the source.
        """
        return self.newsroom_secret.startswith(_SHIPPED_PLACEHOLDER)

    def warn_on_insecure_defaults(self) -> List[str]:
        """Problems that should be fixed in production but never block boot."""
        problems: List[str] = []
        if self.newsroom_secret_is_placeholder():
            problems.append("NEWSROOM_SECRET is still the shipped placeholder")
        if self.admin_key_is_placeholder():
            problems.append("ADMIN_API_KEY is still the shipped placeholder")
        if self.database_kind.lower() == "sqlite":
            problems.append("SQLite is fine for single-node use; use PostgreSQL for HA")
        return problems


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """Cached settings accessor (test isolation uses `settings.cache_clear`)."""
    return Settings()  # pragma: no cover - exercised indirectly everywhere


def env_flag(name: str, default: bool = False) -> bool:
    raw = os.environ.get(name, "").strip().lower()
    if not raw:
        return default
    return raw in {"1", "true", "yes", "on"}
