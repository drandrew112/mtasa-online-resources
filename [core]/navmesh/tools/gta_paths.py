# Reader for GTA:SA data/Paths/NODES0..63.DAT (vehicle, boat and ped path nodes, navi nodes, links).
# Format: https://gtamods.com/wiki/Paths_(GTA_SA)  (checked against the decoded newtraffic data: same
# 30587 car / 37650 ped nodes, the navi lane counts match ai_land_traffic's geometric matching).
#
# load(gta_dir) -> dict(veh={gid: node}, ped={gid: node}, navi=[...])
#   gid = area * 4095 + index  (same ids as ai_land_traffic / surface_scan.json; v_radar GPS id = area * 65536 + index)
#   node: x, y, z, width (m), flood (GTA flood-fill area), flags (raw), links=[(gid, length, crossFlags, naviIndex)]
#   veh links carry the navi record: lanes toward / away from it (see lanes_of)
import struct, os

def gid(area, index): return area * 4095 + index
def gps_id(g): return (g // 4095) * 65536 + g % 4095

# node flag bits (raw uint32)
F_TRAFFIC = 0x30      # traffic level (2 bits)
F_ROADBLOCK = 1 << 6
F_BOATS = 1 << 7
F_EMERGENCY = 1 << 8
F_NOT_HIGHWAY = 1 << 12
F_HIGHWAY = 1 << 13
F_PARKING = 1 << 21

# link intersection flags
X_ROADCROSS = 1
X_PEDLIGHT = 2

def load(gta_dir):
    base = os.path.join(gta_dir, 'data', 'Paths')
    areas = {}
    for a in range(64):
        b = open(os.path.join(base, f'NODES{a}.DAT'), 'rb').read()
        nn, nv, npd, nnav, nl = struct.unpack_from('<5I', b, 0)
        o = 20
        nodes = []
        for i in range(nn):
            _, _, x, y, z, _h, lid, ar, nid, w, typ, fl = struct.unpack_from('<IIhhhhHHHBBI', b, o); o += 28
            nodes.append((x / 8, y / 8, z / 8, lid, w / 8, typ, fl))
        navi = []
        for i in range(nnav):
            x, y, ar, nid, dx, dy, fl = struct.unpack_from('<hhHHbbI', b, o); o += 14
            navi.append(dict(x=x / 8, y=y / 8, target=gid(ar, nid), dx=dx / 100, dy=dy / 100,
                             width=(fl & 0xFF) / 8, left=(fl >> 8) & 7, right=(fl >> 11) & 7,
                             light=(fl >> 16) & 3, lightDir=(fl >> 14) & 1, trainCross=(fl >> 18) & 1))
        links = [struct.unpack_from('<HH', b, o + 4 * i) for i in range(nl)]; o += 4 * nl
        o += 768
        nlinks = [struct.unpack_from('<H', b, o + 2 * i)[0] for i in range(nl)]; o += 2 * nl
        lens = b[o:o + nl]; o += nl
        xfl = b[o:o + nl]; o += nl
        areas[a] = (nv, nodes, navi, links, nlinks, lens, xfl)

    navi_all = {}   # (area, index) -> record
    for a, (nv, nodes, navi, *_r) in areas.items():
        for i, n in enumerate(navi): navi_all[(a, i)] = n
    veh, ped = {}, {}
    for a, (nv, nodes, navi, links, nlinks, lens, xfl) in areas.items():
        for i, (x, y, z, lid, w, typ, fl) in enumerate(nodes):
            ls = []
            for k in range(fl & 15):
                la, ln = links[lid + k]
                nl = nlinks[lid + k]
                nav = navi_all.get((nl >> 10, nl & 1023)) if i < nv else None
                ls.append((gid(la, ln), lens[lid + k], xfl[lid + k], nav))
            rec = dict(x=x, y=y, z=z, width=w, flood=typ, flags=fl, links=ls)
            (veh if i < nv else ped)[gid(a, i)] = rec
    return dict(veh=veh, ped=ped)

def lanes_of(g_from, g_to, nav):
    """(lanes from->to, lanes to->from) from a link's navi record: its left lanes run toward navi.target."""
    if not nav: return None
    if nav['target'] == g_to: return nav['left'], nav['right']
    if nav['target'] == g_from: return nav['right'], nav['left']
    return None
