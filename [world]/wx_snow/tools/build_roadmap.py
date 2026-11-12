"""wx_snow lane map from GTA SA data/Paths/NODES*.DAT (format 3).

    python tools/build_roadmap.py ["C:/Games/GTA San Andreas/data/Paths"]

Every vehicle link (boats left out) is a straight piece of road; its navi node gives the centre
line, the direction and the lanes (left / right count, 5 m each, median = navi width / 8 m).
Lane layout (measured on the LS airport road, a 2+2 divided road = two one-way links 15 m apart):
the whole link - left lanes, median, right lanes - is CENTRED on the navi line.

Every 4 m cell (same grid as the roof map) stores the LINE of a link, not a value to interpolate,
in two height layers (an overpass and the road under it share the cell):
  data/roadmap.png   layer 1 = the nearest link
  data/roadmap2.png  layer 2 = the nearest link at least LAYER_DZ higher / lower than layer 1
    R, G = signed distance of the cell centre from the link centre line, 16 bit, -32..32 m
    B    = direction of the right-hand normal, 0..255 = 0..2pi
    A    = left lanes (bits 0-1) + right lanes * 4 (bits 2-3) + median half width / 0.5 m * 16
  data/roadmapz.png  RG = layer 1 road height, BA = layer 2 road height (16 bit, Z_MIN..Z_MAX)
The shader samples them with POINT filtering, takes the layer whose height matches the pixel
and computes the exact lateral distance: d = dc + dot(pixel - cellCentre, normal).
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gta_paths import read_all, road_segments  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MIN_X, MIN_Y, SIZE, CELL = -3072, -3072, 6144, 4
N = SIZE // CELL
LANE = 5.0
D_RANGE = 32.0          # dc in -32..32 m
MARGIN = 3.0            # m beyond the outer lane a link still claims cells
Z_MIN, Z_MAX = -60.0, 1000.0
LAYER_DZ = 4.0          # m between the roads of the two layers


def link_params(s):
    """-> None or the geometry of one link"""
    nv = s["navi"]
    ax, ay, az = s["a"]
    bx, by, bz = s["b"]
    dx, dy = bx - ax, by - ay
    length = math.hypot(dx, dy)
    if length < 0.5:
        return None
    tx, ty = dx / length, dy / length
    ndx, ndy = nv["dx"], nv["dy"]
    nlen = math.hypot(ndx, ndy)
    if nlen < 0.1:
        ndx, ndy, nlen = tx, ty, 1.0
    ndx, ndy = ndx / nlen, ndy / nlen
    med_half = min(7.5, nv["width"] / 8.0 / 2.0)
    left, right = min(3, nv["left"]), min(3, nv["right"])
    if left + right == 0:
        left = right = 1
    half_w = (left + right) * LANE / 2 + med_half
    return {"ax": ax, "ay": ay, "az": az, "bx": bx, "by": by, "bz": bz, "tx": tx, "ty": ty, "len": length,
            "rx": ndy, "ry": -ndx, "cx": nv["x"], "cy": nv["y"], "half": half_w + MARGIN,
            "code": left + right * 4 + int(round(med_half / 0.5)) * 16}


def cells_of(L):
    i0 = max(0, int((min(L["ax"], L["bx"]) - L["half"] - MIN_X) // CELL))
    i1 = min(N - 1, int((max(L["ax"], L["bx"]) + L["half"] - MIN_X) // CELL))
    j0 = max(0, int((min(L["ay"], L["by"]) - L["half"] - MIN_Y) // CELL))
    j1 = min(N - 1, int((max(L["ay"], L["by"]) + L["half"] - MIN_Y) // CELL))
    if i0 > i1 or j0 > j1:
        return None
    xs = MIN_X + (np.arange(i0, i1 + 1) + 0.5) * CELL
    ys = MIN_Y + (np.arange(j0, j1 + 1) + 0.5) * CELL
    X, Y = np.meshgrid(xs, ys)
    t = np.clip((X - L["ax"]) * L["tx"] + (Y - L["ay"]) * L["ty"], 0, L["len"])
    px, py = L["ax"] + L["tx"] * t, L["ay"] + L["ty"] * t
    dist = np.hypot(X - px, Y - py)
    d = (X - L["cx"]) * L["rx"] + (Y - L["cy"]) * L["ry"]
    z = L["az"] + (L["bz"] - L["az"]) * (t / L["len"])
    cand = (dist <= L["half"]) & (np.abs(d) < D_RANGE)
    return (slice(j0, j1 + 1), slice(i0, i1 + 1)), dist, d, z, cand


class Layer:
    def __init__(self):
        self.best = np.full((N, N), np.inf, dtype=np.float32)
        self.dc = np.zeros((N, N), dtype=np.float32)
        self.ang = np.zeros((N, N), dtype=np.float32)
        self.code = np.zeros((N, N), dtype=np.uint8)
        self.z = np.zeros((N, N), dtype=np.float32)

    def put(self, sl, take, L, dist, d, z):
        self.best[sl][take] = dist[take]
        self.dc[sl][take] = d[take]
        self.ang[sl][take] = math.atan2(L["ry"], L["rx"]) % (2 * math.pi)
        self.code[sl][take] = L["code"]
        self.z[sl][take] = z[take]

    def image(self):
        img = np.zeros((N, N, 4), dtype=np.uint8)
        d16 = np.clip(np.round((self.dc + D_RANGE) / (2 * D_RANGE) * 65535), 0, 65535).astype(np.uint32)
        img[..., 0] = (d16 >> 8).astype(np.uint8)
        img[..., 1] = (d16 & 255).astype(np.uint8)
        img[..., 2] = np.clip(np.round(self.ang / (2 * math.pi) * 256), 0, 255).astype(np.uint8)
        img[..., 3] = self.code
        img[~np.isfinite(self.best)] = 0
        return img


def z16(z):
    return np.clip(np.round((z - Z_MIN) / (Z_MAX - Z_MIN) * 65535), 0, 65535).astype(np.uint32)


def build(paths_dir):
    areas = read_all(paths_dir)
    links = [L for L in (link_params(s) for s in road_segments(areas) if not s["boat"] and s["navi"]) if L]
    one, two = Layer(), Layer()
    geo = [(L, cells_of(L)) for L in links]
    for L, r in geo:                      # layer 1: nearest link
        if not r:
            continue
        sl, dist, d, z, cand = r
        take = cand & (dist < one.best[sl])
        if take.any():
            one.put(sl, take, L, dist, d, z)
    has1 = np.isfinite(one.best)
    for L, r in geo:                      # layer 2: nearest link at another height
        if not r:
            continue
        sl, dist, d, z, cand = r
        take = cand & has1[sl] & (np.abs(z - one.z[sl]) > LAYER_DZ) & (dist < two.best[sl])
        if take.any():
            two.put(sl, take, L, dist, d, z)
    has2 = np.isfinite(two.best)
    zimg = np.zeros((N, N, 4), dtype=np.uint8)
    za, zb = z16(one.z), z16(two.z)
    zimg[..., 0], zimg[..., 1] = (za >> 8).astype(np.uint8), (za & 255).astype(np.uint8)
    zimg[..., 2], zimg[..., 3] = (zb >> 8).astype(np.uint8), (zb & 255).astype(np.uint8)
    zimg[~has1, 0:2] = 0
    zimg[~has2, 2:4] = 0
    return one.image(), two.image(), zimg, len(links), int(has1.sum()), int(has2.sum())


if __name__ == "__main__":
    paths = sys.argv[1] if len(sys.argv) > 1 else r"C:\Games\GTA San Andreas\data\Paths"
    a, b, zimg, nlinks, n1, n2 = build(paths)
    for name, img in (("roadmap.png", a), ("roadmap2.png", b), ("roadmapz.png", zimg)):
        Image.fromarray(img, "RGBA").save(os.path.join(ROOT, "data", name), optimize=True)
    with open(os.path.join(ROOT, "data", "roadmap.json"), "w", encoding="utf-8") as f:
        json.dump([{"minX": MIN_X, "minY": MIN_Y, "size": SIZE, "cells": N, "lane": LANE, "dRange": D_RANGE,
                    "zMin": Z_MIN, "zMax": Z_MAX, "format": 3, "links": nlinks}], f, indent=4)
    print(f"roadmap {N}x{N}, {nlinks} links, layer 1: {n1} cells, layer 2: {n2} cells")
