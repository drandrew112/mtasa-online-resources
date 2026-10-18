# navmesh road network builder:   python tools/build_roads.py ["C:/Games/GTA San Andreas"]
# Inputs: GTA data/Paths/NODES*.DAT (tools/gta_paths.py), data/source/surface_scan.json (claude-mcp probe surface
#         of every car node + link sample, taken over from ai_land_traffic, 2026-10-11)
# Output: data/runtime/roads.nav (lanes, connections, signals), data/runtime/boats.nav, data/build/roads_report.json
#
# The lane geometry (lane offsets, junction trims, Bezier turn curves, lane mapping, signal groups) is the
# ai_land_traffic builder (tools/build_network.py there), with these changes:
#  - lane counts come from each link's own navi reference in NODES*.DAT (no geometric navi matching)
#  - every carriageway gets a class: highway / ramp / road / service, ramps are detected at the highway
#    junctions; a two-way chain that joins a dual carriageway at a ramp angle is forced one-way (validated)
#  - boat paths go into their own network (boats.nav)
#  - connections get a curve speed, lanes their left / right neighbours, the lane graph its main component
import json, math, collections, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gta_paths as GP

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GTA = sys.argv[1] if len(sys.argv) > 1 else 'C:/Games/GTA San Andreas'
RUNTIME = os.path.join(ROOT, 'data', 'runtime')
BUILD = os.path.join(ROOT, 'data', 'build')
LW = 5.0            # lane width (m), checked live for ai_land_traffic (freeway + LS junction)
A_LAT = 3.0         # comfortable lateral acceleration for curve speeds (m/s^2)

paths = GP.load(GTA)
surf = json.load(open(os.path.join(ROOT, 'data', 'source', 'surface_scan.json')))['res']

def r2(x): return round(x, 2)

# ---------------------------------------------------------------- nodes / links
ALL = paths['veh']
V = {g: n for g, n in ALL.items() if not n['flags'] & GP.F_BOATS}
B = {g: n for g, n in ALL.items() if n['flags'] & GP.F_BOATS}
for n in V.values(): n['nbs'] = [l[0] for l in n['links'] if l[0] in V]

def flagset(g):
    f = V[g]['flags']; s = set()
    if f & GP.F_HIGHWAY: s.add('highway')
    if f & GP.F_EMERGENCY: s.add('emergency')
    if f & GP.F_PARKING: s.add('parking')
    if f & GP.F_ROADBLOCK: s.add('roadblock')
    return s

links = {}
missing_navi = 0
for a, v in V.items():
    for (b, _len, _x, nav) in v['links']:
        if b not in V or a >= b: continue
        A_, B_ = V[a], V[b]
        lk = dict(a=a, b=b, len=math.hypot(B_['x'] - A_['x'], B_['y'] - A_['y']))
        ln = GP.lanes_of(a, b, nav)
        if ln is None:
            # the link record of the other end may carry it
            for (c, _l2, _x2, nav2) in V[b]['links']:
                if c == a: ln = GP.lanes_of(a, b, nav2); nav = nav2
        if ln is not None and ln[0] + ln[1] > 0:
            lk['ab'], lk['ba'] = ln
            lk['median'] = nav['width']
            lk['tl'] = nav['light']
        else:
            missing_navi += 1
        links[(a, b)] = lk

def nb_links(node, exclude):
    for c in V[node]['nbs']:
        k = (min(node, c), max(node, c))
        if k != exclude and k in links: yield k

# links without lane data inherit from the neighbouring chain link (ai_land_traffic rule, kept: 24 links)
inherited = 0
for _ in range(5):
    for k, lk in links.items():
        if 'ab' in lk: continue
        cand = None
        for end in (lk['a'], lk['b']):
            if len(V[end]['nbs']) != 2: continue
            for k2 in nb_links(end, k):
                o = links[k2]
                if 'ab' not in o: continue
                same = (o['a'] == end) == (end == lk['b'])
                cand = (o['ab'], o['ba'], o.get('median', 0)) if same else (o['ba'], o['ab'], o.get('median', 0))
        if cand:
            lk['ab'], lk['ba'], lk['median'] = cand; lk['tl'] = 0; lk['inherited'] = True; inherited += 1
