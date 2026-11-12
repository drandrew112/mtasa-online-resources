"""GTA San Andreas data/Paths/NODES*.DAT reader (vehicle path nodes + navi nodes / lanes).

Format (gtamods.com "Paths (GTA SA)"):
  header 5 x uint32: nodes, vehicleNodes, pedNodes, naviNodes, links
  path node 28 B: 0 u32 mem, 4 u32 zero, 8 i16 x, 10 i16 y, 12 i16 z (/8), 14 i16 heuristic,
                  16 u16 linkId, 18 u16 area, 20 u16 node, 22 u8 width, 23 u8 floodFill, 24 u32 flags
                  (flags bits 0-3 link count, bit 7 boats)
  navi node 14 B: i16 x, i16 y (/8), u16 area, u16 node, i8 dirX, i8 dirY (/100), u32 flags
                  (bits 0-7 width, 8-10 left lanes, 11-13 right lanes)
  links 4 B: u16 area, u16 node
  768 B filler
  navi links 2 B: bits 0-9 navi node, 10-15 area
  link lengths 1 B, intersection flags 1 B
"""
import os
import struct


def read_area(path):
    with open(path, "rb") as f:
        data = f.read()
    n_nodes, n_veh, n_ped, n_navi, n_links = struct.unpack_from("<5I", data, 0)
    off = 20
    nodes = []
    for i in range(n_nodes):
        (_, _, x, y, z, _, link_id, area, node, width, _, flags) = struct.unpack_from("<IIhhhhHHHBBI", data, off)
        nodes.append({
            "x": x / 8.0, "y": y / 8.0, "z": z / 8.0, "link": link_id, "area": area, "id": node,
            "width": width, "links": flags & 0xF, "boat": bool(flags & 0x80), "vehicle": i < n_veh,
        })
        off += 28
    navi = []
    for i in range(n_navi):
        x, y, area, node, dx, dy, flags = struct.unpack_from("<hhHHbbI", data, off)
        navi.append({
            "x": x / 8.0, "y": y / 8.0, "area": area, "node": node, "dx": dx / 100.0, "dy": dy / 100.0,
            "width": flags & 0xFF, "left": (flags >> 8) & 7, "right": (flags >> 11) & 7,
        })
        off += 14
    links = []
    for i in range(n_links):
        area, node = struct.unpack_from("<HH", data, off)
        links.append((area, node))
        off += 4
    off += 768
    navi_links = []
    for i in range(n_links):
        (v,) = struct.unpack_from("<H", data, off)
        navi_links.append((v >> 10, v & 0x3FF))
        off += 2
    return {"nodes": nodes, "vehicle": n_veh, "navi": navi, "links": links, "naviLinks": navi_links}


def read_all(folder):
    areas = {}
    for i in range(64):
        p = os.path.join(folder, f"NODES{i}.DAT")
        if os.path.exists(p):
            areas[i] = read_area(p)
    return areas


def road_segments(areas):
    """-> list of { a: (x,y,z), b: (x,y,z), navi: navi node dict, boat } one per vehicle link (each pair once)"""
    seen = set()
    out = []
    for area_id, a in areas.items():
        for idx in range(a["vehicle"]):
            n = a["nodes"][idx]
            for k in range(n["links"]):
                li = n["link"] + k
                tarea, tnode = a["links"][li]
                key = tuple(sorted(((area_id, idx), (tarea, tnode))))
                if key in seen:
                    continue
                t = areas.get(tarea)
                if not t or tnode >= t["vehicle"]:
                    continue
                seen.add(key)
                narea, nid = a["naviLinks"][li]
                na = areas.get(narea)
                navi = na["navi"][nid] if na and nid < len(na["navi"]) else None
                m = t["nodes"][tnode]
                out.append({"a": (n["x"], n["y"], n["z"]), "b": (m["x"], m["y"], m["z"]), "navi": navi,
                            "boat": n["boat"] or m["boat"]})
    return out


if __name__ == "__main__":
    import sys
    areas = read_all(sys.argv[1] if len(sys.argv) > 1 else r"C:\Games\GTA San Andreas\data\Paths")
    segs = road_segments(areas)
    print("areas", len(areas), "segments", len(segs), "boat", sum(s["boat"] for s in segs),
          "no navi", sum(s["navi"] is None for s in segs))
    from collections import Counter
    print("lanes L/R", Counter((s["navi"]["left"], s["navi"]["right"]) for s in segs if s["navi"]).most_common(10))
    print("width", Counter(s["navi"]["width"] for s in segs if s["navi"]).most_common(10))
    # sample near Pershing Square (1481, -1700) and Grove (2495, -1668)
    for px, py in ((1427, -1660), (2495, -1668)):
        near = sorted(segs, key=lambda s: (s["navi"]["x"] - px) ** 2 + (s["navi"]["y"] - py) ** 2 if s["navi"] else 1e18)[:4]
        for s in near:
            print(px, py, s["a"], s["b"], s["navi"])
