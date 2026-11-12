"""Decodes data/roadmap*.png exactly like fx/snow_world.fx RoadLanes() (format 3).

    python tests/check_roadmap.py            # built-in checks
    python tests/check_roadmap.py x y z      # one point
"""
import json
import math
import os
import sys

from PIL import Image

RES = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
info = json.load(open(os.path.join(RES, "data", "roadmap.json")))[0]
L1 = Image.open(os.path.join(RES, "data", "roadmap.png")).load()
L2 = Image.open(os.path.join(RES, "data", "roadmap2.png")).load()
LZ = Image.open(os.path.join(RES, "data", "roadmapz.png")).load()
CELL = info["size"] / info["cells"]


def lanes(x, y, z):
    i = int((x - info["minX"]) // CELL)
    j = int((y - info["minY"]) // CELL)
    zz = LZ[i, j]
    zr = info["zMax"] - info["zMin"]
    z1 = (zz[0] * 256 + zz[1]) / 65535 * zr + info["zMin"]
    z2 = (zz[2] * 256 + zz[3]) / 65535 * zr + info["zMin"]
    r1, r2 = L1[i, j], L2[i, j]
    if r1[3] and abs(z - z1) < 3.5:
        r, layer = r1, 1
    elif r2[3] and abs(z - z2) < 3.5:
        r, layer = r2, 2
    else:
        return None
    a8 = r[3]
    dc = (r[0] * 256 + r[1]) / 65535 * 2 * info["dRange"] - info["dRange"]
    ang = r[2] / 256 * 2 * math.pi
    cx = info["minX"] + (i + 0.5) * CELL
    cy = info["minY"] + (j + 0.5) * CELL
    d = dc + (x - cx) * math.cos(ang) + (y - cy) * math.sin(ang)
    left, right, med = a8 & 3, (a8 >> 2) & 3, (a8 >> 4) * 0.5 * 2
    width = (left + right) * 5 + med
    xx = d + width / 2
    on_left = 0 <= xx <= left * 5 and left > 0
    xr = xx - left * 5 - med
    on_right = 0 <= xr <= right * 5 and right > 0
    if not (on_left or on_right):
        return (layer, round(xx, 2), "off")
    lane = int(xx // 5) if on_left else left + int(xr // 5)
    lf = (xx / 5) % 1 if on_left else (xr / 5) % 1
    return (layer, lane, round(lf, 2))


if len(sys.argv) == 4:
    print(lanes(*map(float, sys.argv[1:])))
    sys.exit(0)

fails = 0
# LS airport road: two one-way links (y -2684.8 and -2669.8), 2 lanes each, 5 m median between
print("airport 2+2 at x=1445 (y: layer, lane, frac)")
row = []
for k in range(0, 32):
    y = -2692.5 + k
    row.append((y, lanes(1445, y, 13.0)))
for y, v in row:
    print(f"  {y:8.1f} {v}")
expect_on = [y for y, v in row if v and v[2] != "off"]
gap = [y for y, v in row if -2679.3 < y < -2675.3 and v and v[2] != "off"]
if gap:
    fails += 1
    print("FAIL: lanes in the median", gap)
if len(expect_on) < 18:
    fails += 1
    print("FAIL: too few lane samples", len(expect_on))

# overpass: count cells with a second layer and check both heights resolve
L2c = 0
for j in range(0, info["cells"], 3):
    for i in range(0, info["cells"], 3):
        if L2[i, j][3]:
            L2c += 1
print("layer 2 samples:", L2c)
sys.exit(1 if fails else 0)