for lk in links.values():
    if 'ab' not in lk:
        lk['ab'], lk['ba'], lk['median'], lk['tl'] = 1, 1, 0.0, 0; lk['inherited'] = True; inherited += 1

# ---------------------------------------------------------------- surface (ai_land_traffic rule)
UNPAVED = {'dirt', 'sand', 'grass', 'rock', 'water'}
PAVED = {'road', 'sidewalk', 'concrete', 'default', 'structure'}
def sclass(s):
    if not s: return None
    if s[3] in UNPAVED: return 'u'
    if s[3] in PAVED: return 'p'
    return None
for k, lk in links.items():
    a, b = k; cnt = collections.Counter(); i = 1
    while f"l{a}_{b}_{i}" in surf:
        c = sclass(surf[f"l{a}_{b}_{i}"])
        if c: cnt[c] += 2
        i += 1
    for n in (a, b):
        c = sclass(surf.get(f"n{n}"))
        if c: cnt[c] += 1
    lk['score'] = cnt['u'] - cnt['p']
smoothed = {}
for k, lk in links.items():
    tot = lk['score'] * 2
    for end in k:
        if len(V[end]['nbs']) == 2:
            for k2 in nb_links(end, k):
                tot += links[k2]['score']
                e2 = k2[0] if k2[1] == end else k2[1]
                if len(V[e2]['nbs']) == 2:
                    for k3 in nb_links(e2, k2): tot += links[k3]['score'] * 0.5
    smoothed[k] = tot
for k, lk in links.items(): lk['dirt'] = smoothed[k] > 0

kept = links
adj = collections.defaultdict(list)
for k in kept: adj[k[0]].append(k); adj[k[1]].append(k)
used_nodes = set(adj)

def is_highway_link(lk): return 'highway' in flagset(lk['a']) and 'highway' in flagset(lk['b'])
def unit(ax, ay, bx, by):
    dx, dy = bx - ax, by - ay; L = math.hypot(dx, dy) or 1
    return dx / L, dy / L
def node_z(n):
    s = surf.get(f"n{n}"); z = V[n]['z']
    if s and abs(s[1] - z) < 2.5: return s[1]
    return z
def dlink_lanes(k, fwd): return kept[k]['ab'] if fwd else kept[k]['ba']
def dlink_other(k, fwd): return kept[k]['ba'] if fwd else kept[k]['ab']
def dlink_nodes(k, fwd): return (k[0], k[1]) if fwd else (k[1], k[0])
def ddir(k, fwd):
    f, t = dlink_nodes(k, fwd)
    return unit(V[f]['x'], V[f]['y'], V[t]['x'], V[t]['y'])
def other_end(k, n): return k[1] if k[0] == n else k[0]

# ---------------------------------------------------------------- chains + classes (highway / ramp / road / service)
chain_of = {}
chains = []
for k in kept:
    if k in chain_of: continue
    seq = [k]; cid = len(chains)
    chain_of[k] = cid
    ends = []
    for start in k:
        cur, node = k, start
        while len(adj[node]) == 2:
            nk = adj[node][0] if adj[node][1] == cur else adj[node][1]
            if nk in chain_of: break
            chain_of[nk] = cid; seq.append(nk)
            cur, node = nk, other_end(nk, node)
        ends.append(node)
    chains.append(dict(links=seq, ends=ends))
for c in chains:
    c['highway'] = all(is_highway_link(kept[k]) for k in c['links'])
    c['oneway'] = all(kept[k]['ab'] == 0 or kept[k]['ba'] == 0 for k in c['links'])
    c['len'] = sum(kept[k]['len'] for k in c['links'])
    c['lanes'] = max(max(kept[k]['ab'], kept[k]['ba']) for k in c['links'])
    c['class'] = 'highway' if c['highway'] else 'road'

