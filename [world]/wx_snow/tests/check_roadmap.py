"""Decodes the lane map exactly like fx/snow_world.fx (format 4, tools/roadmap_decode.py) and measures it.

    python tests/check_roadmap.py                 # built-in checks
    python tests/check_roadmap.py --old DIR       # + the seam score of an older (format 3) build in DIR
    python tests/check_roadmap.py x y z           # one point

Checks:
1. LS airport 2+2 divided road: lanes on both carriageways, nothing in the median
2. layer 2 (overpasses) present
3. junction SEAM SCORE: the wheel tracks are evaluated on both sides (+-2 cm) of every cell border inside and
   around the junctions (junction + ring cells); |difference| > 0.25 is a visible jump. Split by cause:
   "lanes" = the layer 1 lanes alone jump there (the nearest link changes at that border: the old cell-wise
   lane map, the same with and without junction paths, visible where the junction mask is below 1),
   "paths" = the rest (K truncation, a path leaving the listed cells). The paths must stay under 1 %.
4. PATH COVERAGE: every path, sampled along its two wheel tracks, must be in the list of the cell under
   the sample (the shader can only draw a path that its cell lists).
"""
import math
import os
import sys

import numpy as np

RES = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(RES, "tools"))
from roadmap_decode import JK, RoadMap  # noqa: E402

args = sys.argv[1:]
old_dir = None
if "--old" in args:
    k = args.index("--old")
    old_dir = args[k + 1]
    del args[k:k + 2]

m = RoadMap()
info = m.info


def lanes(x, y, z):
    """-> (layer-ish, lane, lane fraction) or (.., x, "off") like the old tool, from the numpy decoder"""
    r = m.lanes(np.array([float(x)]), np.array([float(y)]), np.array([float(z)]))
    if r["on"][0] <= 0:
        return None if r["edge"][0] == 99 else (1, 0, "off")
    return (1, 0, round(float(r["lf"][0]), 2))


if len(args) == 3:
    x, y, z = map(float, args)
    r = m.lanes(np.array([x]), np.array([y]), np.array([z]))
    print({k: (float(v[0]) if hasattr(v, "__len__") else v) for k, v in r.items()})
    sys.exit(0)

fails = 0
# 1. LS airport road: two one-way links (y -2684.8 and -2669.8), 2 lanes each, 5 m median between
ys = -2692.5 + np.arange(32.0)
r = m.lanes(np.full(32, 1445.0), ys, np.full(32, 13.0))
on = r["on"] > 0.5
gap = ys[on & (ys > -2679.3) & (ys < -2675.3)]
print(f"1. airport 2+2 at x=1445: {int(on.sum())} lane samples, {len(gap)} in the median")
if len(gap):
    fails += 1
    print("FAIL: lanes in the median", gap)
if on.sum() < 18:
    fails += 1
    print("FAIL: too few lane samples", int(on.sum()))

# 2. overpass layer
L2c = int((m.L2[::3, ::3, 3] > 0).sum())
print("2. layer 2 samples:", L2c)
if L2c < 100:
    fails += 1
    print("FAIL: layer 2 almost empty")

# 3. seam score around the junctions
LJ = m.LJ
listc = (LJ[..., 2] > 0) | (LJ[..., 3] > 0)
js, is_ = np.nonzero(listc)
zz = m.LZ[js, is_]
zc = (zz[:, 0] * 256 + zz[:, 1]) / 65535 * (info["zMax"] - info["zMin"]) + info["zMin"]
cell = m.cell
EPS = 0.02
offs = (np.arange(6) + 0.5) / 6 * cell
pts_a, pts_b, pz = [], [], []
for axis in (0, 1):                       # 0: border at x = right edge of the cell, 1: at y = top edge
    bx = info["minX"] + (is_ + (1 if axis == 0 else 0)) * cell
    by = info["minY"] + (js + (1 if axis == 1 else 0)) * cell
    for o in offs:
        if axis == 0:
            x, y = bx, info["minY"] + js * cell + o
            pts_a.append((x - EPS, y))
            pts_b.append((x + EPS, y))
        else:
            x, y = info["minX"] + is_ * cell + o, by
            pts_a.append((x, y - EPS))
            pts_b.append((x, y + EPS))
        pz.append(zc + 0.3)
