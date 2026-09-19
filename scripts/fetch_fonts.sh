#!/usr/bin/env bash
# Downloads the two faces the Dasha brand is set in and instantiates the
# static weights Flutter needs.
#
# Both are variable fonts upstream; Flutter resolves weights from the pubspec
# mapping, so each weight is cut as its own static file here.
#
#   Noto Sans Telugu  OFL — every Telugu string in the app
#   Source Serif 4    OFL — the Latin nameplate and Latin headlines
set -euo pipefail

cd "$(dirname "$0")/.."

PY=${PY:-python3}
command -v "$PY" >/dev/null 2>&1 || PY=/home/azureuser/dasha_news/.venv/bin/python
"$PY" -c 'import fontTools' 2>/dev/null || "$PY" -m pip install --quiet fonttools

OUT=app/assets/fonts
mkdir -p "$OUT" /tmp/dasha_fonts

fetch() {  # fetch <repo-path> <local-name>
  local dest="/tmp/dasha_fonts/$2"
  [ -s "$dest" ] || curl -sL --fail --max-time 120 \
    -o "$dest" "https://raw.githubusercontent.com/google/fonts/main/$1"
  echo "fetched $2"
}

fetch "ofl/notosanstelugu/NotoSansTelugu%5Bwdth%2Cwght%5D.ttf" NotoTelugu-VF.ttf
fetch "ofl/sourceserif4/SourceSerif4%5Bopsz%2Cwght%5D.ttf" SourceSerif4-VF.ttf

"$PY" - <<'EOF'
from fontTools import ttLib
from fontTools.varLib.instancer import instantiateVariableFont

def cut(src, dst, axes):
    font = ttLib.TTFont(src)
    instantiateVariableFont(font, axes, inplace=True)
    # The instances upstream reports as "Regular"; give them the subfamily
    # name their weight actually is, so nothing downstream has to guess.
    if axes.get('wght', 400) >= 700:
        font['name'].setName('Bold', 2, 3, 1, 0x409)
        font['name'].setName('Bold', 17, 3, 1, 0x409)
    font.save(dst)
    print('cut', dst)

cut('/tmp/dasha_fonts/NotoTelugu-VF.ttf', 'app/assets/fonts/NotoSansTelugu-Regular.ttf', {'wght': 400, 'wdth': 100})
cut('/tmp/dasha_fonts/NotoTelugu-VF.ttf', 'app/assets/fonts/NotoSansTelugu-Bold.ttf', {'wght': 700, 'wdth': 100})
cut('/tmp/dasha_fonts/SourceSerif4-VF.ttf', 'app/assets/fonts/DashaSerif-Regular.ttf', {'wght': 400, 'opsz': 16})
cut('/tmp/dasha_fonts/SourceSerif4-VF.ttf', 'app/assets/fonts/DashaSerif-SemiBold.ttf', {'wght': 600, 'opsz': 16})
cut('/tmp/dasha_fonts/SourceSerif4-VF.ttf', 'app/assets/fonts/DashaSerif-Bold.ttf', {'wght': 700, 'opsz': 16})
EOF

# The OFL asks for the licence to travel with the font.
for family in notosanstelugu sourceserif4; do
  curl -sL --fail --max-time 30 -o "$OUT/$family-OFL.txt" \
    "https://raw.githubusercontent.com/google/fonts/main/ofl/$family/OFL.txt"
done
echo "fonts are in $OUT"