# Mixed chains: a chain (between junctions) that is one-way for most of its length but has a few two-way links.
# The two-way links are GTA data errors (Angel Pine: the ramp from the highway junction at -2100,-2680 is one-way
# for 15 of its 17 links): the extra opposite lane starts from nowhere and sends traffic the wrong way up the
# ramp. When the one-way links agree on the direction and cover >= MIXED_MIN of the length, the whole chain
# becomes one-way. Otherwise it is only reported.
MIXED_MIN = 0.75
mixed_fixed, mixed_kept = [], []
def chain_walk_from(c):
    """chain links in order from c['ends'][0]: [(link, a->b runs along the walk)]"""
    node = c['ends'][0]
    first = [k for k in c['links'] if node in k]
    if not first: return []
    res = []; seen = set(); cur_node = node; cur_k = first[0]
    while cur_k and cur_k not in seen and cur_k in chain_set[id(c)]:
        seen.add(cur_k); res.append((cur_k, cur_k[0] == cur_node))
        cur_node = other_end(cur_k, cur_node)
        nxt = [x for x in adj[cur_node] if x != cur_k and x in chain_set[id(c)]]
        cur_k = nxt[0] if nxt else None
    return res
chain_set = {id(c): set(c['links']) for c in chains}
for c in chains:
    ow = [k for k in c['links'] if kept[k]['ab'] == 0 or kept[k]['ba'] == 0]
    if not ow or len(ow) == len(c['links']): continue
    walk = chain_walk_from(c)
    fwd_len = back_len = ow_len = 0.0
    for k, along in walk:
        lk = kept[k]
        if lk['ab'] > 0 and lk['ba'] > 0: continue
        ow_len += lk['len']
        if (lk['ab'] > 0) == along: fwd_len += lk['len']
        else: back_len += lk['len']
    n0 = V[c['ends'][0]]
    rec = dict(x=r2(n0['x']), y=r2(n0['y']), links=len(c['links']), oneway=len(ow), km=round(c['len'] / 1000, 2))
    if len(walk) == len(c['links']) and ow_len >= MIXED_MIN * c['len'] and min(fwd_len, back_len) == 0:
        for k, along in walk:
            lk = kept[k]
            if lk['ab'] > 0 and lk['ba'] > 0:
                n = max(lk['ab'], lk['ba'])
                if (fwd_len > 0) == along: lk['ab'], lk['ba'] = n, 0
                else: lk['ab'], lk['ba'] = 0, n
                lk['forced_oneway'] = True
        c['oneway'] = True
        mixed_fixed.append(rec)
    else:
        mixed_kept.append(rec)

def out_dir(node, k):   # direction leaving node along k (geometry only)
    return ddir(k, k[0] == node)

def chain_walk(node, k):
    """links of k's chain walked from junction `node`: [(link, a->b travels away from node)]"""
    res = []; seen = set(); cur_node = node; cur_k = k
    while cur_k and cur_k not in seen:
        seen.add(cur_k)
        res.append((cur_k, cur_k[0] == cur_node))
        cur_node = other_end(cur_k, cur_node)
        if len(adj[cur_node]) != 2: break
        nxt = [x for x in adj[cur_node] if x != cur_k]
        cur_k = nxt[0] if nxt else None
    return res

