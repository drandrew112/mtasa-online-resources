"""Builds v_radar/interiors/*.png + index.json from the probe scans (scan.lua grids)."""
import json, os
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = r"C:\Dev\MTASA\server\mods\deathmatch\resources\[ui]\v_radar\interiors"
PPM = 10  # image pixels per metre (scan cell 0.2 m -> x2)

C_FOOT = (132, 136, 142, 255)     # roofed, not walkable: grey
C_FLOOR = [(206, 209, 213, 255),  # main level: light grey-white
           (190, 193, 198, 255)]  # second level: a bit darker
C_FURN = (196, 199, 204, 255)     # furniture: light grey
C_WALL = (78, 82, 88, 255)        # walls: darker grey


def load(name):
    d = json.load(open(os.path.join(HERE, name + ".json")))
    g = np.frombuffer(d["data"].encode(), np.uint8).reshape(d["ny"], d["nx"]).astype(np.int32) - 48
    return d, g


def dilate(m, r=1):
    o = m.copy()
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            o |= np.roll(np.roll(m, dy, 0), dx, 1)
    return o


def erode(m, r=1):
    return ~dilate(~m, r)


def label(m):
    import collections
    lab = np.zeros(m.shape, np.int32); n = 0; H, W = m.shape
    for y0, x0 in zip(*np.nonzero(m)):
        if lab[y0, x0]:
            continue
        n += 1; q = collections.deque([(y0, x0)]); lab[y0, x0] = n
        while q:
            y, x = q.popleft()
            for yy, xx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
                if 0 <= yy < H and 0 <= xx < W and m[yy, xx] and not lab[yy, xx]:
                    lab[yy, xx] = n; q.append((yy, xx))
    return lab, n


def build(map_id, scans, crop, footprint="ceil", close=2, keep=None, min_cells=600, cut=(), colors=None):
    """footprint: "ceil" = roofed cells next to the walkable area, "rect" = bounding box of the walkable area,
    None = nothing (game interiors). keep(cx, cy, cells) -> bool filters walkable components (world centre)."""
    """scans: list of scan names (same grid), first = main level. crop: (x0, y0, x1, y1) world."""
    d0, _ = load(scans[0])
    cell = d0["cell"]
    floors, walls, furns, ceil = [], [], [], None
    for s in scans:
        d, g = load(s)
        assert (d["x0"], d["y0"], d["nx"], d["ny"]) == (d0["x0"], d0["y0"], d0["nx"], d0["ny"])
        fl = ((g & 4) > 0) & ((g & 8) > 0)
        fl = erode(dilate(fl, close), close)           # fill small holes (stair edges, poles)
        floors.append(fl)
        walls.append((g & 3) == 3)
        furns.append(((g & 1) > 0) & ((g & 2) == 0))
        if ceil is None:
            ceil = (g & 8) > 0
    walk = np.zeros_like(floors[0])
    for fl in floors:
        walk |= fl
    # cut = world rectangles removed from the plan (rooms nobody can enter, e.g. behind a lift door)
    for (ax, ay, bx, by) in cut:
        walk[int((ay - d0["y0"]) / cell):int((by - d0["y0"]) / cell) + 1, int((ax - d0["x0"]) / cell):int((bx - d0["x0"]) / cell) + 1] = False
    lab, n = label(walk)
    good = np.zeros(n + 1, bool)
    for i in range(1, n + 1):
        ys, xs = np.nonzero(lab == i)
        cx = d0["x0"] + xs.mean() * cell; cy = d0["y0"] + ys.mean() * cell
        good[i] = len(xs) >= min_cells and (keep is None or keep(cx, cy, len(xs)))
    walk = good[lab]
    level = np.full(walk.shape, -1)
    for i, fl in enumerate(floors):
        level[fl & walk & (level < 0)] = i
    # small islands of one level inside another (a counter top read as floor) take the surrounding level
    for i in range(len(scans)):
        lab2, n2 = label(level == i)
        for k in range(1, n2 + 1):
            m = lab2 == k
            if m.sum() < 120:
                ring = dilate(m, 1) & ~m & (level >= 0)
                if ring.any():
                    level[m] = np.bincount(level[ring]).argmax()
    wall = np.zeros_like(walk)
    for i in range(len(scans)):
        near = dilate(level == i, 3)
        wall |= walls[i] & near
    wall = dilate(wall, 1)                              # ~0.6 m thick, readable at minimap scale
    furn = np.zeros_like(walk)
    for i in range(len(scans)):
        furn |= furns[i] & (level == i)
    furn &= ~wall

    h, w = walk.shape
    img = np.zeros((h, w, 4), np.uint8)
    foot = np.zeros_like(walk)
    if footprint == "ceil":
        foot = ceil & dilate(walk, 6)
    elif footprint == "rect":
        ys, xs = np.nonzero(walk)
        foot[max(0, ys.min() - 3):ys.max() + 4, max(0, xs.min() - 3):xs.max() + 4] = True
    img[foot] = C_FOOT
    border = foot & ~erode(foot, 2) & ~dilate(walk, 1)
    for i in range(len(scans)):
        ci = colors[i] if colors else min(i, len(C_FLOOR) - 1)
        img[level == i] = C_FLOOR[ci]
    img[wall & (dilate(walk, 2) | foot)] = C_WALL
    if footprint == "rect":
        img[border] = C_WALL

    # crop (grid row 0 = y0 = south) and flip so north is up
    x0, y0, x1, y1 = crop
    cx0 = int(round((x0 - d0["x0"]) / cell)); cx1 = int(round((x1 - d0["x0"]) / cell))
    cy0 = int(round((y0 - d0["y0"]) / cell)); cy1 = int(round((y1 - d0["y0"]) / cell))
    img = img[cy0:cy1, cx0:cx1][::-1]
    scale = int(PPM * cell)
    im = Image.fromarray(img, "RGBA").resize((img.shape[1] * scale, img.shape[0] * scale), Image.NEAREST)
    os.makedirs(OUT, exist_ok=True)
    im.save(os.path.join(OUT, map_id + ".png"), optimize=True)
    ys, xs = np.nonzero(walk)
    print(map_id, im.size, "walkable x %.1f..%.1f y %.1f..%.1f" % (
        d0["x0"] + xs.min() * cell, d0["x0"] + xs.max() * cell, d0["y0"] + ys.min() * cell, d0["y0"] + ys.max() * cell))
    return {"image": map_id + ".png", "x": x0, "y": y1, "width": x1 - x0, "height": y1 - y0}


