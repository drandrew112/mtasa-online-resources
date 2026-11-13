"""Top-down render of the road snow at real junctions (numpy port of the shader, tools/roadmap_decode.py).

    python tools/render_junction.py                       # 6 junctions picked from the lane map (LS first)
    python tools/render_junction.py 1530,-1630,13 ...     # x,y,z of the junction centres
    options: --old DIR   also render DIR (a format 3 build: roadmap.png, roadmap2.png, roadmapz.png,
                         roadmap.json) on the left = before / after
             --out DIR   where to write (default: the system temp folder / wx_snow_junctions)
             --size M    side of the square in metres (default 64), --ppm N pixels per metre (default 8)
             --grid      draw the 4 m lane map cells
Writes junction_<x>_<y>.png (and an index of what it wrote on stdout).
"""
import os
import sys
import tempfile

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from roadmap_decode import RoadMap, sat, smoothstep  # noqa: E402

ASPHALT = np.array([78, 74, 70], dtype=float)
SNOW = np.array([236, 240, 244], dtype=float)
SLUSH = np.array([150, 144, 136], dtype=float)


def render(m, cx, cy, cz, size, ppm, grid):
    n = int(size * ppm)
    xs = cx - size / 2 + (np.arange(n) + 0.5) / ppm
    ys = cy + size / 2 - (np.arange(n) + 0.5) / ppm
    X, Y = np.meshgrid(xs, ys)
    r = m.road(X, Y, np.full(X.shape, cz), 1.0 / ppm)
    grain = m.noise.sample(3, X * 0.25 + 0.13, Y * 0.25, 0.25 / ppm)
    road = (r["on"] > 0.01) | (r["jm"] > 0.01) | (r["tracks"] > 0.01) | (r["packed"] > 0.01)
    mk = sat(r["roadSnow"] * (0.65 + 0.7 * grain) * 1.25)
    plain = sat(0.85 * (0.75 + 0.5 * grain))
    mask = np.where(road, mk, plain)
    col = ASPHALT[None, None] + (SNOW - ASPHALT)[None, None] * mask[..., None]
    slush = sat(r["packed"] * 0.5 + r["rim"] * 0.6 + r["tracks"] * 0.3)[..., None] * mask[..., None]
    col = col + (SLUSH[None, None] - col) * slush * 0.6
    img = Image.fromarray(np.clip(col, 0, 255).astype(np.uint8), "RGB")
    if grid:
        d = ImageDraw.Draw(img)
        cell = m.cell
        x0 = np.ceil((cx - size / 2 - m.info["minX"]) / cell) * cell + m.info["minX"]
        while x0 < cx + size / 2:
            px = (x0 - (cx - size / 2)) * ppm
            d.line([(px, 0), (px, n)], fill=(90, 140, 200))
            x0 += cell
        y0 = np.ceil((cy - size / 2 - m.info["minY"]) / cell) * cell + m.info["minY"]
        while y0 < cy + size / 2:
            py = (cy + size / 2 - y0) * ppm
            d.line([(0, py), (n, py)], fill=(90, 140, 200))
            y0 += cell
    return img


def pick_junctions(m, count):
    """centres of the larger junction masks, Los Santos first"""
    A = m.LJ[..., 3] == 255             # junction cells (ring = 128)
    seen = np.zeros_like(A)
    found = []
    js, is_ = np.nonzero(A)
    for j, i in zip(js, is_):
        if seen[j, i]:
            continue
        stack, cells = [(j, i)], []
        seen[j, i] = True
        while stack:
            a, b = stack.pop()
            cells.append((a, b))
            for da in (-1, 0, 1):
                for db in (-1, 0, 1):
                    q = (a + da, b + db)
                    if 0 <= q[0] < m.n and 0 <= q[1] < m.n and A[q] and not seen[q]:
                        seen[q] = True
                        stack.append(q)
        if 6 <= len(cells) <= 40:
            cj = np.mean([c[0] for c in cells])
            ci = np.mean([c[1] for c in cells])
            x = m.info["minX"] + (ci + 0.5) * m.cell
            y = m.info["minY"] + (cj + 0.5) * m.cell
            zz = m.LZ[int(round(cj)), int(round(ci))]
            z = (zz[0] * 256 + zz[1]) / 65535 * (m.info["zMax"] - m.info["zMin"]) + m.info["zMin"]
            ls = 300 < x < 2900 and -2800 < y < -900
            found.append((0 if ls else 1, -len(cells), x, y, z))
    found.sort()
    out, taken = [], []
    for _, _, x, y, z in found:
        if all(abs(x - a) + abs(y - b) > 200 for a, b in taken):
            out.append((x, y, z))
            taken.append((x, y))
        if len(out) >= count:
            break
    return out


def main(argv):
    old, out, size, ppm, grid, pts = None, os.path.join(tempfile.gettempdir(), "wx_snow_junctions"), 64.0, 8, False, []
    k = 0
    while k < len(argv):
        a = argv[k]
        if a == "--old":
            old, k = argv[k + 1], k + 1
        elif a == "--out":
            out, k = argv[k + 1], k + 1
        elif a == "--size":
            size, k = float(argv[k + 1]), k + 1
        elif a == "--ppm":
            ppm, k = int(argv[k + 1]), k + 1
        elif a == "--grid":
            grid = True
        else:
            pts.append(tuple(float(v) for v in a.split(",")))
        k += 1
    os.makedirs(out, exist_ok=True)
    m = RoadMap()
    mo = RoadMap(old) if old else None
    if not pts:
        pts = pick_junctions(m, 6)
    for x, y, z in pts:
        img = render(m, x, y, z, size, ppm, grid)
        if mo is not None:
            before = render(mo, x, y, z, size, ppm, grid)
            both = Image.new("RGB", (img.width * 2 + 12, img.height), (255, 255, 255))
            both.paste(before, (0, 0))
            both.paste(img, (img.width + 12, 0))
            img = both
        path = os.path.join(out, f"junction_{int(x)}_{int(y)}.png")
        img.save(path)
        print(f"{x:.1f},{y:.1f},{z:.1f} -> {path}")


if __name__ == "__main__":
    main(sys.argv[1:])