ramp_forced = []
for node in used_nodes:
    if len(adj[node]) < 3: continue
    hw = [k for k in adj[node] if is_highway_link(kept[k])]
    if len(hw) < 2: continue
    ins = [k for k in hw if dlink_lanes(k, k[1] == node) > 0 and dlink_lanes(k, k[0] == node) == 0]
    outs = [k for k in hw if dlink_lanes(k, k[0] == node) > 0 and dlink_lanes(k, k[1] == node) == 0]
    # mainline = straightest highway in -> out pair (most lanes on a tie)
    best = None
    for ki in ins:
        di = ddir(ki, ki[1] == node)
        for ko in outs:
            do = out_dir(node, ko)
            sc = di[0] * do[0] + di[1] * do[1] + 0.05 * min(dlink_lanes(ki, ki[1] == node), dlink_lanes(ko, ko[0] == node))
            if best is None or sc > best[0]: best = (sc, ki, ko)
    main = {best[1], best[2]} if best and best[0] > 0.5 else set()
    if not main: continue
    din = ddir(best[1], best[1][1] == node); dout = out_dir(node, best[2])
    for k in adj[node]:
        if k in main: continue
        c = chains[chain_of[k]]
        d = out_dir(node, k)
        if c['oneway']:
            c['class'] = 'ramp'
            continue
        # A ramp is one-way. A two-way (or partly two-way) chain at a dual-carriageway junction lost its direction
        # in the GTA data (e.g. LV north interchange: half of the loop 2+0 lanes, half 1+1). Force it one-way:
        # the direction of its one-way links when it has any, else the ramp shape (shallow angle to the mainline:
        # diverge = leaves the junction, merge = enters it).
        walk = chain_walk(node, k)
        vote = 0.0
        for kk, away in walk:
            lk = kept[kk]
            if lk['ab'] > 0 and lk['ba'] > 0: continue
            travels_away = (lk['ab'] > 0) == away
            vote += lk['len'] if travels_away else -lk['len']
        div = d[0] * dout[0] + d[1] * dout[1]
        mer = -(d[0] * din[0] + d[1] * din[1])
        if vote != 0:
            leaving = vote > 0; why = 'oneway part'
        else:
            if max(div, mer) < 0.8 or c['len'] > 1500: continue
            leaving = div >= mer; why = 'ramp angle'
        for kk, away in walk:
            lk = kept[kk]
            n = max(lk['ab'], lk['ba'])
            if lk['ab'] > 0 and lk['ba'] > 0 and lk['median'] == 0: n = max(n, 1)
            # away = a->b travels away from the junction
            if away == leaving: lk['ab'], lk['ba'] = n, 0
            else: lk['ab'], lk['ba'] = 0, n
            lk['forced_oneway'] = True
        c['oneway'] = True; c['class'] = 'ramp'
        ramp_forced.append(dict(junction=node, x=r2(V[node]['x']), y=r2(V[node]['y']), links=len(walk),
                                dir='off' if leaving else 'on', reason=why, km=round(c['len'] / 1000, 2)))

for k, lk in kept.items():
    c = chains[chain_of[k]]
    lk['class'] = c['class']
    if 'parking' in flagset(k[0]) or 'parking' in flagset(k[1]):
        if len(adj[k[0]]) == 1 or len(adj[k[1]]) == 1: lk['class'] = 'service'

# ---------------------------------------------------------------- lane geometry (ai_land_traffic)
def lane_offset(k, fwd, i):
    lk = kept[k]; n = dlink_lanes(k, fwd); m = dlink_other(k, fwd)
    if m > 0: return lk['median'] / 2 + LW * (i + 0.5)
    return LW * (i + 0.5 - n / 2)
def half_width(k):
    lk = kept[k]
    if lk['ab'] > 0 and lk['ba'] > 0: return lk['median'] / 2 + LW * max(lk['ab'], lk['ba'])
    return LW * max(lk['ab'], lk['ba']) / 2
def trim_at(node, k):
    deg = len(adj[node])
    if deg == 2: return 0.0
    if deg == 1: return min(2.0, kept[k]['len'] * 0.3)
    d0 = ddir(k, k[0] == node); t = 0.0
    for k2 in adj[node]:
        if k2 == k: continue
        d1 = ddir(k2, k2[0] == node)
        s = abs(d0[0] * d1[1] - d0[1] * d1[0]); c = d0[0] * d1[0] + d0[1] * d1[1]
        hw = half_width(k2)
        t = max(t, hw * 0.5) if c > 0.8 else max(t, hw / max(s, 0.5) + 1.0)
    return min(t, kept[k]['len'] * 0.45, 25.0)
def lane_point(node, k, fwd, i, at_end):
    dx, dy = ddir(k, fwd); rx, ry = dy, -dx
    off = lane_offset(k, fwd, i); tr = trim_at(node, k)
    px, py = V[node]['x'], V[node]['y']
    if len(adj[node]) == 2:
        k2 = adj[node][0] if adj[node][1] == k else adj[node][1]
        d2 = ddir(k2, k2[0] == node) if at_end else ddir(k2, k2[1] == node)
        mx, my = rx + d2[1], ry - d2[0]; ml = math.hypot(mx, my)
        if ml > 0.2:
            mx, my = mx / ml, my / ml
            scale = 1 / max(mx * rx + my * ry, 0.6)
            return [px + mx * off * scale, py + my * off * scale]
    sgn = -1 if at_end else 1
    return [px + rx * off + dx * tr * sgn, py + ry * off + dy * tr * sgn]

