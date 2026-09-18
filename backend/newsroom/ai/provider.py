"""Provider-agnostic LLM access.

The newsroom is *provider-abstract*: every stage that can use a model goes
through :func:`complete`, and the concrete backend is chosen by ``AI_PROVIDER``.

Three backends ship:

``heuristic`` (default)
    No model at all. Every stage has a deterministic fallback implemented in
    this repository, so the product is fully functional with zero external
    calls and zero cost. This is the "local AI" guarantee.
``ollama``
    A local Ollama HTTP endpoint (``OLLAMA_BASE_URL``). Free and offline once
    the model is pulled.
``openai``
    Any OpenAI-compatible endpoint (OpenAI, Groq, Together, vLLM, llama.cpp
    server, ...). Requires ``OPENAI_API_KEY`` when the endpoint needs one.

Prompt-injection hardening lives here rather than in each stage: model output
is always parsed back into structured Python objects, never executed, never
concatenated into a shell command or SQL statement, and never shown to a user
without being re-validated.
"""

from __future__ import annotations

import json
import logging
import re
import time
from dataclasses import dataclass, field
from typing import Any, Callable, Dict, List, Optional

import httpx

from newsroom.config import get_settings

logger = logging.getLogger(__name__)

MAX_OUTPUT_TOKENS = 900
REQUEST_TIMEOUT_SECONDS = 60

_SYSTEM = (
    "You are the Dasha News newsroom assistant. You write original, factual "
    "journalistic summaries in Telugu, Tenglish and English. You NEVER copy "
    "more than a short quoted fragment from a source. You NEVER invent facts, "
    "numbers, names or quotes. If a fact is not supported by the provided "
    "material you say so. You output only what the user's format asks for."
)


@dataclass
class CompletionResult:
    """One model completion plus the audit fields the newsroom records."""

    text: str
    provider: str
    model: str
    tokens_in: int = 0
    tokens_out: int = 0
    duration_ms: int = 0
    success: bool = True
    error: Optional[str] = None
    raw: Optional[Dict[str, Any]] = field(default=None, repr=False)


class AiProvider:
    """Common interface for every backend."""

    name = "base"

    def complete(self, prompt: str, *, system: str = _SYSTEM, stage: str = "generic",
                 story_id: Optional[int] = None, max_tokens: int = MAX_OUTPUT_TOKENS,
                 temperature: float = 0.4) -> CompletionResult:
        raise NotImplementedError


class HeuristicProvider(AiProvider):
    """The zero-cost default: no model, deterministic templates.

    Stages that ask for a completion are expected to check
    :func:`is_heuristic` first and use their own algorithm instead. This
    provider exists so the call path is exercised and audited even when no
    model is configured.
    """

    name = "heuristic"

    def complete(self, prompt: str, **_: Any) -> CompletionResult:
        raise AiUnavailable("heuristic provider does not generate prose; "
                            "stages must use their deterministic fallback")


class OllamaProvider(AiProvider):
    name = "ollama"

    def __init__(self, base_url: str, model: str, timeout: int = REQUEST_TIMEOUT_SECONDS):
        self.base_url = base_url.rstrip("/")
        self.model = model
        self.timeout = timeout

    def complete(self, prompt: str, *, system: str = _SYSTEM, stage: str = "generic",
                 story_id: Optional[int] = None, max_tokens: int = MAX_OUTPUT_TOKENS,
                 temperature: float = 0.4) -> CompletionResult:
        started = time.monotonic()
        url = f"{self.base_url}/api/chat"
        payload = {
            "model": self.model,
            "stream": False,
            "options": {"temperature": temperature, "num_predict": max_tokens},
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": prompt},
            ],
        }
        try:
            response = _http().post(url, json=payload, timeout=self.timeout)
            response.raise_for_status()
            data = response.json()
        except Exception as exc:  # noqa: BLE001 - reported, never fatal
            return _failure(self, prompt, exc, started, stage, story_id)
        text = str(data.get("message", {}).get("content", "") or "")
        return CompletionResult(
            text=sanitize_model_output(text),
            provider=self.name,
            model=self.model,
            tokens_in=int(data.get("prompt_eval_count", 0) or 0),
            tokens_out=int(data.get("eval_count", 0) or 0),
            duration_ms=int((time.monotonic() - started) * 1000),
            raw=data,
        )


class OpenAiCompatibleProvider(AiProvider):
    name = "openai"

    def __init__(self, base_url: str, model: str, api_key: str,
                 timeout: int = REQUEST_TIMEOUT_SECONDS):
        self.base_url = base_url.rstrip("/")
        self.model = model
        self.api_key = api_key
        self.timeout = timeout

    def complete(self, prompt: str, *, system: str = _SYSTEM, stage: str = "generic",
                 story_id: Optional[int] = None, max_tokens: int = MAX_OUTPUT_TOKENS,
                 temperature: float = 0.4) -> CompletionResult:
        started = time.monotonic()
        url = f"{self.base_url}/chat/completions"
        payload = {
            "model": self.model,
            "temperature": temperature,
            "max_tokens": max_tokens,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": prompt},
            ],
        }
        headers = {"Content-Type": "application/json"}
        if self.api_key:
            headers["Authorization"] = f"Bearer {self.api_key}"
        try:
            response = _http().post(url, json=payload, headers=headers, timeout=self.timeout)
            response.raise_for_status()
            data = response.json()
        except Exception as exc:  # noqa: BLE001 - reported, never fatal
            return _failure(self, prompt, exc, started, stage, story_id)
        try:
            text = data["choices"][0]["message"]["content"]
        except (KeyError, IndexError, TypeError):
            return CompletionResult(
                text="", provider=self.name, model=self.model,
                duration_ms=int((time.monotonic() - started) * 1000),
                success=False, error="malformed completion response", raw=data,
            )
        usage = data.get("usage", {}) or {}
        return CompletionResult(
            text=sanitize_model_output(text),
            provider=self.name,
            model=self.model,
            tokens_in=int(usage.get("prompt_tokens", 0) or 0),
            tokens_out=int(usage.get("completion_tokens", 0) or 0),
            duration_ms=int((time.monotonic() - started) * 1000),
            raw=data,
        )