A = np.concatenate([np.stack(p, -1) for p in pts_a])
B = np.concatenate([np.stack(p, -1) for p in pts_b])
Z = np.concatenate(pz)


def seam(mm):
    out, lane = [], []
    for s0 in range(0, len(A), 200000):
        sl = slice(s0, s0 + 200000)
        ta = mm.road(A[sl, 0], A[sl, 1], Z[sl], 0.05)["tracks"]
        tb = mm.road(B[sl, 0], B[sl, 1], Z[sl], 0.05)["tracks"]
        la = mm.lane_tracks(mm.lanes(A[sl, 0], A[sl, 1], Z[sl]), A[sl, 0], A[sl, 1], 0.05)
        lb = mm.lane_tracks(mm.lanes(B[sl, 0], B[sl, 1], Z[sl]), B[sl, 0], B[sl, 1], 0.05)
        out.append(np.abs(ta - tb))
        lane.append(np.abs(la - lb) > 0.25)
    d = np.concatenate(out)
    lj = np.concatenate(lane)
    jump = d > 0.25
    return float(d.mean()), float(jump.mean()), float((jump & lj).mean()), float((jump & ~lj).mean())


mean_new, jump_new, lane_new, path_new = seam(m)
print(f"3. seam score (format {m.format}): {len(A)} border samples in {len(js)} junction + ring cells, "
      f"mean |dtracks| {mean_new:.4f}, visible jumps {jump_new * 100:.2f} % "
      f"(lanes {lane_new * 100:.2f} %, paths {path_new * 100:.2f} %)")
if old_dir:
    mo = RoadMap(old_dir)
    mean_old, jump_old, lane_old, path_old = seam(mo)
    print(f"   format {mo.format} ({old_dir}): mean |dtracks| {mean_old:.4f}, visible jumps {jump_old * 100:.2f} % "
          f"(cell-wise lanes and turn pieces)")
if path_new > 0.01:
    fails += 1
    print("FAIL: the junction paths leave more than 1 % visible jumps at the cell borders")

# 4. path coverage
npaths = len(m.p0)
tt = np.linspace(0.02, 0.98, 25)
P0, P1, P2 = m.p0[:, None, :], m.p1[:, None, :], m.p2[:, None, :]
T = tt[None, :, None]
pos = (1 - T) ** 2 * P0 + 2 * T * (1 - T) * P1 + T * T * P2
der = 2 * (1 - T) * (P1 - P0) + 2 * T * (P2 - P1)
der = der / np.maximum(np.linalg.norm(der, axis=-1, keepdims=True), 1e-6)
nrm = np.stack([-der[..., 1], der[..., 0]], -1)
idx = np.repeat(np.arange(npaths), len(tt))
cover, total = 0, 0
miss_paths = set()
for side in (-0.9, 0.9):
    p = (pos + nrm * side).reshape(-1, 2)
    i = np.floor((p[:, 0] - info["minX"]) / cell).astype(int).clip(0, m.n - 1)
    j = np.floor((p[:, 1] - info["minY"]) / cell).astype(int).clip(0, m.n - 1)
    jj = LJ[j, i]
    off = jj[:, 0] * 256 + jj[:, 1]
    cnt = jj[:, 2]
    found = np.zeros(len(p), dtype=bool)
    for k in range(JK):
        sel = k < cnt
        found |= sel & (m.path_of_list(off, np.full(len(p), k)) == idx)
    # samples outside every list cell (the first metres of a path lie on its arm, drawn by the lanes)
    inlist = (cnt > 0) | (jj[:, 3] > 0)
    cover += int((found & inlist).sum())
    total += int(inlist.sum())
    miss_paths |= set(idx[inlist & ~found].tolist())
cov = cover / max(total, 1)
print(f"4. path coverage: {npaths} paths, {cov * 100:.2f} % of {total} track samples in list cells are listed, "
      f"{len(miss_paths)} paths miss a sample (K = {JK} truncation)")
if cov < 0.97:
    fails += 1
    print("FAIL: path coverage under 97 %")
sys.exit(1 if fails else 0)