lanes = []; lane_index = {}; link_ids = {}
for li, k in enumerate(sorted(kept)): link_ids[k] = li + 1
for k in sorted(kept):
    for fwd in (True, False):
        n = dlink_lanes(k, fwd); f, t = dlink_nodes(k, fwd)
        for i in range(n):
            p0 = lane_point(f, k, fwd, i, False); p1 = lane_point(t, k, fwd, i, True)
            lid = len(lanes) + 1
            lane_index[(k, fwd, i)] = lid
            L = math.hypot(p1[0] - p0[0], p1[1] - p0[1])
            lanes.append(dict(id=lid, k=k, link=link_ids[k], fwd=fwd, from_=f, to=t, index=i, count=n,
                              p=[[r2(p0[0]), r2(p0[1]), r2(node_z(f))], [r2(p1[0]), r2(p1[1]), r2(node_z(t))]],
                              length=math.hypot(L, node_z(t) - node_z(f)), next=[], prev=[]))

# ---------------------------------------------------------------- signals (ai_land_traffic)
signal = {}
def chain_to_junction(k, node, limit=45.0):
    dist = 0.0; cur_k = k; cur = node
    while True:
        if len(adj[cur]) >= 3: return cur, cur_k, dist
        if len(adj[cur]) != 2: return None
        nk = adj[cur][0] if adj[cur][1] == cur_k else adj[cur][1]
        dist += kept[nk]['len']
        if dist > limit: return None
        cur = other_end(nk, cur); cur_k = nk
for k, lk in kept.items():
    if not lk.get('tl'): continue
    best = None
    for end in k:
        r = chain_to_junction(k, end)
        if r and (best is None or r[2] < best[2]): best = r
    if not best: continue
    j, lastk, _ = best
    fwd = lastk[1] == j
    if dlink_lanes(lastk, fwd) > 0: signal[(lastk, fwd)] = lk['tl']

# ---------------------------------------------------------------- connections (ai_land_traffic)
conns = []
def signed_turn(din, dout):
    return math.degrees(math.atan2(din[0] * dout[1] - din[1] * dout[0], din[0] * dout[0] + din[1] * dout[1]))
def bezier(p0, d0, p3, d3):
    k = math.hypot(p3[0] - p0[0], p3[1] - p0[1]) / 3
    return [p0, [p0[0] + d0[0] * k, p0[1] + d0[1] * k], [p3[0] - d3[0] * k, p3[1] - d3[1] * k], p3]
def bez_pt(c, t):
    u = 1 - t
    return [u ** 3 * c[0][j] + 3 * u * u * t * c[1][j] + 3 * u * t * t * c[2][j] + t ** 3 * c[3][j] for j in range(3)]
def bez_len(c):
    l = 0; prev = c[0]
    for s in range(1, 9):
        p = bez_pt(c, s / 8); l += math.dist(prev, p); prev = p
    return l
def bez_radius(c):
    """smallest turn radius along the curve (from heading change per metre)"""
    pts = [bez_pt(c, s / 12) for s in range(13)]
    rmin = 1e9
    for i in range(1, 12):
        a = (pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]); b = (pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1])
        la, lb = math.hypot(*a), math.hypot(*b)
        if la < 1e-3 or lb < 1e-3: continue
        ang = abs(math.atan2(a[0] * b[1] - a[1] * b[0], a[0] * b[0] + a[1] * b[1]))
        if ang > 1e-4: rmin = min(rmin, (la + lb) / 2 / ang)
    return rmin
def prop_map(n, m):
    res = {}
    for i in range(n):
        a0, a1 = i / n, (i + 1) / n
        res[i] = [j for j in range(m) if min(a1, (j + 1) / m) - max(a0, j / m) > 1e-6]
    return res
