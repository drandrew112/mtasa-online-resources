"""ui_browser :: tools/car_images.py

Copies /takeapic car screenshots into a dealer site as product images:
960x540, 256-colour PNG (~260 KB instead of ~2.2 MB), named <model>.png.

    python -I tools/car_images.py <site> <model> [<model> ...]
    python -I tools/car_images.py lvcars 405 410

Run from the ui_browser folder. Source: [devtools]/takeapic/screenshots/car/<model>.png
(full resolution, kept there). New models also need a <file> line in meta.xml.
"""
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHOTS = os.path.join(HERE, "..", "..", "[devtools]", "takeapic", "screenshots", "car")
SIZE = (960, 540)


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    site, models = sys.argv[1], sys.argv[2:]
    dest = os.path.join(HERE, "sites", site)
    if not os.path.isdir(dest):
        print("no such site folder:", dest)
        return 1

    meta = open(os.path.join(HERE, "meta.xml"), encoding="utf-8").read()
    failed = 0
    for model in models:
        src = os.path.join(SHOTS, model + ".png")
        if not os.path.isfile(src):
            print(model, "- no screenshot, run /takeapic car", model)
            failed += 1
            continue
        im = Image.open(src).convert("RGB").resize(SIZE, Image.LANCZOS)
        im = im.quantize(256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.FLOYDSTEINBERG)
        out = os.path.join(dest, model + ".png")
        im.save(out, optimize=True)
        listed = 'src="sites/%s/%s.png"' % (site, model) in meta
        print("%s -> sites/%s/%s.png (%d KB)%s" % (model, site, model, os.path.getsize(out) // 1024,
                                                  "" if listed else "  NOT IN meta.xml"))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
