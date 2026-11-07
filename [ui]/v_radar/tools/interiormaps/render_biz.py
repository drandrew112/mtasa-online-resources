"""Builds the biz_int interior maps (biz_<template>) and merges them into interiors/index.json.
Scans: biz_os (office_standard), biz_ox (office_exclusive), biz_wf (weed_farm), biz_ca (casino)."""
import json, os
import render

OUT = render.OUT
specs = []

def add(map_id, name, scans, crop, interior, zone, zoom, **kw):
    e = render.build(map_id, scans, crop, footprint=None, **kw)
    e.update({"id": map_id, "name": name, "interior": interior, "zoom": zoom,
              "zones": [{"min": zone[0], "max": zone[1]}]})
    specs.append(e)

# standard office: only the room with the exit + PC (the hall next to it is not part of the office)
add("biz_office_standard", "Office (standard)", ["biz_os"], (335, 158, 346, 169.5), 3,
    ([335.5, 159.0, 1018.0], [345.5, 169.0, 1022.5]), 3,
    cut=[(320, 168.4, 362, 186), (344.4, 148, 362, 186), (320, 148, 336.8, 186)], min_cells=300)
add("biz_office_exclusive", "Office (exclusive)", ["biz_ox"], (-2176, 633, -2154, 656), 1,
    ([-2175.5, 633.5, 1050.5], [-2154.5, 655.5, 1056.5]), 2.5, min_cells=100)
add("biz_weed_farm", "Weed farm", ["biz_wf"], (1244, -54, 1314, 10), 18,
    ([1247, -52, 999.0], [1312, 9, 1010.0]), 1, min_cells=300)
add("biz_casino", "Casino", ["biz_ca", "biz_ca2"], (1112, -20, 1148, 15), 12,
    ([1113, -19, 998.7], [1147, 14, 1006.0]), 1.5, colors=[0, 1], min_cells=300)

path = os.path.join(OUT, "index.json")
idx = json.load(open(path, encoding="utf-8"))
maps = [m for m in idx["maps"] if not m["id"].startswith("biz_")]
for m in specs:
    for k in ("x", "y", "width", "height"):
        m[k] = round(m[k], 2)
maps += specs
lines = ["{", '  "_comment": %s,' % json.dumps(idx["_comment"]), '  "maps": [']
for i, m in enumerate(maps):
    lines.append("    {")
    keys = ["id", "name", "image", "x", "y", "width", "height", "interior", "zoom", "dimension"]
    body = ['      "%s": %s' % (k, json.dumps(m[k])) for k in keys if k in m]
    zl = ",\n".join("        " + json.dumps(z) for z in m["zones"])
    body.append('      "zones": [\n' + zl + '\n      ]')
    lines.append(",\n".join(body))
    lines.append("    }" + ("," if i < len(maps) - 1 else ""))
lines += ["  ]", "}", ""]
open(path, "w", encoding="utf-8", newline="\n").write("\n".join(lines))
print("index written", [m["id"] for m in maps])