def add_conn(kin, fin, i, kout, fout, j, node, turn):
    lin = lane_index[(kin, fin, i)]; lout = lane_index[(kout, fout, j)]
    A = lanes[lin - 1]; Bl = lanes[lout - 1]
    p0 = A['p'][-1]; p3 = Bl['p'][0]
    c = bezier(p0, ddir(kin, fin), p3, ddir(kout, fout))
    c = [[r2(p[0]), r2(p[1]), r2(p[2] if len(p) > 2 else p0[2] + (p3[2] - p0[2]) * (q / 3))] for q, p in enumerate(c)]
    L = math.dist(p0, p3)
    e = dict(id=len(conns) + 1, from_=lin, to=lout, node=node, turn=turn, length=bez_len(c) if L > 0.05 else 0.0)
    if L > 0.05:
        e['curve'] = c
        R = bez_radius(c)
        if R < 300: e['vmax'] = max(4.0, math.sqrt(A_LAT * R))
    ph = signal.get((kin, fin))
    if ph and len(adj[node]) >= 3: e['signal'] = ph
    conns.append(e); A['next'].append(e['id']); Bl['prev'].append(e['id'])

stats = collections.Counter()
for node in used_nodes:
    deg = len(adj[node])
    for kin in adj[node]:
        fin = kin[1] == node
        n = dlink_lanes(kin, fin)
        if n == 0: continue
        din = ddir(kin, fin); outs = []
        for kout in adj[node]:
            if kout == kin: continue
            fout = kout[0] == node; m = dlink_lanes(kout, fout)
            if m == 0: continue
            outs.append((kout, fout, m, signed_turn(din, ddir(kout, fout))))
        if not outs:
            m = dlink_lanes(kin, not fin)
            if m > 0:
                for i in range(n): add_conn(kin, fin, i, kin, not fin, 0, node, 'uturn')
                stats['uturn'] += 1
            else: stats['deadend_no_exit'] += 1
            continue
        if len(outs) == 1 or deg == 2:
            for kout, fout, m, ang in outs:
                turn = 'straight' if abs(ang) < 35 else ('left' if ang > 0 else 'right')
                for i, js in prop_map(n, m).items():
                    for j in js: add_conn(kin, fin, i, kout, fout, j, node, turn)
            continue
        classed = []
        for kout, fout, m, ang in outs:
            turn = 'straight' if abs(ang) < 35 else ('uturn' if abs(ang) > 160 else ('left' if ang > 0 else 'right'))
            classed.append((kout, fout, m, ang, turn))
        for kout, fout, m, ang, turn in classed:
            if turn == 'uturn': continue
            if turn == 'straight' or n == 1:
                for i, js in prop_map(n, m).items():
                    for j in js: add_conn(kin, fin, i, kout, fout, j, node, turn)
            elif turn == 'left':
                use = [0] if n < 4 else [0, 1]
                for q, i in enumerate(use): add_conn(kin, fin, i, kout, fout, min(q, m - 1), node, turn)
            else:
                use = [n - 1] if n < 4 else [n - 2, n - 1]
                for q, i in enumerate(use): add_conn(kin, fin, i, kout, fout, max(m - len(use) + q, 0), node, turn)
        for i in range(n):
            lid = lane_index[(kin, fin, i)]
            if not lanes[lid - 1]['next']:
                kout, fout, m, ang, turn = min((c for c in classed if c[4] != 'uturn'), key=lambda c: abs(c[3]), default=classed[0])
                add_conn(kin, fin, i, kout, fout, min(round(i * m / n), m - 1), node, turn)
                stats['orphan_fix'] += 1

# ---------------------------------------------------------------- main component (lanes that can reach and be reached)
succ = {l['id']: [conns[c - 1]['to'] for c in l['next']] for l in lanes}
pred = collections.defaultdict(list)
for a, bs in succ.items():
    for b in bs: pred[b].append(a)
def reach(start, g):
    seen = {start}; st = [start]
    while st:
        x = st.pop()
        for y in g[x]:
            if y not in seen: seen.add(y); st.append(y)
    return seen
# seed: the longest highway lane
seed = max((l for l in lanes if kept[l['k']]['class'] == 'highway'), key=lambda l: l['length'])['id']
to_main = reach(seed, pred)      # lanes that can still reach the main network
from_main = reach(seed, succ)    # lanes the main network can reach
for l in lanes:
    if l['id'] not in to_main: l['trap'] = True          # never gets back (garage loops, stadium tracks, sinks)
    if l['id'] not in from_main: l['source'] = True      # only reachable from where it starts

