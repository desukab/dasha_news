"""Media: legally-usable imagery and the Shorts pipeline.

Every image carries its source, creator, licence and attribution in the
database, alongside the story it illustrates. No image is ever used without
that record being written first.

Shorts: 9:16 vertical news shorts. story -> script -> narration -> captions ->
imagery -> attribution -> FFmpeg render. FFmpeg is optional: when it is absent,
the pipeline produces the script, captions and poster so a render can happen
later, and the short is marked ``pending`` rather than ``ready``.
"""

from __future__ import annotations

import logging
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional

from newsroom.config import get_settings
from newsroom.media.audio import render_audio, tts_available
from newsroom.nlp.telugu import (
    split_sentences,
    strip_dangling_vowel_signs,
    transliterate_to_tenglish,
    word_count,
)

logger = logging.getLogger(__name__)

SHORT_WIDTH, SHORT_HEIGHT = 720, 1280
SHORT_MAX_SECONDS = 60
SHORT_MAX_WORDS = 70
CAPTION_MAX_CHARS = 42

LICENCE_NOTES = {
    "wikimedia": "Wikimedia Commons; see file page for the full licence terms",
    "generated": "Generated in-process by Dasha News; no third-party rights",
    "unsplash": "Unsplash Licence (free to use, attribution appreciated)",
    "pexels": "Pexels Licence (free to use, attribution appreciated)",
    "source": "Publisher-supplied; used as a thumbnail linking to the source",
}


@dataclass
class ImageCandidate:
    url: str
    provider: str
    licence: Optional[str]
    attribution: Optional[str]
    credit_text: Optional[str]
    width: Optional[int] = None
    height: Optional[int] = None


def ffmpeg_available() -> bool:
    return bool(shutil.which("ffmpeg"))


# ---------------------------------------------------------------------------
# Shorts
# ---------------------------------------------------------------------------

@dataclass
class ShortScript:
    lines: List[str]
    caption_lines: List[str]
    duration_estimate: float
    language: str


def build_short_script(body: Optional[str], headline: Optional[str], *,
                       language: str = "te") -> ShortScript:
    """Turn a story into a 9:16 script: punchy lines plus on-screen captions.

    The script is a *reduction* of the Dasha article, never of the source.
    """
    source = headline or ""
    if body:
        source = (source + "\n" + body).strip()
    if language == "ten":
        source = transliterate_to_tenglish(source)

    sentences = [s for s in split_sentences(source) if 6 <= word_count(s) <= 30]
    if not sentences:
        return ShortScript([], [], 0.0, language)

    lines: List[str] = []
    total_words = 0
    for sentence in sentences:
        if total_words >= SHORT_MAX_WORDS:
            break
        lines.append(sentence)
        total_words += word_count(sentence)
    if language == "te":
        lines = [strip_dangling_vowel_signs(line) for line in lines]

    captions = [_caption(line) for line in lines]
    # Narration at ~2.4 words/second, plus a beat per card.
    duration = min(SHORT_MAX_SECONDS, total_words / 2.4 + 1.2 * len(lines))
    return ShortScript(lines, captions, round(duration, 2), language)


def _caption(text: str) -> str:
    """One on-screen caption: short, single line."""
    words = text.split()
    if len(words) <= 6:
        return text
    while len(text) > CAPTION_MAX_CHARS and len(words) > 4:
        words = words[:-1]
        text = " ".join(words)
    return text