class AiUnavailable(RuntimeError):
    """Raised when a stage requires a model but none is configured."""


_http_client: Optional[httpx.Client] = None


def _http() -> httpx.Client:
    global _http_client
    if _http_client is None:
        _http_client = httpx.Client(follow_redirects=False)
    return _http_client


def _failure(provider: AiProvider, prompt: str, exc: BaseException, started: float,
             stage: str, story_id: Optional[int]) -> CompletionResult:
    logger.warning("AI call failed (%s/%s): %s", provider.name, stage, exc)
    return CompletionResult(
        text="", provider=provider.name, model=getattr(provider, "model", ""),
        duration_ms=int((time.monotonic() - started) * 1000),
        success=False, error=repr(exc)[:400],
    )


# ---------------------------------------------------------------------------
# Construction + audit
# ---------------------------------------------------------------------------

_provider: Optional[AiProvider] = None


def get_provider() -> AiProvider:
    """Return the configured provider, constructing it on first use."""
    global _provider
    if _provider is None:
        settings = get_settings()
        kind = settings.ai_provider
        if kind == "ollama":
            _provider = OllamaProvider(settings.ollama_base_url, settings.ollama_model)
        elif kind == "openai":
            if not settings.openai_api_key and "openai.com" in settings.openai_base_url:
                # Fall back rather than fail: the product must never hard-require
                # a paid credential.
                logger.warning(
                    "AI_PROVIDER=openai but OPENAI_API_KEY is empty; "
                    "falling back to the deterministic heuristic provider")
                _provider = HeuristicProvider()
            else:
                _provider = OpenAiCompatibleProvider(
                    settings.openai_base_url, settings.openai_model, settings.openai_api_key)
        else:
            _provider = HeuristicProvider()
        logger.info("AI provider: %s", _provider.name)
    return _provider


def reset_provider() -> None:
    """Test hook."""
    global _provider
    _provider = None


def is_heuristic() -> bool:
    return get_provider().name == "heuristic"


def record_call(result: CompletionResult, stage: str,
                story_id: Optional[int], session) -> None:
    """Persist the audit row for one model call."""
    from newsroom.db.models import AiCall
    session.add(AiCall(
        provider=result.provider, model=result.model, stage=stage,
        story_id=story_id, tokens_in=result.tokens_in,
        tokens_out=result.tokens_out, duration_ms=result.duration_ms,
        success=result.success, error=result.error,
    ))


# ---------------------------------------------------------------------------
# Output hardening
# ---------------------------------------------------------------------------

_FORBIDDEN_MARKUP = re.compile(r"<\s*(script|iframe|object|embed|link|style|meta)\b",
                               re.IGNORECASE)
_EVENT_HANDLER = re.compile(r"on\w+\s*=", re.IGNORECASE)
_CONTROL_CHARS = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")


def sanitize_model_output(text: str) -> str:
    """Make model output safe to store and render.

    Models are fed untrusted source text and can echo it back. Output is never
    trusted as structure: control characters are dropped, javascript: URIs and
    inline event handlers are neutralised, and balanced-code-fence extraction
    is applied by the caller where structured data is expected.
    """
    if not text:
        return ""
    out = _CONTROL_CHARS.sub("", text)
    out = _EVENT_HANDLER.sub("data-handler-removed=", out)
    out = re.sub(r"javascript\s*:", "blocked:", out, flags=re.IGNORECASE)
    out = _FORBIDDEN_MARKDOWN_ESCAPE.sub(_escape_tag, out)
    return out.strip()


_FORBIDDEN_MARKDOWN_ESCAPE = re.compile(r"<(?!/?[a-zA-Z0-9])")


def _escape_tag(match: re.Match) -> str:
    return "&lt;" + match.group(0)[1:]


def extract_code_block(text: str) -> str:
    """Return the content of the first fenced code block, or the whole text.

    Models are asked for JSON; this isolates it from surrounding chatter
    without executing anything.
    """
    if not text:
        return ""
    fences = re.findall(r"```(?:json)?\s*(.*?)```", text, re.DOTALL)
    if fences:
        return fences[0].strip()
    return text.strip()


def parse_json_object(text: str) -> Optional[Dict[str, Any]]:
    """Parse model output as a JSON object, tolerating trailing commas.

    Returns ``None`` when the output is not valid JSON. Callers must treat that
    as "the model produced nothing usable" and fall back.
    """
    candidate = extract_code_block(text)
    if not candidate:
        return None
    candidate = candidate.strip()
    if not candidate.startswith(("{", "[")):
        return None
    try:
        return json.loads(candidate)
    except json.JSONDecodeError:
        pass
    try:
        return json.loads(re.sub(r",\s*([}\]])", r"\1", candidate))
    except json.JSONDecodeError:
        return None


def with_fallback(fn: Callable[[], CompletionResult],
                  fallback: Callable[[], Any], *, stage: str,
                  story_id: Optional[int], session) -> Any:
    """Run a model call, audit it, and use the deterministic result on failure.

    This is the single choke point that keeps the newsroom honest: a broken,
    misbehaving or unconfigured model degrades to the heuristic writer, never
    to silence and never to invented content.
    """
    result = fn()
    record_call(result, stage, story_id, session)
    if not result.success or not result.text.strip():
        return fallback()
    return result