# ---------------------------------------------------------------- signal groups (ai_land_traffic)
def node_signalled(n): return len(adj[n]) >= 3 and any(signal.get((k, k[1] == n)) for k in adj[n])
sig_nodes = sorted(n for n in used_nodes if node_signalled(n))
group_of = {}; groups = []
for s0 in sig_nodes:
    if s0 in group_of: continue
    gid = len(groups) + 1; members = []; stack = [(s0, 0.0)]; seen = {s0: 0.0}
    while stack:
        cur, d = stack.pop()
        if node_signalled(cur) and cur not in group_of:
            group_of[cur] = gid; members.append(cur); d = 0.0
        for k in adj[cur]:
            o = other_end(k, cur); nd = d + kept[k]['len']
            if nd <= 35 and (o not in seen or seen[o] > nd): seen[o] = nd; stack.append((o, nd))
    cx = sum(V[m]['x'] for m in members) / len(members); cy = sum(V[m]['y'] for m in members) / len(members)
    cz = sum(node_z(m) for m in members) / len(members)
    phases = sorted({c['signal'] for c in conns if c.get('signal') and c['node'] in members})
    groups.append(dict(id=gid, nodes=members, c=[r2(cx), r2(cy), r2(cz)], phases=phases))

# ---------------------------------------------------------------- output
CLASS = dict(highway=1, ramp=2, road=3, service=4)
# link flags
KF_UNPAVED, KF_EMERGENCY, KF_ROADBLOCK, KF_ESTIMATED, KF_FORCED = 1, 2, 4, 8, 16
# node flags
NF_JUNCTION, NF_DEADEND, NF_PARKING, NF_SIGNAL, NF_HIGHWAY, NF_EMERGENCY = 1, 2, 4, 8, 16, 32
# lane flags
LF_TRAP, LF_PARKING, LF_SOURCE = 1, 2, 4
TURN = dict(straight='S', left='L', right='R', uturn='U')

node_ids = {}
for i, n in enumerate(sorted(used_nodes)): node_ids[n] = i + 1
os.makedirs(RUNTIME, exist_ok=True); os.makedirs(BUILD, exist_ok=True)
out = ["# navmesh roads v1 - GENERATED by tools/build_roads.py from GTA NODES*.DAT + data/source/surface_scan.json",
       "# N id x y z gpsId flags          (flags: 1 junction 2 deadend 4 parking 8 signalled 16 highway 32 emergency-only)",
       "# K id a b class flags lanesAB lanesBA median length   (class: 1 highway 2 ramp 3 road 4 service; flags: 1 unpaved 2 emergency 4 roadblock 8 estimated 16 forced-oneway)",
       "# A id link from to index count left right flags x1 y1 z1 x2 y2 z2   (lane from->to; index 0 = innermost; left/right = neighbour lane or 0; flags: 1 trap = cannot reach the main network, 2 parking, 4 source = the main network cannot reach it)",
       "# C id fromLane toLane node turn signal vmax length [bx1 by1 bz1 bx2 by2 bz2]  (turn S/L/R/U, signal 0/1/2, vmax m/s 0 = none, Bezier inner control points)",
       "# S id x y z phases nodes   (signal group: comma lists)"]
for n in sorted(used_nodes):
    v = V[n]; deg = len(adj[n]); fl = 0
    if deg >= 3: fl |= NF_JUNCTION
    if deg == 1: fl |= NF_DEADEND
    fs = flagset(n)
    if 'parking' in fs and deg == 1: fl |= NF_PARKING
    if node_signalled(n): fl |= NF_SIGNAL
    if 'highway' in fs: fl |= NF_HIGHWAY
    if 'emergency' in fs: fl |= NF_EMERGENCY
    out.append(f"N {node_ids[n]} {r2(v['x'])} {r2(v['y'])} {r2(node_z(n))} {GP.gps_id(n)} {fl}")
for k in sorted(kept):
    lk = kept[k]; fl = 0
    fs = flagset(k[0]) & flagset(k[1])
    if lk['dirt']: fl |= KF_UNPAVED
    if 'emergency' in fs: fl |= KF_EMERGENCY
    if 'roadblock' in fs: fl |= KF_ROADBLOCK
    if lk.get('inherited'): fl |= KF_ESTIMATED
    if lk.get('forced_oneway'): fl |= KF_FORCED
    out.append(f"K {link_ids[k]} {node_ids[k[0]]} {node_ids[k[1]]} {CLASS[lk['class']]} {fl} {lk['ab']} {lk['ba']} {r2(lk['median'])} {r2(lk['len'])}")
