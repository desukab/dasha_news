"""Audio Engine: text-to-speech for Telugu, English and Tenglish.

Zero-cost by default. ``espeak-ng`` is free, offline and has a Telugu voice, so
the app ships with genuine audio support and no paid TTS dependency. When the
binary is absent the engine degrades to "no audio" rather than failing -- the
newsroom records the failure and the story stays readable.

The audio contract is deliberately narrow: narrate the Dasha summary, never the
source article.
"""

from __future__ import annotations

import logging
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

from newsroom.config import get_settings

logger = logging.getLogger(__name__)

# espeak-ng voice codes. espeak-ng supports te (Telugu) and en (English).
VOICE_MAP = {
    ("te", "female"): "te+f2",
    ("te", "male"): "te+m1",
    ("en", "female"): "en-us+f2",
    ("en", "male"): "en-us+m1",
    ("ten", "female"): "en-us+f2",
    ("ten", "male"): "en-us+m1",
}
DEFAULT_VOICE = {"te": "te", "en": "en-us", "ten": "en-us"}

MAX_AUDIO_CHARS = 6000


@dataclass
class AudioResult:
    path: Optional[str]
    duration_seconds: float
    byte_size: int
    voice: str
    status: str
    error: Optional[str] = None


def tts_available(engine: Optional[str] = None) -> bool:
    """Is a real TTS binary installed?"""
    engine = engine or get_settings().tts_engine
    if engine == "none":
        return False
    binary = shutil.which("espeak-ng") or shutil.which("espeak")
    if binary:
        return True
    return False


def render_audio(text: str, *, language: str, out_dir: Path,
                 name: str, voice_kind: Optional[str] = None,
                 rate: Optional[int] = None) -> AudioResult:
    """Render `text` to a WAV file in `out_dir`."""
    settings = get_settings()
    voice_kind = voice_kind or (settings.tts_voice_te if language == "te" else settings.tts_voice_en)
    rate = rate or settings.tts_rate

    if not text or not text.strip():
        return AudioResult(None, 0.0, 0, "", "failed", "empty text")
    if not tts_available(settings.tts_engine):
        logger.info("TTS unavailable (%s); skipping audio for %s", settings.tts_engine, name)
        return AudioResult(None, 0.0, 0, "", "failed",
                           f"TTS engine '{settings.tts_engine}' not installed")
    if len(text) > MAX_AUDIO_CHARS:
        text = text[:MAX_AUDIO_CHARS]

    voice = VOICE_MAP.get((language, voice_kind)) or DEFAULT_VOICE.get(language, "en-us")
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / f"{name}.wav"

    binary = shutil.which("espeak-ng") or shutil.which("espeak")
    command = [binary, "-v", voice, "-s", str(rate), "-w", str(out_path), text]
    try:
        completed = subprocess.run(  # noqa: S603 - argv list, no shell
            command, capture_output=True, text=True, timeout=120)
    except subprocess.TimeoutExpired:
        return AudioResult(None, 0.0, 0, voice, "failed", "TTS timed out")
    if completed.returncode != 0 or not out_path.exists():
        return AudioResult(None, 0.0, 0, voice, "failed",
                           (completed.stderr or "unknown error")[:200])

    size = out_path.stat().st_size
    duration = _estimate_duration(size)
    return AudioResult(str(out_path), duration, size, voice, "ready")


def _estimate_duration(byte_size: int) -> float:
    """Rough duration from WAV payload size (16kHz mono 16-bit)."""
    if byte_size <= 0:
        return 0.0
    return max(0.1, (byte_size - 44) / (16000 * 2))