if __name__ == "__main__":
    entries = []
    e = build("ls_allsaints", ["as_g"], (1137, -1388, 1176, -1288), keep=lambda cx, cy, n: cx > 1136)
    e.update({"id": "ls_allsaints", "name": "All Saints General Hospital", "interior": 0,
              "zones": [{"min": [1149.6, -1384.5, 13.6], "max": [1172.4, -1290.8, 19.0]}]})
    entries.append(e)
    e = build("ls_pd", ["pd_15.2", "pd_16.6", "pd_14.0"], (1549, -1697, 1593, -1639), footprint=None,
              colors=[0, 1, 1], cut=[(1582.6, -1678.6, 1591.0, -1669.0)],  # lift-door room (locked)
              keep=lambda cx, cy, n: cx < 1580 and cy > -1694)
    e.update({"id": "ls_pd", "name": "Los Santos Police Department", "interior": 0,
              "zones": [{"min": [1551, -1695, 14.8], "max": [1591, -1641, 19.2]}]})
    entries.append(e)
    e = build("ls_pd_jail", ["pd_jail"], (1567, -1706, 1607, -1687), footprint=None,
              keep=lambda cx, cy, n: cy < -1688)
    e.update({"id": "ls_pd_jail", "name": "LSPD Jail", "interior": 0,
              "zones": [{"min": [1568.5, -1704, 12.2], "max": [1605.5, -1689.5, 14.79]}]})
    entries.append(e)
    e = build("ls_pd_garage", ["pd_lower"], (1523, -1725, 1614, -1631), footprint=None,
              keep=lambda cx, cy, n: n > 5000)
    e.update({"id": "ls_pd_garage", "name": "LSPD Garage", "interior": 0,
              "zones": [{"min": [1524, -1724, 3.5], "max": [1613, -1632, 10.0]}]})
    entries.append(e)
    e = build("sa_control", ["sac"], (172, 154, 225, 210), footprint=None)
    e.update({"id": "sa_control", "name": "SA Control", "interior": 3,
              "zones": [{"min": [172, 154, 1056.0], "max": [225, 210, 1063.0]}]})
    entries.append(e)
    index = {
        "_comment": "Minimap interior maps. x/y = world position of the image's top-left corner (north-west), "
                    "width/height = metres the image covers. interior = game interior id (0 = free-roam building). "
                    "zones = boxes (player position, min/max x,y,z) where this map replaces the world minimap; "
                    "zoom = minimap zoom multiplier inside (1 = default, 2 = twice as close, 0.5 = half; "
                    "kept when the maps are regenerated). optional dimension.",
        "maps": entries,
    }
    # zoom is edited by hand in index.json: keep the existing values, defaults for new maps
    default_zoom = {"ls_pd": 2, "ls_pd_jail": 2}
    old_zoom = {}
    try:
        for m in json.load(open(os.path.join(OUT, "index.json"), encoding="utf-8")).get("maps", []):
            old_zoom[m["id"]] = m.get("zoom")
    except Exception:
        pass
    for m in entries:
        m["zoom"] = old_zoom.get(m["id"]) or default_zoom.get(m["id"], 1)
    for m in entries:
        for k in ("x", "y", "width", "height"):
            m[k] = round(m[k], 2)
    lines = ["{", '  "_comment": %s,' % json.dumps(index["_comment"]), '  "maps": [']
    for i, m in enumerate(entries):
        lines.append("    {")
        keys = ["id", "name", "image", "x", "y", "width", "height", "interior", "zoom"]
        body = ['      "%s": %s' % (k, json.dumps(m[k])) for k in keys if k in m]
        zl = ",\n".join("        " + json.dumps(z) for z in m["zones"])
        body.append('      "zones": [\n' + zl + '\n      ]')
        lines.append(",\n".join(body))
        lines.append("    }" + ("," if i < len(entries) - 1 else ""))
    lines += ["  ]", "}", ""]
    with open(os.path.join(OUT, "index.json"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))
    print("index written")
