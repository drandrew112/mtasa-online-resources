"""Compress takeapic freecam screenshots into biz_core/img/buildings/<name>.jpg.

    python tools/compress_photos.py [source_dir] [names...]

The PNG must be named after the building key (biz_core/shared/properties.lua
BIZ.BUILDINGS), e.g. ls_commerce.png. Output: 1280x720 progressive JPEG, ~150-200 KB.
Without names every PNG of the source folder is converted.
"""
import os, sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_SRC = os.path.join(HERE, "..", "..", "[devtools]", "takeapic", "screenshots", "freecam")
DST = os.path.join(HERE, "..", "biz_core", "img", "buildings")
WIDTH, QUALITY = 1280, 80

src = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_SRC
names = set(sys.argv[2:])
os.makedirs(DST, exist_ok=True)
for f in sorted(os.listdir(src)):
    if not f.lower().endswith(".png") or (names and f[:-4] not in names):
        continue
    im = Image.open(os.path.join(src, f)).convert("RGB")
    w, h = im.size
    im = im.resize((WIDTH, round(h * WIDTH / w)), Image.LANCZOS)
    out = os.path.join(DST, f[:-4] + ".jpg")
    im.save(out, "JPEG", quality=QUALITY, optimize=True, progressive=True)
    print(f, (w, h), "->", im.size, os.path.getsize(out) // 1024, "KB")
