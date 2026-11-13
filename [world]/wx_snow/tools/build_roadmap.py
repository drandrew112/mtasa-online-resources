"""wx_snow lane map from GTA SA data/Paths/NODES*.DAT (format 4).

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
  data/roadmapj.png  junction layer (format 4, see Junctions), belongs to layer 1
The shader samples them with POINT filtering, takes the layer whose height matches the pixel
and computes the exact lateral distance: d = dc + dot(pixel - cellCentre, normal).

Curves (2026-11-13): a curve is a chain of short straight links. The old lateral distance was the
distance to the infinite LINE of the nearest link, so beside a joint on the outer side of a bend it
jumped (a step in the wheel tracks, lanes shifting). Now d is the signed EUCLIDEAN distance to the
nearest point of the link segment: past the end of a link that is the distance to its end node (a
round join, concentric lanes around the bend), and B stores the direction of the gradient of that
distance (radial around the node) instead of the link normal. Inside the segment nothing changes.
`python tests/check_roadmap.py` measures the result.

Chunks (2026-11-13): the client does not load the full images (28 MB of textures in a 32 bit process
that already ran out of memory). The lane map is only read within ~110 m of the camera, so the client
keeps a small window (128 x 128 cells = 512 m) around the camera and fills it from
data/road/c_<cx>_<cy>.png, 256 x 256 cells (1024 m) each, the four layers stacked (rows 0-255 =
layer 1, 256-511 = layer 2, 512-767 = heights, 768-1023 = junction layer). Empty chunks are not
written. The block between the ROAD CHUNKS markers in meta.xml is rewritten by this tool. The full
roadmap*.png stay in data/ for the tests only.

Junctions (format 4, 2026-11-13): where the lanes of two links that cross at a clearly different
direction (> 35 degrees, same height) overlap, the cell is a JUNCTION cell. Layer 1 keeps the nearest
link there (the shader fades its lanes out with the junction mask). One junction = one connected blob
of junction cells (8-connected, dilated by one cell so that the two squares of a divided road join);
its ARMS are the vehicle links that end in the blob and start outside of it (collinear duplicates
dropped; more than MAX_ARMS arms = an interchange / lot: no paths, trodden snow). The blob is often only
part of the crossing (at a T junction only where the stem overlaps the through road), so the junction
MASK also takes the geometric CORE: cells inside the road bands of two arms of clearly different
direction. For every pair of arms, from an inbound lane of one arm to an outbound lane of the other
(right hand traffic; one-way arms keep their flow), there is a traffic PATH: one quadratic Bezier
p0 -> p1 -> p2 (straight through, right turn from the kerb side lanes, left turn / straight from the
median side, no U turns). p0 / p2 sit on the lane lines of the arms, 1 + EXTEND m before the point
where the lane line enters the band of a crossing arm (scanning from 30 m out to 15 m past the arm's
own node; fallbacks: a nearly parallel arm (fork), the first blob cell, the node), so a path overlaps
the lanes of its arms; p1 is where the two lane lines meet. The shader fades a path in / out over its
first / last 4 m and from the outer border of the ring (cross-fade with the lanes, no seam).
Measured 2026-11-13: 1382 blobs, 10164 paths, lists p50 3 / p95 7 / max 35, 626 cells over K = 8,
jpaths 160 KB + jlists 192 KB of textures; tests/check_roadmap.py: seam jumps caused by the paths 0.37 %,
path coverage 98.4 % (the rest: K truncation).

  data/road/jpaths.png  4 texels per path (index k at texel 4k.., JTEX_W wide):
    T0 RG = origin cell i (bits 0-10) + type (bits 11-12: 0 straight, 1 right, 2 left)
            + bit 13 / 14: the noise frame of the entry / exit arm is flipped (see below)
       BA = origin cell j
    T1, T2, T3 = p0, p1, p2: x (RG), y (BA) relative to the corner of the origin cell, 16 bit, -64..64 m
  data/road/jlists.png  the path lists of the cells, 2 path indices per texel (RG, BA, 16 bit)
  junction layer (roadmapj.png / rows 768-1023 of a chunk), per cell:
    R, G = texel offset of the cell's list in jlists, B = list length (<= K), A = region: 255 junction cell,
           128 ring cell, 0 elsewhere. The shader reads A BILINEAR: from the ring centre to the junction
           border the lanes of the links fade out (junction mask), from the outer border of the ring to the
           ring centre the paths fade in, so no track ends at a cell border.
Every junction cell and every cell of the one cell ring around a junction gets the list of the paths
that pass within LIST_R m of the cell (by traffic weight, then distance; more than K: the lightest
ones are dropped). Cells with a list but no layer 1 link get the junction height in roadmapz RG.
Noise frame: the shader wobbles a wheel track with noise sampled along the lane direction of the link
(the navi direction). A path samples it in the frame of its entry arm, blended into the frame of its
exit arm, so a track runs on with the very same wobble from an arm into the junction and out of it.
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
CURVE_MIN_OFFSET = 0.15  # m: the navi point is this far (or more) beside the link chord -> bend the link there
CURVE_MAX_OFFSET = 8.0   # m: farther is a data oddity, keep the chord
JUNCTION_ANGLE = math.radians(35)   # links crossing at more than this overlap = intersection
TURN_SCAN = 30.0                    # m: how far along an arm lane the junction cells are looked for
TURN_BACK = 15.0                    # m: and how far past the arm's own node (its node can be beside the junction)
EXTEND = 4.0                        # m: a path starts / ends this far outside of the entry point (overlap with the arm)
LIST_R = 1.6                        # m: a cell lists the paths this close to its square (tracks reach 0.9 + 0.5 m)
K = 8                               # paths per cell at most (the shader loop)
MAX_ARMS = 12                       # more arms: an interchange / lot, not one junction: no paths (trodden snow)
TYPE_STRAIGHT, TYPE_RIGHT, TYPE_LEFT = 0, 1, 2
WEIGHT = {TYPE_STRAIGHT: 1.0, TYPE_RIGHT: 0.7, TYPE_LEFT: 0.5}   # traffic weight (fx/snow_world.fx JunctionTracks)
RING_A = 128                        # junction layer A of the ring cells (junction cells 255)
REL = 64.0                          # m: path points relative to the origin cell, -REL..REL
JTEX_W = 1024                       # width of jpaths.png / jlists.png
DEBUG = {}                          # last junction_paths internals (tools/render_junction.py)
CUSTOM = os.path.join(ROOT, "data", "road_custom.json")   # custom road models (see apply_custom)


def apply_custom(segs, path=CUSTOM):
    """Custom road models (v_modloader) whose road does not follow the GTA path nodes any more.
    data/road_custom.json, per area: the GTA vehicle links with BOTH ends inside the remove box are dropped,
    and every road polyline becomes a chain of links (point i -> i + 1, navi point in the middle on the line,
    so link_params keeps it straight) with the lanes given at point i. A road's "caps": [start, end] (default
    true, true): false = no link of the chain claims cells behind the line across that end (no round join:
    past the end of a one lane link the wheel tracks would be small rings around the end point, and the
    round joins of the inner joints would reach back past it too). Used where a chain ends ON the lanes of
    another link that runs on (a lane merging into another, a lane chain overlapping a road) instead of in
    a shared node. -> (segs, dropped, added)"""
    if not os.path.exists(path):
        return segs, 0, 0
    with open(path, encoding="utf-8") as f:
        areas = json.load(f).get("areas", [])
    dropped = added = 0
    for area in areas:
        box = area["remove"]

        def inside(p):
            return box["minX"] <= p[0] <= box["maxX"] and box["minY"] <= p[1] <= box["maxY"]

        keep = [s for s in segs if not (inside(s["a"]) and inside(s["b"]))]
        dropped += len(segs) - len(keep)
        segs = keep
        for road in area["roads"]:
            pts = road["points"]
            caps = road.get("caps", [True, True])
            clip = []    # half planes (x, y, nx, ny): a cell is claimed only where (X - x) * nx + (Y - y) * ny >= 0
            for cap, p, q in ((caps[0], pts[0], pts[1]), (caps[1], pts[-1], pts[-2])):
                if not cap:
                    u = _unit(q[0] - p[0], q[1] - p[1])
                    clip.append((p[0], p[1], u[0], u[1]))
            for p, q in zip(pts[:-1], pts[1:]):
                dx, dy = q[0] - p[0], q[1] - p[1]
                length = math.hypot(dx, dy)
                if length < 0.5:
                    continue
                segs.append({"a": (p[0], p[1], p[2]), "b": (q[0], q[1], q[2]), "boat": False, "custom": True,
                             "clip": clip,
                             "navi": {"x": (p[0] + q[0]) / 2, "y": (p[1] + q[1]) / 2, "dx": dx / length,
                                      "dy": dy / length, "width": int(round(p[5] * 16)), "left": int(p[3]),
                                      "right": int(p[4]), "area": -1, "node": -1}})
                added += 1
    return segs, dropped, added


def link_params(s):
    """-> list of the straight pieces of one link (1 or 2)

    A long link over a curve is a chord of the real road: the navi node sits ON the road, up to a few
    metres beside the chord (measured: mean 0.1 m, p95 0.25 m, max 4.9 m; the navi direction is the
    chord direction). With the lanes centred on the navi line of every link, the neighbouring links
    of a curve were offset against each other, which was the step in the wheel tracks. So a link
    whose navi point is off the chord becomes two pieces, A -> navi point -> B, and the lanes follow
    that bent line (the joints are shared with the next link, so the road is continuous)."""
    nv = s["navi"]
    ax, ay, az = s["a"]
    bx, by, bz = s["b"]
    dx, dy = bx - ax, by - ay
    length = math.hypot(dx, dy)
    if length < 0.5:
        return []
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
    code = left + right * 4 + int(round(med_half / 0.5)) * 16
    rnx, rny = ndy, -ndx                      # right-hand side of the driving direction (navi)

    pts = [(ax, ay, az), (bx, by, bz)]
    t_navi = (nv["x"] - ax) * tx + (nv["y"] - ay) * ty
    off = (nv["x"] - ax) * (ty) + (nv["y"] - ay) * (-tx)
    if 0.5 < t_navi < length - 0.5 and CURVE_MIN_OFFSET < abs(off) < CURVE_MAX_OFFSET:
        nz = az + (bz - az) * (t_navi / length)
        pts = [(ax, ay, az), (nv["x"], nv["y"], nz), (bx, by, bz)]
    pieces = []
    for (x0, y0, z0), (x1, y1, z1) in zip(pts[:-1], pts[1:]):
        sx, sy = x1 - x0, y1 - y0
        sl = math.hypot(sx, sy)
        if sl < 0.3:
            continue
        stx, sty = sx / sl, sy / sl
        rx, ry = sty, -stx
        if rx * rnx + ry * rny < 0:
            rx, ry = -rx, -ry
        pieces.append({"ax": x0, "ay": y0, "az": z0, "bx": x1, "by": y1, "bz": z1, "tx": stx, "ty": sty, "len": sl,
                       "rx": rx, "ry": ry, "cx": x0, "cy": y0, "half": half_w + MARGIN, "code": code,
                       "clip": s.get("clip", ())})   # open ends of a custom road chain (apply_custom)
    return pieces


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
    s_along = (X - L["ax"]) * L["tx"] + (Y - L["ay"]) * L["ty"]
    t = np.clip(s_along, 0, L["len"])
    px, py = L["ax"] + L["tx"] * t, L["ay"] + L["ty"] * t
    vx, vy = X - px, Y - py
    dist = np.hypot(vx, vy)
    # lateral distance to the line of the link (the lanes are laid out around it)
    dline = (X - L["cx"]) * L["rx"] + (Y - L["cy"]) * L["ry"]
    # past an end: the signed distance to the end node, direction = radial (round join)
    past = (s_along < 0) | (s_along > L["len"])
    dot_r = vx * L["rx"] + vy * L["ry"]
    side = np.where(np.abs(dot_r) > 0.2 * dist, np.sign(dot_r), np.sign(dline))
    side = np.where(side == 0, 1.0, side)
    safe = np.maximum(dist, 1e-6)
    d = np.where(past, side * dist, dline)
    nx = np.where(past & (dist > 0.05), vx / safe * side, L["rx"])
    ny = np.where(past & (dist > 0.05), vy / safe * side, L["ry"])
    ang = np.arctan2(ny, nx) % (2 * np.pi)
    z = L["az"] + (L["bz"] - L["az"]) * (t / L["len"])
    cand = (dist <= L["half"]) & (np.abs(d) < D_RANGE)
    for cx_, cy_, nx_, ny_ in L["clip"]:
        cand &= (X - cx_) * nx_ + (Y - cy_) * ny_ >= 0
    inside = cand & ~past & (np.abs(dline) < L["half"] - MARGIN + 0.5)   # on the lanes of this very piece
    return (slice(j0, j1 + 1), slice(i0, i1 + 1)), dist, d, z, cand, ang, inside


class Layer:
    def __init__(self):
        self.best = np.full((N, N), np.inf, dtype=np.float32)
        self.dc = np.zeros((N, N), dtype=np.float32)
        self.ang = np.zeros((N, N), dtype=np.float32)
        self.code = np.zeros((N, N), dtype=np.uint8)
        self.z = np.zeros((N, N), dtype=np.float32)

    def put(self, sl, take, L, dist, d, z, ang):
        self.best[sl][take] = dist[take]
        self.dc[sl][take] = d[take]
        self.ang[sl][take] = ang[take]
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


def _unit(x, y):
    n = math.hypot(x, y)
    return (x / n, y / n) if n > 1e-6 else (0.0, 0.0)


def _arm_lanes(u, navi):
    """lanes of an arm (u = unit vector from the junction along the arm) -> (r_n, W, in_d, out_d)
    in_d / out_d: lateral centre (along the navi right normal, like the map) of every inbound / outbound
    lane, from the median outwards."""
    nx, ny = _unit(navi["dx"], navi["dy"])
    if nx == 0 and ny == 0:
        nx, ny = -u[0], -u[1]
    r_n = (ny, -nx)
    left, right = min(3, navi["left"]), min(3, navi["right"])
    if left + right == 0:
        left = right = 1
    med = 2 * min(7.5, navi["width"] / 8.0 / 2.0)
    W = (left + right) * LANE + med
    leftW = left * LANE

    def centres(side, n):          # side +1 = right lanes of the map, -1 = left lanes; k from the median out
        out = []
        for k in range(n):
            x = leftW + med + (k + 0.5) * LANE if side > 0 else leftW - (k + 0.5) * LANE
            out.append(x - W / 2)
        return out

    to_j = (-u[0], -u[1])
    if left > 0 and right > 0:
        # right hand traffic: the lanes on the right of the travel towards the junction are inbound;
        # rightOf(v) = (v.y, -v.x), compared with the navi right normal
        in_side = 1 if (to_j[1] * r_n[0] - to_j[0] * r_n[1]) > 0 else -1
        n_in = right if in_side > 0 else left
        n_out = left if in_side > 0 else right
        return r_n, W, centres(in_side, n_in), centres(-in_side, n_out)
    # one way: the right lanes flow along the navi direction, the left lanes against it
    # (checked on a divided road: consecutive links of one carriageway differ in navi direction but the
    # lanes are always on the same side, L2 R0 against / L0 R2 along)
    side = 1 if right > 0 else -1
    lanes = centres(side, right if right > 0 else left)
    fx, fy = (nx, ny) if right > 0 else (-nx, -ny)
    if fx * to_j[0] + fy * to_j[1] > 0:       # flowing towards the junction
        return r_n, W, lanes, []
    return r_n, W, [], lanes


def _label_junctions(junction):
    """-> dict cell (i, j) -> component id of the 8-connected junction cells (dilated by 1 cell so that the two
    squares of a divided road join), and the number of components"""
    cells = set(zip(*[a.tolist() for a in np.nonzero(junction.T)]))        # (i, j)
    grown = set(cells)
    for (i, j) in cells:
        for di in (-1, 0, 1):
            for dj in (-1, 0, 1):
                grown.add((i + di, j + dj))
    comp = {}
    n = 0
    for start in grown:
        if start in comp:
            continue
        stack = [start]
        comp[start] = n
        while stack:
            ci, cj = stack.pop()
            for di in (-1, 0, 1):
                for dj in (-1, 0, 1):
                    nb = (ci + di, cj + dj)
                    if nb in grown and nb not in comp:
                        comp[nb] = n
                        stack.append(nb)
        n += 1
    return comp, n


def _comp_at(comp, x, y, radius=1):
    """component id at a world point (looking radius cells around), or None"""
    i, j = int((x - MIN_X) // CELL), int((y - MIN_Y) // CELL)
    for di in range(-radius, radius + 1):
        for dj in range(-radius, radius + 1):
            c = comp.get((i + di, j + dj))
            if c is not None:
                return c
    return None


def junction_paths(segs, junction, zmap, has1):
    """-> list of the traffic paths through the junctions:
    { p0, p1, p2 (x, y), type, fa, fb (noise frame of the entry / exit arm flipped), z },
    and the CORE cells of the junctions (bool N x N)

    One junction = one connected blob of junction cells (a divided road crossing is several navi nodes with
    short links between them, so the node graph is no good). Its ARMS are the vehicle links that end in the
    blob and start outside of it (collinear duplicates dropped). The blob itself is often only a part of the
    crossing (at a T junction only the squares where the stem overlaps the through road), so the CORE is
    geometric: where the road bands (lanes of the arm, from -width/2 behind its node) of two arms of clearly
    different direction overlap. A lane line of an arm is followed from the far end inwards; the first point in
    the band of another (non-parallel) arm is where the paths of that lane leave / join (fallback: the first
    junction cell). The short links inside the blob are ignored."""
    comp, ncomp = _label_junctions(junction)
    arms_of = {}
    for s in segs:
        if s["boat"] or not s["navi"]:
            continue
        for near, far in ((s["a"], s["b"]), (s["b"], s["a"])):
            c = _comp_at(comp, near[0], near[1])
            if c is None or _comp_at(comp, far[0], far[1], 0) == c:
                continue
            u = _unit(far[0] - near[0], far[1] - near[1])
            if u == (0.0, 0.0):
                continue
            r_n, W, in_d, out_d = _arm_lanes(u, s["navi"])
            nd = _unit(s["navi"]["dx"], s["navi"]["dy"])
            if nd == (0.0, 0.0):
                nd = (-u[0], -u[1])
            seg_len = math.hypot(far[0] - near[0], far[1] - near[1])
            arms_of.setdefault(c, []).append({"p": near, "u": u, "r": r_n, "in": in_d, "out": out_d, "len": seg_len,
                                              "nd": nd, "W": W})
    # collinear duplicates (the next link of the same road, its near node still beside the blob): keep the inner one
    for c, arms in arms_of.items():
        cx = sum(a["p"][0] for a in arms) / len(arms)
        cy = sum(a["p"][1] for a in arms) / len(arms)
        arms.sort(key=lambda a: math.hypot(a["p"][0] - cx, a["p"][1] - cy))
        keep = []
        for a in arms:
            dup = False
            for b in keep:
                if a["u"][0] * b["u"][0] + a["u"][1] * b["u"][1] > 0.98:
                    dx, dy = a["p"][0] - b["p"][0], a["p"][1] - b["p"][1]
                    if abs(dx * b["u"][1] - dy * b["u"][0]) < 1.0:
                        dup = True
                        break
            if not dup:
                keep.append(a)
        arms_of[c] = keep
    paths = []
    entry_stats = {"band": 0, "fork": 0, "blob": 0, "node": 0}
    core = np.zeros((N, N), dtype=bool)
    par = math.cos(JUNCTION_ANGLE)

    def in_band(b, x, y, back):
        """point (x, y) on the road band of arm b (numpy ok); back = metres the band reaches behind the node"""
        dx, dy = x - b["p"][0], y - b["p"][1]
        s_ = dx * b["u"][0] + dy * b["u"][1]
        lat = np.abs(dx * b["u"][1] - dy * b["u"][0])
        return (s_ >= -back) & (s_ <= b["len"]) & (lat <= b["W"] / 2)

    def entry(c, arm, d):
        """point where the lane line of the arm (lateral offset d) first reaches component c, walking in,
        moved EXTEND m out along the arm"""
        off = (arm["r"][0] * d, arm["r"][1] * d)
        crossing = [b for b in arms_of[c] if b is not arm and abs(b["u"][0] * arm["u"][0] + b["u"][1] * arm["u"][1]) < par]
        # a fork / merge (all other arms nearly parallel): where the lane leaves the other roads' bands
        others = [b for b in arms_of[c] if b is not arm and b["u"][0] * arm["u"][0] + b["u"][1] * arm["u"][1] > -par]
        for kind, cand in (("band", crossing), ("fork", others)):
            if not cand:
                continue
            t = min(arm["len"], TURN_SCAN)
            while t >= -TURN_BACK:
                x, y = arm["p"][0] + arm["u"][0] * t + off[0], arm["p"][1] + arm["u"][1] * t + off[1]
                if any(in_band(b, x, y, arm["W"] / 2 + 0.5) for b in cand):
                    t += 1.0 + EXTEND       # one metre before the band of the crossing road + the overlap
                    entry_stats[kind] += 1
                    return (arm["p"][0] + arm["u"][0] * t + off[0], arm["p"][1] + arm["u"][1] * t + off[1])
                t -= 0.5
        t = min(arm["len"], TURN_SCAN)
        hit = None
        while t >= -TURN_BACK:
            x, y = arm["p"][0] + arm["u"][0] * t + off[0], arm["p"][1] + arm["u"][1] * t + off[1]
            i, j = int((x - MIN_X) // CELL), int((y - MIN_Y) // CELL)
            if 0 <= i < N and 0 <= j < N and junction[j, i] and comp.get((i, j)) == c:
                hit = t                     # the first junction cell on the way in (the largest t)
                break
            t -= 1.0
        if hit is None:                     # nothing found: the lane line at the node
            entry_stats["node"] += 1
            DEBUG.setdefault("node", []).append((c, id(arm)))
            hit = 0.0
        else:
            entry_stats["blob"] += 1
        hit += 1.0 + EXTEND                 # one metre before the first junction cell + the overlap
        return (arm["p"][0] + arm["u"][0] * hit + off[0], arm["p"][1] + arm["u"][1] * hit + off[1])

    skipped = 0
    for c, arms in arms_of.items():
        if len(arms) < 2:
            continue
        if len(arms) > MAX_ARMS:
            skipped += 1
            continue
        # core cells: inside the bands of two arms of different direction, at the junction height
        back = max(a["W"] for a in arms) / 2 + 0.5
        xs_ = [a["p"][0] for a in arms]
        ys_ = [a["p"][1] for a in arms]
        i0 = max(0, int((min(xs_) - 30 - MIN_X) // CELL))
        i1 = min(N - 1, int((max(xs_) + 30 - MIN_X) // CELL))
        j0 = max(0, int((min(ys_) - 30 - MIN_Y) // CELL))
        j1 = min(N - 1, int((max(ys_) + 30 - MIN_Y) // CELL))
        X, Y = np.meshgrid(MIN_X + (np.arange(i0, i1 + 1) + 0.5) * CELL, MIN_Y + (np.arange(j0, j1 + 1) + 0.5) * CELL)
        bands = [in_band(a, X, Y, back) for a in arms]
        cc = np.zeros(X.shape, dtype=bool)
        for ka in range(len(arms)):
            for kb in range(ka + 1, len(arms)):
                ua, ub = arms[ka]["u"], arms[kb]["u"]
                if abs(ua[0] * ub[0] + ua[1] * ub[1]) < par:
                    cc |= bands[ka] & bands[kb]
        zj = arms[0]["p"][2]
        sl = (slice(j0, j1 + 1), slice(i0, i1 + 1))
        cc &= has1[sl] & (np.abs(zmap[sl] - zj) < LAYER_DZ)
        core[sl] |= cc
        for i, ai in enumerate(arms):
            for j, aj in enumerate(arms):
                if i == j or not ai["in"] or not aj["out"]:
                    continue
                tin = (-ai["u"][0], -ai["u"][1])        # travel direction into the junction
                tout = aj["u"]                          # and out of it
                dot = tin[0] * tout[0] + tin[1] * tout[1]
                cross = tin[0] * tout[1] - tin[1] * tout[0]
                if dot < -0.9:                          # U turn
                    continue
                right_turn = cross < -0.35
                ptype = TYPE_RIGHT if right_turn else (TYPE_LEFT if cross > 0.35 else TYPE_STRAIGHT)
                # the lane noise frame of a link runs along its navi direction: flipped when the travel is against it
                fa = 1 if (tin[0] * ai["nd"][0] + tin[1] * ai["nd"][1]) < 0 else 0
                fb = 1 if (tout[0] * aj["nd"][0] + tout[1] * aj["nd"][1]) < 0 else 0
                nI, nO = len(ai["in"]), len(aj["out"])
                for t in range(min(nI, nO)):
                    ia, ib = (nI - 1 - t, nO - 1 - t) if right_turn else (t, t)
                    p0 = entry(c, ai, ai["in"][ia])
                    p2 = entry(c, aj, aj["out"][ib])
                    if p0 is None or p2 is None:
                        continue
                    # control point: the entry lane line (p0 + t * tin) meets the exit lane line (p2 - s * tout)
                    p1 = ((p0[0] + p2[0]) / 2, (p0[1] + p2[1]) / 2)
                    det = tin[0] * tout[1] - tin[1] * tout[0]       # t * tin + s * tout = p2 - p0
                    if abs(det) > 0.2:
                        rx, ry = p2[0] - p0[0], p2[1] - p0[1]
                        tt = (rx * tout[1] - ry * tout[0]) / det
                        ss = (tin[0] * ry - tin[1] * rx) / det
                        if 0 < tt < 50 and 0 < ss < 50:
                            p1 = (p0[0] + tin[0] * tt, p0[1] + tin[1] * tt)
                    paths.append({"p0": p0, "p1": p1, "p2": p2, "type": ptype, "fa": fa, "fb": fb, "z": ai["p"][2]})
    DEBUG["arms_of"], DEBUG["comp"], DEBUG["paths"] = arms_of, comp, paths
    print(f"junction blobs: {ncomp} ({len(arms_of)} with arms), paths: {len(paths)}, core cells: {int(core.sum())}, entries: {entry_stats}, "
          f"skipped (> {MAX_ARMS} arms): {skipped}")
    return paths, core


def bezier(p, f):
    """points of the path at parameters f (numpy array) -> (x, y)"""
    p0, p1, p2 = p["p0"], p["p1"], p["p2"]
    a, b, c = (1 - f) ** 2, 2 * f * (1 - f), f * f
    return a * p0[0] + b * p1[0] + c * p2[0], a * p0[1] + b * p1[1] + c * p2[1]


def path_length(p):
    p0, p1, p2 = p["p0"], p["p1"], p["p2"]
    return (math.dist(p0, p2) + math.dist(p0, p1) + math.dist(p1, p2)) / 2


def path_lists(paths, junction, z1, has1):
    """-> per cell list of path indices (dict flat cell -> [idx]), the list cells, stats

    The list cells are the junction cells + the one cell ring around them. A path is listed in a cell when
    it passes within LIST_R m of the cell square (sampled every <= 0.5 m)."""
    ring = np.zeros_like(junction)
    J = junction
    for dj in (-1, 0, 1):
        for di in (-1, 0, 1):
            ring |= np.roll(np.roll(J, dj, axis=0), di, axis=1)
    listable = ring                         # junction + ring
    entries = {}
    zcell = {}
    for k, p in enumerate(paths):
        n = max(4, int(math.ceil(path_length(p) / 0.5)))
        xs, ys = bezier(p, np.linspace(0, 1, n + 1))
        i0 = max(0, int((xs.min() - LIST_R - MIN_X) // CELL))
        i1 = min(N - 1, int((xs.max() + LIST_R - MIN_X) // CELL))
        j0 = max(0, int((ys.min() - LIST_R - MIN_Y) // CELL))
        j1 = min(N - 1, int((ys.max() + LIST_R - MIN_Y) // CELL))
        jj, ii = np.nonzero(listable[j0:j1 + 1, i0:i1 + 1])
        if not len(ii):
            continue
        ii, jj = ii + i0, jj + j0
        x0 = MIN_X + ii * CELL
        y0 = MIN_Y + jj * CELL
        dx = np.maximum(np.maximum(x0[:, None] - xs[None, :], 0), xs[None, :] - (x0[:, None] + CELL))
        dy = np.maximum(np.maximum(y0[:, None] - ys[None, :], 0), ys[None, :] - (y0[:, None] + CELL))
        dmin = np.sqrt(dx * dx + dy * dy).min(axis=1)
        w = WEIGHT[p["type"]]
        for ci, cj, dd in zip(ii[dmin <= LIST_R], jj[dmin <= LIST_R], dmin[dmin <= LIST_R]):
            key = int(cj) * N + int(ci)
            entries.setdefault(key, []).append((-w, float(dd), k))
            zcell.setdefault(key, p["z"])
    lists, lengths, dropped = {}, [], 0
    for key, e in entries.items():
        e.sort()
        lengths.append(len(e))
        if len(e) > K:
            dropped += len(e) - K
        lists[key] = [k for _, _, k in e[:K]]
    return lists, zcell, np.array(lengths), dropped, ring & ~junction


def encode_paths(paths):
    """-> jpaths image (JTEX_W wide, 4 texels per path), number of paths dropped (points beyond REL)"""
    n = len(paths)
    rows = max(1, int(math.ceil(n * 4 / JTEX_W)))
    img = np.zeros((rows, JTEX_W, 4), dtype=np.uint8)
    flat = img.reshape(-1, 4)
    bad = 0

    def put16(t, lo, v):
        v = int(min(65535, max(0, v)))
        flat[t, lo], flat[t, lo + 1] = v >> 8, v & 255

    for k, p in enumerate(paths):
        xs = [p["p0"][0], p["p1"][0], p["p2"][0]]
        ys = [p["p0"][1], p["p1"][1], p["p2"][1]]
        ci = int(((min(xs) + max(xs)) / 2 - MIN_X) // CELL)
        cj = int(((min(ys) + max(ys)) / 2 - MIN_Y) // CELL)
        ox, oy = MIN_X + ci * CELL, MIN_Y + cj * CELL
        rel = [(x - ox, y - oy) for x, y in (p["p0"], p["p1"], p["p2"])]
        if any(abs(v) >= REL for xy in rel for v in xy) or not (0 <= ci < 2048 and 0 <= cj < N):
            bad += 1
            p["bad"] = True
            continue
        put16(4 * k, 0, ci + (p["type"] << 11) + (p["fa"] << 13) + (p["fb"] << 14))
        put16(4 * k, 2, cj)
        for m, (rx, ry) in enumerate(rel):
            put16(4 * k + 1 + m, 0, round((rx + REL) / (2 * REL) * 65535))
            put16(4 * k + 1 + m, 2, round((ry + REL) / (2 * REL) * 65535))
    return img, bad


def encode_lists(lists, junction, ring):
    """-> junction layer image (N x N), jlists image"""
    jimg = np.zeros((N, N, 4), dtype=np.uint8)
    jimg[ring, 3] = RING_A
    jimg[junction, 3] = 255
    words = []
    for key in sorted(lists):
        lst = [k for k in lists[key]]
        off = len(words) // 2
        if off > 65535:
            raise SystemExit("jlists offset over 16 bit")
        cj, ci = divmod(key, N)
        jimg[cj, ci, 0], jimg[cj, ci, 1], jimg[cj, ci, 2] = off >> 8, off & 255, len(lst)
        words += lst
        if len(words) % 2:
            words.append(0)
    texels = max(1, len(words) // 2)
    rows = max(1, int(math.ceil(texels / JTEX_W)))
    limg = np.zeros((rows * JTEX_W, 4), dtype=np.uint8)
    for t in range(len(words) // 2):
        a, b = words[2 * t], words[2 * t + 1]
        limg[t] = (a >> 8, a & 255, b >> 8, b & 255)
    return jimg, limg.reshape(rows, JTEX_W, 4), texels


def z16(z):
    return np.clip(np.round((z - Z_MIN) / (Z_MAX - Z_MIN) * 65535), 0, 65535).astype(np.uint32)


def build(paths_dir):
    areas = read_all(paths_dir)
    segs, c_drop, c_add = apply_custom(road_segments(areas))
    print(f"custom roads ({os.path.basename(CUSTOM)}): {c_drop} GTA links dropped, {c_add} links added")
    links = [L for s in segs if not s["boat"] and s["navi"] for L in link_params(s)]
    one, two = Layer(), Layer()
    geo = [(L, cells_of(L)) for L in links]
    for L, r in geo:                      # layer 1: nearest link
        if not r:
            continue
        sl, dist, d, z, cand, ang, inside = r
        take = cand & (dist < one.best[sl])
        if take.any():
            one.put(sl, take, L, dist, d, z, ang)
    has1 = np.isfinite(one.best)
    # junctions: lanes of differently directed links over each other
    first_ang = np.full((N, N), np.nan, dtype=np.float32)
    first_z = np.zeros((N, N), dtype=np.float32)
    cross = np.zeros((N, N), dtype=bool)
    for L, r in geo:
        if not r:
            continue
        sl, dist, d, z, cand, ang, inside = r
        seg = math.atan2(L["ty"], L["tx"]) % math.pi
        fa, fz = first_ang[sl], first_z[sl]
        have = ~np.isnan(fa)
        diff = np.abs(((seg - np.where(have, fa, 0) + math.pi / 2) % math.pi) - math.pi / 2)
        cross[sl] |= inside & have & (np.abs(z - fz) < LAYER_DZ) & (diff > JUNCTION_ANGLE)
        new = inside & ~have
        fa[new] = seg
        fz[new] = z[new]
    junction = cross & has1
    # paths through the junctions + the path lists of the junction and ring cells
    paths, core = junction_paths(segs, junction, one.z, has1)
    blob = junction
    junction = junction | core              # the junction mask: blob cells + the geometric core
    jpaths, bad = encode_paths(paths)
    good = [k for k, p in enumerate(paths) if not p.get("bad")]
    if len(paths) > 65535:
        raise SystemExit(f"{len(paths)} paths: over the 16 bit path index")
    lists, zcell, lengths, dropped, ring = path_lists([p for p in paths], junction, one.z, has1)
    goodset = set(good)
    lists = {key: [k for k in lst if k in goodset] for key, lst in lists.items()}
    lists = {key: lst for key, lst in lists.items() if lst}
    jimg, jlists, texels = encode_lists(lists, junction, ring)
    # list cells without a layer 1 link: the junction height, so the shader can match the layer
    jz = np.zeros((N, N), dtype=bool)
    for key in lists:
        cj, ci = divmod(key, N)
        if not has1[cj, ci]:
            one.z[cj, ci] = zcell[key]
            jz[cj, ci] = True
    stats = {
        "junction_cells": int(blob.sum()), "mask_cells": int(junction.sum()), "paths": len(paths), "paths_beyond_rel": bad,
        "list_cells": len(lists), "list_len_p50": float(np.percentile(lengths, 50)) if len(lengths) else 0,
        "list_len_p95": float(np.percentile(lengths, 95)) if len(lengths) else 0,
        "list_len_max": int(lengths.max()) if len(lengths) else 0,
        "cells_over_k": int((lengths > K).sum()), "entries_dropped": dropped,
        "jlist_texels": texels, "jpaths_bytes": int(jpaths.nbytes), "jlists_bytes": int(jlists.nbytes),
        "list_cells_without_layer1": int(jz.sum()),
        "max_path_extent": max((max(abs(a - b) for a, b in ((p["p0"][0], p["p2"][0]), (p["p0"][1], p["p2"][1]),
                                                             (p["p1"][0], p["p0"][0]), (p["p1"][1], p["p0"][1])))
                                for p in paths), default=0),
    }
    for t in (TYPE_STRAIGHT, TYPE_RIGHT, TYPE_LEFT):
        stats[f"paths_type{t}"] = sum(1 for p in paths if p["type"] == t)
    print("junction stats:", json.dumps(stats))
    for L, r in geo:                      # layer 2: nearest link at another height
        if not r:
            continue
        sl, dist, d, z, cand, ang, inside = r
        take = cand & has1[sl] & (np.abs(z - one.z[sl]) > LAYER_DZ) & (dist < two.best[sl])
        if take.any():
            two.put(sl, take, L, dist, d, z, ang)
    has2 = np.isfinite(two.best)
    zimg = np.zeros((N, N, 4), dtype=np.uint8)
    za, zb = z16(one.z), z16(two.z)
    zimg[..., 0], zimg[..., 1] = (za >> 8).astype(np.uint8), (za & 255).astype(np.uint8)
    zimg[..., 2], zimg[..., 3] = (zb >> 8).astype(np.uint8), (zb & 255).astype(np.uint8)
    zimg[~(has1 | jz), 0:2] = 0
    zimg[~has2, 2:4] = 0
    return {"one": one.image(), "two": two.image(), "z": zimg, "j": jimg, "jpaths": jpaths, "jlists": jlists,
            "links": len(links), "n1": int(has1.sum()), "n2": int(has2.sum()), "stats": stats}


CHUNK = 256


def write_chunks(layers):
    """-> list of "cx_cy" of the chunks written"""
    out_dir = os.path.join(ROOT, "data", "road")
    os.makedirs(out_dir, exist_ok=True)
    for old in os.listdir(out_dir):
        if old.startswith("c_") and old.endswith(".png"):
            os.remove(os.path.join(out_dir, old))
    have = []
    for cy in range(N // CHUNK):
        for cx in range(N // CHUNK):
            sl = (slice(cy * CHUNK, (cy + 1) * CHUNK), slice(cx * CHUNK, (cx + 1) * CHUNK))
            parts = [img[sl] for img in layers]
            if not any(p.any() for p in parts):
                continue
            Image.fromarray(np.concatenate(parts, axis=0), "RGBA").save(
                os.path.join(out_dir, f"c_{cx}_{cy}.png"), optimize=True)
            have.append(f"{cx}_{cy}")
    return have


def patch_meta(have):
    p = os.path.join(ROOT, "meta.xml")
    s = open(p, encoding="utf-8").read()
    start, end = "<!-- ROAD CHUNKS BEGIN -->", "<!-- ROAD CHUNKS END -->"
    files = [f"data/road/c_{c}.png" for c in have] + ["data/road/jpaths.png", "data/road/jlists.png"]
    block = start + "\n" + "".join(f'    <file src="{f}" />\n' for f in files) + "    " + end
    i, j = s.index(start), s.index(end) + len(end)
    open(p, "w", encoding="utf-8").write(s[:i] + block + s[j:])


if __name__ == "__main__":
    paths = sys.argv[1] if len(sys.argv) > 1 else r"C:\Games\GTA San Andreas\data\Paths"
    r = build(paths)
    for name, key in (("roadmap.png", "one"), ("roadmap2.png", "two"), ("roadmapz.png", "z"), ("roadmapj.png", "j")):
        Image.fromarray(r[key], "RGBA").save(os.path.join(ROOT, "data", name), optimize=True)
    have = write_chunks([r["one"], r["two"], r["z"], r["j"]])
    Image.fromarray(r["jpaths"], "RGBA").save(os.path.join(ROOT, "data", "road", "jpaths.png"), optimize=True)
    Image.fromarray(r["jlists"], "RGBA").save(os.path.join(ROOT, "data", "road", "jlists.png"), optimize=True)
    patch_meta(have)
    with open(os.path.join(ROOT, "data", "roadmap.json"), "w", encoding="utf-8") as f:
        json.dump([{"minX": MIN_X, "minY": MIN_Y, "size": SIZE, "cells": N, "lane": LANE, "dRange": D_RANGE,
                    "zMin": Z_MIN, "zMax": Z_MAX, "format": 4, "links": r["links"],
                    "chunk": CHUNK, "chunks": have, "layers": 4,
                    "k": K, "jRel": REL, "jPaths": int(r["stats"]["paths"]),
                    "jPathSize": [JTEX_W, int(r["jpaths"].shape[0])],
                    "jListSize": [JTEX_W, int(r["jlists"].shape[0])],
                    "junction": r["stats"]}], f, indent=4)
    print(f"roadmap {N}x{N}, {r['links']} links, layer 1: {r['n1']} cells, layer 2: {r['n2']} cells, {len(have)} chunks")