for l in lanes:
    left = lane_index.get((l['k'], l['fwd'], l['index'] - 1), 0) if l['index'] > 0 else 0
    right = lane_index.get((l['k'], l['fwd'], l['index'] + 1), 0)
    fl = (LF_TRAP if l.get('trap') else 0) | (LF_SOURCE if l.get('source') else 0) | (LF_PARKING if not l['next'] and len(adj[l['to']]) == 1 and 'parking' in flagset(l['to']) else 0)
    p = l['p']
    out.append(f"A {l['id']} {l['link']} {node_ids[l['from_']]} {node_ids[l['to']]} {l['index']} {l['count']} {left} {right} {fl} "
               f"{p[0][0]} {p[0][1]} {p[0][2]} {p[1][0]} {p[1][1]} {p[1][2]}")
for c in conns:
    s = f"C {c['id']} {c['from_']} {c['to']} {node_ids[c['node']]} {TURN[c['turn']]} {c.get('signal', 0)} {r2(c.get('vmax', 0))} {r2(c['length'])}"
    if 'curve' in c:
        b1, b2 = c['curve'][1], c['curve'][2]
        s += f" {b1[0]} {b1[1]} {b1[2]} {b2[0]} {b2[1]} {b2[2]}"
    out.append(s)
for g in groups:
    out.append(f"S {g['id']} {g['c'][0]} {g['c'][1]} {g['c'][2]} {','.join(map(str, g['phases'])) or '-'} {','.join(str(node_ids[m]) for m in g['nodes'])}")
open(os.path.join(RUNTIME, 'roads.nav'), 'w', newline='\n').write('\n'.join(out) + '\n')

# ---------------------------------------------------------------- boats (GTA boat paths, plain graph)
bo = ["# navmesh boats v1 - GENERATED by tools/build_roads.py from the GTA boat path nodes",
      "# N id x y z width   /   E a b"]
bid = {g: i + 1 for i, g in enumerate(sorted(B))}
for g in sorted(B):
    n = B[g]; bo.append(f"N {bid[g]} {r2(n['x'])} {r2(n['y'])} {r2(n['z'])} {r2(n['width'])}")
be = set()
for g, n in B.items():
    for (o, *_r) in n['links']:
        if o in B and g < o: be.add((bid[g], bid[o]))
for a, b in sorted(be): bo.append(f"E {a} {b}")
open(os.path.join(RUNTIME, 'boats.nav'), 'w', newline='\n').write('\n'.join(bo) + '\n')

# ---------------------------------------------------------------- report
cls = collections.Counter(kept[k]['class'] for k in kept)
clen = collections.Counter()
for k in kept: clen[kept[k]['class']] += kept[k]['len']
two_way_ramps = [chains[i] for i in range(len(chains)) if chains[i]['class'] == 'ramp' and not chains[i]['oneway']]
report = dict(
    counts=dict(nodes=len(used_nodes), links=len(kept), lanes=len(lanes), connections=len(conns), signalGroups=len(groups),
                boatNodes=len(B), boatEdges=len(be), trapLanes=sum(1 for l in lanes if l.get('trap')), sourceLanes=sum(1 for l in lanes if l.get('source')),
                missingNavi=missing_navi, inherited=inherited),
    classes={c: dict(links=cls[c], km=round(clen[c] / 1000, 1)) for c in cls},
    rampChains=sum(1 for c in chains if c['class'] == 'ramp'),
    rampsTwoWay=len(two_way_ramps),
    rampsForcedOneway=ramp_forced,
    mixedChainsFixed=mixed_fixed,
    mixedChainsKept=mixed_kept,
    connections=dict(stats),
)
json.dump(report, open(os.path.join(BUILD, 'roads_report.json'), 'w'), indent=1)
print(json.dumps(report['counts']), report['classes'], 'ramps', report['rampChains'], 'forced', len(ramp_forced), 'mixed fixed', len(mixed_fixed), 'kept', len(mixed_kept), dict(stats))

