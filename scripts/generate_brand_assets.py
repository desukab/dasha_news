#!/usr/bin/env python3
"""Generate Dasha News brand assets: the launcher icon set and the wordmark.

The brand is the Telugu nameplate

    దశ న్యూస్

so every mark the app ships is derived from that string rather than from a
single decorative glyph. Two faces are used:

    Noto Sans Telugu  — every Telugu string (the paper's own script)
    Source Serif 4    — Latin display type, for the English nameplate

The launcher mark is a typeset monogram of the paper's first word, "దశ", set
on the masthead red with a rule beneath it, the way a nameplate sits on a
front page. It is composed deliberately rather than typed: the glyphs are
optically centred (PIL's bounding box, not its advance width), the rule is
sized to the glyph block, and the side bearing is equal on both sides.

Run from the repository root:

    python3 scripts/generate_brand_assets.py

Inputs  : assets/fonts/*.ttf                (see scripts/fetch_fonts.sh)
Outputs : app/assets/images/*.png           (source of the launcher set)
          app/android/app/src/main/res/**  (generated densities)
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

# -- brand constants ---------------------------------------------------------

MASTHEAD_RED = (179, 38, 30, 255)      # #B3261E
INK_RED_DARK = (127, 18, 18, 255)      # #7F1212, the masthead shade
WHITE = (255, 255, 255, 255)
TRANSPARENT = (0, 0, 0, 0)

TELUGU_WORD = 'దశ న్యూస్'
TELUGU_MARK = 'దశ'
LATIN_NAMEPLATE = 'DASHA NEWS'

ROOT = Path(__file__).resolve().parent.parent
FONTS = ROOT / 'app' / 'assets' / 'fonts'
IMAGES = ROOT / 'app' / 'assets' / 'images'

_TELUGU_REGULAR = FONTS / 'NotoSansTelugu-Regular.ttf'
_TELUGU_BOLD = FONTS / 'NotoSansTelugu-Bold.ttf'
_SERIF_BOLD = FONTS / 'DashaSerif-Bold.ttf'


# -- helpers ------------------------------------------------------------------

def _font(path: Path, size: int) -> ImageFont.FreeTypeFont:
    if not path.exists():
        sys.exit(f'missing font: {path} (run scripts/fetch_fonts.sh first)')
    return ImageFont.truetype(str(path), size)


def _text_size(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.FreeTypeFont):
    """The glyph bbox, which is what an optical centre needs."""
    return draw.textbbox((0, 0), text, font=font)


def _draw_centred(draw, text, font, cx, top, colour):
    """Draws `text` so that its glyph block is centred on `cx`, anchored at `top`."""
    left, top_box, right, bottom = _text_size(draw, text, font)
    width = right - left
    draw.text((cx - width / 2 - left, top), text, font=font, fill=colour)
    return top, top + (bottom - top_box)


# -- the marks ----------------------------------------------------------------

def wordmark(size: int) -> Image.Image:
    """The full lockup: Telugu nameplate over the Latin nameplate.

    Used by the splash screen and the in-app masthead.
    """
    canvas = Image.new('RGBA', (size, size), TRANSPARENT)
    draw = ImageDraw.Draw(canvas)

    telugu = _font(_TELUGU_BOLD, int(size * 0.235))
    latin = _font(_SERIF_BOLD, int(size * 0.062))

    # The Telugu nameplate, optically centred.
    t_top, t_bottom = _draw_centred(draw, TELUGU_WORD, telugu, size / 2,
                                   size * 0.30, WHITE)

    # A masthead rule: as wide as the nameplate block, 1.4% of the canvas thick.
    left, _, right, _ = _text_size(draw, TELUGU_WORD, telugu)
    rule_top = t_bottom + size * 0.045
    draw.rectangle([left, rule_top, right, rule_top + size * 0.014], fill=WHITE)

    # The Latin nameplate beneath the rule, tracked out like a folio line.
    tracked = ' '.join(LATIN_NAMEPLATE.replace(' ', ''))
    _draw_centred(draw, tracked, latin, size / 2, rule_top + size * 0.062, WHITE)

    return canvas


def launcher_icon(size: int) -> Image.Image:
    """The legacy (non-adaptive) launcher icon: the monogram on masthead red."""
    canvas = Image.new('RGBA', (size, size), MASTHEAD_RED)
    draw = ImageDraw.Draw(canvas)

    mark = _font(_TELUGU_BOLD, int(size * 0.40))
    # The monogram sits slightly above the optical centre, the way a cap-height
    # block does above a baseline rule.
    _, top_box, _, bottom_box = _text_size(draw, TELUGU_MARK, mark)
    glyph_h = bottom_box - top_box
    target_top = (size - glyph_h) / 2 - size * 0.055
    m_top, m_bottom = _draw_centred(draw, TELUGU_MARK, mark, size / 2,
                                   target_top, WHITE)

    # The masthead rule, sized and placed from the glyph block itself.
    left, _, right, _ = _text_size(draw, TELUGU_MARK, mark)
    inset = (right - left) * 0.06
    rule_top = m_bottom + size * 0.075
    draw.rectangle([left + inset, rule_top, right - inset,
                    rule_top + size * 0.022], fill=WHITE)

    return canvas


def launcher_foreground(size: int) -> Image.Image:
    """The adaptive-icon foreground: the monogram on transparency.

    Android applies its own inset (see res/mipmap-anydpi-v26/ic_launcher.xml),
    so this is drawn full-bleed and left transparent around the mark.
    """
    canvas = Image.new('RGBA', (size, size), TRANSPARENT)
    draw = ImageDraw.Draw(canvas)

    mark = _font(_TELUGU_BOLD, int(size * 0.34))
    _, top_box, _, bottom_box = _text_size(draw, TELUGU_MARK, mark)
    glyph_h = bottom_box - top_box
    target_top = (size - glyph_h) / 2 - size * 0.045
    m_top, m_bottom = _draw_centred(draw, TELUGU_MARK, mark, size / 2,
                                   target_top, WHITE)

    left, _, right, _ = _text_size(draw, TELUGU_MARK, mark)
    inset = (right - left) * 0.06
    rule_top = m_bottom + size * 0.065
    draw.rectangle([left + inset, rule_top, right - inset,
                    rule_top + size * 0.019], fill=WHITE)

    return canvas


# -- output -------------------------------------------------------------------

DENSITIES = {  # Android launcher densities, in px for a 48dp icon
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
}
FOREGROUND_DENSITIES = {
    'mdpi': 108,
    'hdpi': 162,
    'xhdpi': 216,
    'xxhdpi': 324,
    'xxxhdpi': 432,
}


def _check_balance(image: Image.Image, label: str) -> None:
    """Cheap visual QA: assert the ink is centred and covers a sane area.

    A mark that is off-centre or that covers half the canvas is what a
    "typed" logo looks like; these checks catch it without a human looking.
    For a mark on a coloured ground the ink is the white glyph block; on a
    transparent ground it is the alpha channel.
    """
    rgb = image.convert('RGB')
    white = rgb.point(lambda p: 255 if p > 200 else 0)
    mask = white.getchannel('R') if white.getextrema() != (0, 0) \
        else image.getchannel('A')
    bbox = mask.getbbox()
    if bbox is None:
        sys.exit(f'{label}: the mark drew nothing')
    w, h = image.size
    left, top, right, bottom = bbox
    if left > w * 0.30 or w - right > w * 0.30:
        sys.exit(f'{label}: ink is not horizontally centred '
                 f'(margins {left}px / {w - right}px of {w}px)')
    cover = sum(mask.point(lambda a: 1 if a else 0).getdata()) / (w * h)
    if not 0.03 <= cover <= 0.60:
        sys.exit(f'{label}: ink covers {cover:.0%} of the canvas, outside '
                 'the 3-60% range a legible mark occupies')
    print(f'  {label}: {w}x{h}, ink centred '
          f'(l={left} r={w - right}), coverage {cover:.0%}')


def main() -> None:
    print('drawing the brand marks')
    IMAGES.mkdir(parents=True, exist_ok=True)

    for name, painter in (('icon', launcher_icon),
                          ('icon_foreground', launcher_foreground)):
        image = painter(1024)
        _check_balance(image, name)
        image.save(IMAGES / f'{name}.png')
        print(f'  wrote app/assets/images/{name}.png')

    wordmark(1024).save(IMAGES / 'wordmark.png')
    print('  wrote app/assets/images/wordmark.png')

    res = ROOT / 'app' / 'android' / 'app' / 'src' / 'main' / 'res'
    for density, px in DENSITIES.items():
        launcher_icon(px).save(res / f'mipmap-{density}' / 'ic_launcher.png')
    for density, px in FOREGROUND_DENSITIES.items():
        launcher_foreground(px).save(
            res / f'drawable-{density}' / 'ic_launcher_foreground.png')
    print('  wrote launcher bitmaps for all densities')


if __name__ == '__main__':
    main()
