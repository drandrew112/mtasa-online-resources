#!/usr/bin/env python3
"""Track-line minimap image of a job map for v_radar (run: python -I tools/radar_image.py hungaroring)

Reads maps/<name>/<name>.map + the dff files, takes the triangles of the road materials (ROAD_TEXTURES)
and draws them top-down into v_radar/interiors/jobmap_<name>.png (transparent, only the track in light
grey - v_radar puts it on its dark plan background). Also writes the entry of the image into
v_radar/interiors/jobmaps.json (zones = the map's bounding box, so the image can never show elsewhere).
"""
import json
import os
import re
import struct
import sys
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RADAR = os.path.join(ROOT, "..", "..", "[ui]", "v_radar", "interiors")
ROAD_TEXTURES = {"base_dark", "base_old", "base_dark_po", "base_dark_po2", "roadh", "roadpit", "roadpitout",
                 "road_sector", "road_sector1", "roadlownew", "hung_road"}
PX_PER_M = 2          # final image
SUPER = 2             # supersampling (smooth edges)
MARGIN = 25           # metres around the track
TRACK = (232, 234, 240)


def chunks(d, s, e):
    p = s
    while p + 12 <= e:
        t, sz, _v = struct.unpack_from("<III", d, p)
        yield t, sz, p + 12
        p += 12 + sz


def geometries(d):
    """-> [(verts, tris(a, b, c, material), material names)] of a dff"""
    out = []

    def geom(s, e):
        ch = list(chunks(d, s, e))
        _t, _sz, o = ch[0]
        flags, ntri, nv, _nm = struct.unpack_from("<IIII", d, o)
        o += 16
        ver, = struct.unpack_from("<I", d, s - 4)
        if ver < 0x1003FFFF:
            o += 12
        if flags & 8:
            o += 4 * nv
        if flags & 4:
            o += 8 * nv
        tris = []
        for i in range(ntri):
            b, a, m, c = struct.unpack_from("<HHHH", d, o + 8 * i)
            tris.append((a, b, c, m))
        o += 8 * ntri + 16 + 8
        verts = struct.unpack_from("<%df" % (3 * nv), d, o)
        mats = []
        for t, sz, o1 in ch[1:]:
            if t == 8:
                for t2, s2, o2 in chunks(d, o1, o1 + sz):
                    if t2 == 7:
                        name = None
                        for t3, s3, o3 in chunks(d, o2, o2 + s2):
                            if t3 == 6:
                                for t4, s4, o4 in chunks(d, o3, o3 + s3):
                                    if t4 == 2 and name is None:
                                        name = d[o4:o4 + s4].split(bytes([0]))[0].decode()
                        mats.append(name)
        return verts, tris, mats

    for t, sz, o in chunks(d, 0, len(d)):
        if t == 0x10:
            for t2, s2, o2 in chunks(d, o, o + sz):
                if t2 == 0x1A:
                    for t3, s3, o3 in chunks(d, o2, o2 + s2):
                        if t3 == 0x0F:
                            out.append(geom(o3, o3 + s3))
    return out


def main():
    name = sys.argv[1] if len(sys.argv) > 1 else "hungaroring"
    base = os.path.join(ROOT, "maps", name)
    text = open(os.path.join(base, name + ".map"), encoding="utf-8").read()
    polys = []
    zs = []
    for m in re.finditer(r'<object\b[^>]*>', text):
        a = dict(re.findall(r'(\w+)="([^"]*)"', m.group(0)))
        if not a.get("model", "").isalpha() and not re.match(r"^[A-Za-z]", a.get("model", "")):
            continue
        dff = os.path.join(base, "models", a["model"] + ".dff")
        if not os.path.exists(dff):
            continue
        ox, oy = float(a["posX"]), float(a["posY"])
        zs.append(float(a["posZ"]))
        for verts, tris, mats in geometries(open(dff, "rb").read()):
            for ia, ib, ic, mi in tris:
                if mi < len(mats) and mats[mi] in ROAD_TEXTURES:
                    polys.append([(verts[3 * i] + ox, verts[3 * i + 1] + oy) for i in (ia, ib, ic)])
    if not polys:
        sys.exit("no road triangles found")
    x1 = min(p[0] for t in polys for p in t) - MARGIN
    x2 = max(p[0] for t in polys for p in t) + MARGIN
    y1 = min(p[1] for t in polys for p in t) - MARGIN
    y2 = max(p[1] for t in polys for p in t) + MARGIN
    x1, y1 = int(x1 // 1), int(y1 // 1)
    x2, y2 = int(x2 // 1) + 1, int(y2 // 1) + 1
    w, h = x2 - x1, y2 - y1
    s = PX_PER_M * SUPER
    mask = Image.new("L", (w * s, h * s), 0)
    dr = ImageDraw.Draw(mask)
    for t in polys:
        dr.polygon([((px - x1) * s, (y2 - py) * s) for px, py in t], fill=255)
    mask = mask.resize((w * PX_PER_M, h * PX_PER_M), Image.LANCZOS)
    img = Image.new("RGBA", mask.size, TRACK + (0,))
    img.putalpha(mask)
    os.makedirs(RADAR, exist_ok=True)
    fname = "jobmap_%s.png" % name
    img.save(os.path.join(RADAR, fname), optimize=True)

    path = os.path.join(RADAR, "jobmaps.json")
    data = {"maps": []}
    if os.path.exists(path):
        data = json.load(open(path, encoding="utf-8"))
    old = next((m for m in data["maps"] if m.get("id") == name), {})
    title = json.load(open(os.path.join(base, "map.json"), encoding="utf-8")).get("title", name)
    z1, z2 = int(min(zs)) - 60, int(max(zs)) + 120    # the track floats high above the ground: only there
    entry = {"id": name, "name": title, "image": fname, "x": x1, "y": y2, "width": w, "height": h,
             "zoom": old.get("zoom", 1),
             "zones": [{"min": [x1, y1, z1], "max": [x2, y2, z2]}]}
    data["maps"] = [m for m in data["maps"] if m.get("id") != name] + [entry]
    lines = ["{",
             '  "_comment": "Job map minimap images (written by v_jobmaps tools/radar_image.py). Same fields as index.json, but a map is only shown after exports.v_radar:setJobMapImage(id, true [, options]) (v_jobmaps does it) and only inside its zones.",',
             '  "maps": [']
    lines += ["    " + json.dumps(m) + ("," if i < len(data["maps"]) - 1 else "") for i, m in enumerate(data["maps"])]
    lines += ["  ]", "}"]
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print("%s: %dx%d m, %d triangles -> %s" % (name, w, h, len(polys), fname))


main()