def render_short(story_id: int, *, script: ShortScript, media_dir: Path,
                 name: str, language: str, poster_path: Optional[Path] = None,
                 background_color: str = "0B1020") -> Optional[Path]:
    """Render a 9:16 short with burned-in captions.

    Falls back to audio-only (and a pending status) when FFmpeg lacks the
    drawtext filter or the render fails -- the script and captions survive.
    """
    if not script.lines:
        return None
    if not tts_available():
        logger.info("no TTS available; short %s kept pending", name)
        return None
    if not ffmpeg_available():
        logger.info("no ffmpeg available; short %s kept pending", name)
        return None

    audio_dir = media_dir / "audio"
    shorts_dir = media_dir / "shorts"
    audio_dir.mkdir(parents=True, exist_ok=True)
    shorts_dir.mkdir(parents=True, exist_ok=True)

    narration = " ".join(script.lines)
    audio = render_audio(narration, language=language, out_dir=audio_dir,
                         name=f"{name}-narration")
    if audio.status != "ready" or not audio.path:
        return None

    output = shorts_dir / f"{name}.mp4"
    duration = max(3.0, min(SHORT_MAX_SECONDS, audio.duration_seconds + 1.5))
    font = _find_font()

    filter_parts: List[str] = []
    if poster_path and Path(poster_path).exists():
        filter_parts.append(f"[0:v]scale={SHORT_WIDTH}:{SHORT_HEIGHT}:force_original_aspect_ratio="
                            f"increase,crop={SHORT_WIDTH}:{SHORT_HEIGHT}[bg]")
    else:
        filter_parts.append(
            f"color=c={background_color}:s={SHORT_WIDTH}:{SHORT_HEIGHT}:d={duration:.2f}[bg]")

    caption_chain = "[bg]"
    for index, caption in enumerate(script.caption_lines[:8]):
        escaped = _escape(caption)
        y = 0.62 + 0.075 * index
        filter_parts.append(
            f"{caption_chain}drawtext=fontfile='{font}':text='{escaped}':"
            f"fontcolor=white:fontsize=42:x=(w-text_w)/2:y={y}:"
            f"borderw=3:bordercolor=black@0.8:enable='between(t,{index*2.0},{duration})'"
            f"[v{index}]")
        caption_chain = f"[v{index}]"

    filter_complex = ";".join(filter_parts)
    command = [
        "ffmpeg", "-y",
        *(["-loop", "1", "-t", f"{duration:.2f}", "-i", str(poster_path)]
          if poster_path and Path(poster_path).exists() else []),
        "-i", audio.path,
        "-filter_complex", filter_complex,
        "-map", caption_chain.strip("[]"),
        "-map", f"{len(filter_parts) - 1}:a",
        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-preset", "veryfast",
        "-c:a", "aac", "-b:a", "128k",
        "-t", f"{duration:.2f}",
        "-movflags", "+faststart",
        str(output),
    ]
    try:
        completed = subprocess.run(  # noqa: S603 - argv list, no shell
            command, capture_output=True, text=True, timeout=300)
    except subprocess.TimeoutExpired:
        logger.warning("short render timed out for %s", name)
        return None
    if completed.returncode != 0 or not output.exists():
        logger.warning("short render failed for %s: %s", name, (completed.stderr or "")[-400:])
        return None
    return output


def _find_font() -> str:
    """A font with Telugu coverage, else any usable TTF."""
    candidates = [
        "/usr/share/fonts/truetype/noto/NotoSansTelugu-Regular.ttf",
        "/usr/share/fonts/truetype/noto/NotoSansTelugu-Bold.ttf",
        "/usr/share/fonts/opentype/noto/NotoSansTelugu-Regular.otf",
        "/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    ]
    for candidate in candidates:
        if Path(candidate).exists():
            return candidate
    for found in Path("/usr/share/fonts").rglob("*.ttf"):
        return str(found)
    return "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"


def _escape(text: str) -> str:
    return (text or "").replace("\\", "\\\\").replace("'", "\\'") \
        .replace(":", "\\:").replace("%", "\\%")


def generate_poster(headline: Optional[str], *, out_path: Path, width: int = 720,
                    height: int = 1280, background: str = (11, 16, 32),
                    accent: str = (232, 182, 60)) -> Optional[Path]:
    """Generate a simple, licence-clean poster with Pillow."""
    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError:  # pragma: no cover
        logger.info("Pillow unavailable; poster generation skipped")
        return None

    out_path.parent.mkdir(parents=True, exist_ok=True)
    image = Image.new("RGB", (width, height), background)
    draw = ImageDraw.Draw(image)
    draw.rectangle([0, 0, width, 14], fill=accent)

    font_path = _find_font()
    font_big = ImageFont.truetype(font_path, 52)
    font_small = ImageFont.truetype(font_path, 30)
    draw.text((48, 120), "దశా న్యూస్", font=font_small, fill=accent)
    draw.text((48, 180), "DASHA NEWS", font=font_small, fill=(200, 205, 220))

    words = (headline or "").split()
    lines: List[str] = []
    current = ""
    for word in words:
        trial = f"{current} {word}".strip()
        if draw.textlength(trial, font=font_big) > width - 96 and current:
            lines.append(current)
            current = word
        else:
            current = trial
    if current:
        lines.append(current)
    lines = lines[:9]

    y = 420
    for line in lines:
        draw.text((48, y), line, font=font_big, fill=(245, 247, 252))
        y += 74
    draw.text((48, height - 90), "మూలం: దశా న్యూస్ న్యూస్‌రూమ్",
              font=font_small, fill=(160, 168, 190))
    image.save(out_path, "PNG")
    return out_path
