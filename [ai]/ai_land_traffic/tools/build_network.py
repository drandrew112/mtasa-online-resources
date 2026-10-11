# ai_land_traffic road network builder:  python tools/build_network.py
# Inputs: data/source/gta_paths.json  (tools/parse_nodes.py: newtraffic nodes.lua = GTA SA nodes.dat car paths + navi links)
#         data/source/surface_scan.json (claude-mcp probe get_ground of every node + link sample, 2026-10-11)
# Output: data/meta.json, nodes.json, links.json, lanes.json, connections.json, signals.json, validation.json
# Lane width 5 m was checked against the map with probe cross-sections and top-view overlays (freeway + LS junction).
import json, math, collections, sys, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'data')
raw = json.load(open(os.path.join(ROOT, 'data', 'source', 'gta_paths.json')))
surf = json.load(open(os.path.join(ROOT, 'data', 'source', 'surface_scan.json')))['res']
LW = 5.0            # lane width (m)
LW_HW = 5.0         # highway lane width (m)
CENTER_SHIFT = 0.0

V = {int(k): v for k, v in raw['veh'].items()}
NV = dict(enumerate(raw['navi']))   # navi records are matched to links by geometry, not by id
V = {k: v for k, v in V.items() if v['type'] != 2}   # type 2 = boat paths
for v in V.values():
    v['nbs'] = [int(b) for b in v['nbs'] if int(b) in V]

def r2(x): return round(x, 2)
def gps_id(i): return (i // 4095) * 65536 + i % 4095

# ---------------------------------------------------------------- surface
UNPAVED = {'dirt', 'sand', 'grass', 'rock', 'water'}
PAVED = {'road', 'sidewalk', 'concrete', 'default', 'structure'}
def sclass(s):
    if not s: return None
    c = s[3]
    if c in UNPAVED: return 'u'
    if c in PAVED: return 'p'
    return None   # material_* procedural / vehicle / ped: unknown

# ---------------------------------------------------------------- links
links = {}   # (a,b) a<b -> dict
fixed_navi = 0
# navi links are matched to car links by geometry: navi.nb is one end node, the navi lies on the link
# and its direction vector points toward navi.nb. (The navinbs id lists break on area borders.)
geo_navi = {}
for nid, n in NV.items():
    t = V.get(n['nb'])
    if not t: continue
    best = None
    for o in t['nbs']:
        O = V[o]; L = math.hypot(t['x'] - O['x'], t['y'] - O['y']) or 1
        d = math.hypot(n['x'] - (t['x'] + O['x']) / 2, n['y'] - (t['y'] + O['y']) / 2)
        al = ((t['x'] - O['x']) * n['dx'] + (t['y'] - O['y']) * n['dy']) / L / 100
        sc = d / max(L, 1) - al
        if best is None or sc < best[0]: best = (sc, o, d)
    if best is None or best[0] > 0: continue   # navi must sit on the link and point toward navi.nb
    k = (min(n['nb'], best[1]), max(n['nb'], best[1]))
    if k not in geo_navi or best[2] < geo_navi[k][0]: geo_navi[k] = (best[2], nid)

for a, v in V.items():
    for b in v['nbs']:
        if a >= b: continue
        nid = geo_navi[(a, b)][1] if (a, b) in geo_navi else None
        if nid is None: fixed_navi += 1
        A, B = V[a], V[b]
        L = math.hypot(B['x'] - A['x'], B['y'] - A['y'])
        lk = dict(a=a, b=b, len=L, navi=nid)
        if nid is not None:
            n = NV[nid]
            toward, away = n['l'], n['r']   # left lanes run toward navi.nb, right lanes away from it
            if n['nb'] == b: lk['ab'], lk['ba'] = toward, away
            else: lk['ab'], lk['ba'] = away, toward
            lk['median'] = n['w'] / 8.0
            lk['tl'] = n['tl']
        links[(a, b)] = lk

# inherit lane data for links without a usable navi / with 0+0 lanes from the neighbouring chain link
def nb_links(node, exclude):
    for c in V[node]['nbs']:
        k = (min(node, c), max(node, c))
        if k != exclude: yield k
inherited = 0
for _ in range(5):
    for k, lk in links.items():
        if 'ab' in lk and (lk['ab'] + lk['ba']) > 0: continue
        cand = None
        for end in (lk['a'], lk['b']):
            if len(V[end]['nbs']) != 2: continue
            for k2 in nb_links(end, k):
                o = links[k2]
                if 'ab' not in o or o['ab'] + o['ba'] == 0: continue
                # orient o relative to lk: travel a->b on lk continues through `end`
                same = (o['a'] == end) == (end == lk['b'])
                cand = (o['ab'], o['ba'], o.get('median', 0), 0) if same else (o['ba'], o['ab'], o.get('median', 0), 0)
        if cand:
            lk['ab'], lk['ba'], lk['median'], lk['tl'] = cand; lk['inherited'] = True; inherited += 1
for lk in links.values():
    if 'ab' not in lk or lk['ab'] + lk['ba'] == 0:
        lk['ab'], lk['ba'], lk['median'], lk['tl'] = 1, 1, 0.0, 0; lk['inherited'] = True; inherited += 1

# surface per link (samples + end nodes), then smoothed over degree-2 chains
for k, lk in links.items():
    a, b = k
    cnt = collections.Counter()
    mats = collections.Counter()
    i = 1
    while f"l{a}_{b}_{i}" in surf:
        s = surf[f"l{a}_{b}_{i}"]; c = sclass(s)
        if c: cnt[c] += 2
        if s: mats[s[0]] += 1
        i += 1
    for n in (a, b):
        s = surf.get(f"n{n}"); c = sclass(s)
        if c: cnt[c] += 1
        if s: mats[s[0]] += 1
    lk['score'] = cnt['u'] - cnt['p']
    lk['mats'] = mats
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
for k, lk in links.items():
    lk['dirt'] = smoothed[k] > 0

# ---------------------------------------------------------------- road graph (paved only)
kept = dict(links)   # unpaved links are kept (removed manually later); link.surface is only a hint
adj = collections.defaultdict(list)
for k in kept: adj[k[0]].append(k); adj[k[1]].append(k)
used_nodes = set(adj)

def flagset(n): return set(V[n]['flags'])
def is_highway(lk): return 'highway' in flagset(lk['a']) and 'highway' in flagset(lk['b'])

def unit(ax, ay, bx, by):
    dx, dy = bx - ax, by - ay; L = math.hypot(dx, dy) or 1
    return dx / L, dy / L

def node_z(n):
    s = surf.get(f"n{n}")
    z = V[n]['z']
    if s and abs(s[1] - z) < 2.5: return s[1]
    return z

# directed link travel: (k, forward) forward = a->b
def dlink_lanes(k, fwd): return kept[k]['ab'] if fwd else kept[k]['ba']
def dlink_other(k, fwd): return kept[k]['ba'] if fwd else kept[k]['ab']
def dlink_nodes(k, fwd): return (k[0], k[1]) if fwd else (k[1], k[0])

def lane_width(k): return LW_HW if is_highway(kept[k]) else LW
def lane_offset(k, fwd, i):
    """Offset to the right of the travel direction for lane i (0 = innermost / leftmost)."""
    lk = kept[k]; n = dlink_lanes(k, fwd); m = dlink_other(k, fwd); w = lane_width(k)
    if m > 0: return lk['median'] / 2 + w * (i + 0.5) + CENTER_SHIFT
    return w * (i + 0.5 - n / 2)
def half_width(k):
    lk = kept[k]; w = lane_width(k)
    if lk['ab'] > 0 and lk['ba'] > 0: return lk['median'] / 2 + w * max(lk['ab'], lk['ba'])
    return w * max(lk['ab'], lk['ba']) / 2

# travel direction unit vector of a directed link
def ddir(k, fwd):
    f, t = dlink_nodes(k, fwd)
    return unit(V[f]['x'], V[f]['y'], V[t]['x'], V[t]['y'])

# trim at junctions / dead ends so turn curves have room
def trim_at(node, k):
    deg = len(adj[node])
    if deg == 2: return 0.0
    if deg == 1: return min(2.0, kept[k]['len'] * 0.3)
    far = node
    d0 = ddir(k, k[0] == node)          # direction leaving node along k
    t = 0.0
    for k2 in adj[node]:
        if k2 == k: continue
        d1 = ddir(k2, k2[0] == node)
        s = abs(d0[0] * d1[1] - d0[1] * d1[0])  # |sin angle|
        c = d0[0] * d1[0] + d0[1] * d1[1]
        hw = half_width(k2)
        if c > 0.8:   # shallow split / merge: little room needed
            t = max(t, hw * 0.5)
        else:
            t = max(t, hw / max(s, 0.5) + 1.0)
    return min(t, kept[k]['len'] * 0.45, 25.0)

# node-level offset normal for degree-2 nodes (miter between the two links)
def lane_point(node, k, fwd, i, at_end):
    lk = kept[k]
    f, t = dlink_nodes(k, fwd)
    dx, dy = ddir(k, fwd)
    rx, ry = dy, -dx
    off = lane_offset(k, fwd, i)
    tr = trim_at(node, k)
    px, py = V[node]['x'], V[node]['y']
    if len(adj[node]) == 2:
        k2 = adj[node][0] if adj[node][1] == k else adj[node][1]
        # direction of the continuing link with the same travel sense
        d2 = ddir(k2, k2[0] == node) if at_end else ddir(k2, k2[1] == node)
        mx, my = rx + d2[1], ry - d2[0]
        ml = math.hypot(mx, my)
        if ml > 0.2:
            mx, my = mx / ml, my / ml
            cosv = mx * rx + my * ry
            scale = 1 / max(cosv, 0.6)
            return [px + mx * off * scale, py + my * off * scale]
    sgn = -1 if at_end else 1
    return [px + rx * off + dx * tr * sgn, py + ry * off + dy * tr * sgn]

# ---------------------------------------------------------------- lanes
lanes = []
lane_index = {}    # (k, fwd, i) -> lane id
link_out = {}
link_ids = {}
for li, k in enumerate(sorted(kept)): link_ids[k] = li + 1
for k in sorted(kept):
    lk = kept[k]
    for fwd in (True, False):
        n = dlink_lanes(k, fwd)
        f, t = dlink_nodes(k, fwd)
        for i in range(n):
            p0 = lane_point(f, k, fwd, i, False)
            p1 = lane_point(t, k, fwd, i, True)
            lid = len(lanes) + 1
            lane_index[(k, fwd, i)] = lid
            L = math.hypot(p1[0] - p0[0], p1[1] - p0[1])
            lanes.append(dict(id=lid, link=link_ids[k], from_=f, to=t, index=i, count=n,
                              width=lane_width(k), offset=r2(lane_offset(k, fwd, i)),
                              points=[[r2(p0[0]), r2(p0[1]), r2(node_z(f))], [r2(p1[0]), r2(p1[1]), r2(node_z(t))]],
                              length=r2(math.hypot(L, node_z(t) - node_z(f))), next=[], prev=[]))

# ---------------------------------------------------------------- traffic light phases
# A navi traffic-light value marks the road arm of a signalled junction; the phase applies to the
# lanes that enter the nearest junction (degree >= 3) along this road arm.
signal = {}   # (k, fwd) -> phase
def chain_to_junction(k, node, limit=45.0):
    """walk from link k through `node` along degree-2 nodes until a junction; returns (junction, last link, dist)"""
    dist = 0.0; cur_k = k; cur = node
    while True:
        if len(adj[cur]) >= 3: return cur, cur_k, dist
        if len(adj[cur]) != 2: return None
        nk = adj[cur][0] if adj[cur][1] == cur_k else adj[cur][1]
        dist += kept[nk]['len']
        if dist > limit: return None
        cur = nk[0] if nk[1] == cur else nk[1]; cur_k = nk
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

# ---------------------------------------------------------------- connections
conns = []
def signed_turn(din, dout):
    cr = din[0] * dout[1] - din[1] * dout[0]
    dt = din[0] * dout[0] + din[1] * dout[1]
    return math.degrees(math.atan2(cr, dt))   # + = left (counter-clockwise), - = right

def bezier(p0, d0, p3, d3):
    L = math.hypot(p3[0] - p0[0], p3[1] - p0[1])
    k = L / 3
    return [p0, [p0[0] + d0[0] * k, p0[1] + d0[1] * k], [p3[0] - d3[0] * k, p3[1] - d3[1] * k], p3]

def bez_len(c):
    l = 0; prev = c[0]
    for s in range(1, 9):
        t = s / 8; u = 1 - t
        p = [u**3 * c[0][j] + 3 * u * u * t * c[1][j] + 3 * u * t * t * c[2][j] + t**3 * c[3][j] for j in range(3)]
        l += math.dist(prev, p); prev = p
    return l

def prop_map(n, m):
    """lane i of n -> lanes of m with overlapping normalised span"""
    res = {}
    for i in range(n):
        a0, a1 = i / n, (i + 1) / n
        res[i] = [j for j in range(m) if min(a1, (j + 1) / m) - max(a0, j / m) > 1e-6]
    return res

def add_conn(kin, fin, i, kout, fout, j, node, turn):
    lin = lane_index[(kin, fin, i)]; lout = lane_index[(kout, fout, j)]
    A = lanes[lin - 1]; B = lanes[lout - 1]
    p0 = A['points'][-1]; p3 = B['points'][0]
    din = ddir(kin, fin); dout = ddir(kout, fout)
    c = bezier(p0, din, p3, dout)
    c = [[r2(p[0]), r2(p[1]), r2(p[2] if len(p) > 2 else p0[2] + (p3[2] - p0[2]) * (q / 3))] for q, p in enumerate(c)]
    cid = len(conns) + 1
    L = math.dist(p0, p3)
    e = dict(id=cid, from_=lin, to=lout, node=node, turn=turn, length=r2(bez_len(c) if L > 0.05 else 0.0))
    if L > 0.05: e['curve'] = c
    ph = signal.get((kin, fin))
    if ph and len(adj[node]) >= 3: e['signal'] = ph
    conns.append(e)
    A['next'].append(cid); B['prev'].append(cid)

stats = collections.Counter()
for node in used_nodes:
    deg = len(adj[node])
    for kin in adj[node]:
        fin = kin[1] == node              # travelling toward node
        n = dlink_lanes(kin, fin)
        if n == 0: continue
        din = ddir(kin, fin)
        outs = []
        for kout in adj[node]:
            if kout == kin: continue
            fout = kout[0] == node
            m = dlink_lanes(kout, fout)
            if m == 0: continue
            ang = signed_turn(din, ddir(kout, fout))
            outs.append((kout, fout, m, ang))
        if not outs:
            # dead end / end of a one-way: U-turn into the opposite lanes of the same link if they exist
            m = dlink_lanes(kin, not fin)
            if m > 0:
                for i in range(n):
                    add_conn(kin, fin, i, kin, not fin, 0, node, 'uturn')
                stats['uturn'] += 1
            else:
                stats['deadend_no_exit'] += 1
            continue
        if len(outs) == 1 or deg == 2:
            for kout, fout, m, ang in outs:
                turn = 'straight' if abs(ang) < 35 else ('left' if ang > 0 else 'right')
                for i, js in prop_map(n, m).items():
                    for j in js: add_conn(kin, fin, i, kout, fout, j, node, turn)
            continue
        # junction with choices
        classed = []
        for kout, fout, m, ang in outs:
            if abs(ang) < 35: turn = 'straight'
            elif abs(ang) > 160: turn = 'uturn'
            else: turn = 'left' if ang > 0 else 'right'
            classed.append((kout, fout, m, ang, turn))
        # if there is no straight option, the shallowest turn behaves like straight for lane use
        has_straight = any(c[4] == 'straight' for c in classed)
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
        # every incoming lane must lead somewhere: give orphans the most straight-ahead exit
        for i in range(n):
            lid = lane_index[(kin, fin, i)]
            if not lanes[lid - 1]['next']:
                kout, fout, m, ang, turn = min((c for c in classed if c[4] != 'uturn'), key=lambda c: abs(c[3]), default=classed[0])
                add_conn(kin, fin, i, kout, fout, min(round(i * m / n), m - 1), node, turn)
                stats['orphan_fix'] += 1

# ---------------------------------------------------------------- validation
for l in lanes:
    if not l['next'] and 'parking' in V[l['to']]['flags'] and len(adj[l['to']]) == 1: l['parking'] = True
no_next = [l['id'] for l in lanes if not l['next'] and not l.get('parking')]
no_prev = [l['id'] for l in lanes if not l['prev']]
validation = dict(
    note='Lanes with no successor (sink) or no predecessor (source). These come from the GTA path data '
         '(one-way stubs, a two-way link meeting a one-way). '
         'Parking stubs (lane.parking = true) are not listed as sinks.',
    sinks=[dict(lane=i, node=lanes[i - 1]['to']) for i in no_next],
    sources=[dict(lane=i, node=lanes[i - 1]['from_']) for i in no_prev])

# ---------------------------------------------------------------- output
def speed_class(lk):
    if is_highway(lk): return 'highway'
    return 'road'
nodes_out = {}
for n in sorted(used_nodes):
    v = V[n]
    deg = len(adj[n])
    e = dict(x=r2(v['x']), y=r2(v['y']), z=r2(node_z(n)), gps=gps_id(n),
             type='junction' if deg >= 3 else ('parking' if deg == 1 and 'parking' in v['flags'] else ('deadend' if deg == 1 else 'road')),
             links=[link_ids[k] for k in adj[n]])
    fl = [f for f in v['flags']]
    if fl: e['flags'] = fl
    if any(signal.get((k, k[1] == n)) for k in adj[n]) and deg >= 3: e['signalled'] = True
    nodes_out[str(n)] = e
# signal groups: signalled junction nodes joined by short links (<= 35 m, through any node) form one intersection
sig_nodes = sorted(int(k) for k, n in nodes_out.items() if n.get('signalled'))
group_of = {}
signal_groups = {}
for s0 in sig_nodes:
    if s0 in group_of: continue
    gid = len(signal_groups) + 1
    members, stack, seen = [], [(s0, 0.0)], {s0: 0.0}
    while stack:
        cur, d = stack.pop()
        if nodes_out[str(cur)].get('signalled') and cur not in group_of:
            group_of[cur] = gid; members.append(cur); d = 0.0
        for k in adj[cur]:
            o = k[0] if k[1] == cur else k[1]
            nd = d + kept[k]['len']
            if nd <= 35 and (o not in seen or seen[o] > nd):
                seen[o] = nd; stack.append((o, nd))
    cx = sum(V[m]['x'] for m in members) / len(members); cy = sum(V[m]['y'] for m in members) / len(members)
    phases = sorted({c['signal'] for c in conns if c.get('signal') and c['node'] in members})
    signal_groups[str(gid)] = dict(nodes=members, center=[r2(cx), r2(cy), r2(sum(node_z(m) for m in members) / len(members))], phases=phases)
for m, g in group_of.items(): nodes_out[str(m)]['signalGroup'] = g

links_out = {}
for k in sorted(kept):
    lk = kept[k]
    fl = sorted(flagset(k[0]) & flagset(k[1]))
    e = dict(a=k[0], b=k[1], length=r2(lk['len']), lanesAB=lk['ab'], lanesBA=lk['ba'],
             oneway=(lk['ab'] == 0 or lk['ba'] == 0), median=r2(lk['median']),
             laneWidth=lane_width(k), class_=speed_class(lk),
             lanes=[lane_index[(k, f, i)] for f in (True, False) for i in range(dlink_lanes(k, f))])
    if fl: e['flags'] = fl
    if lk.get('tl'): e['trafficLight'] = lk['tl']
    if lk.get('inherited'): e['estimated'] = True
    if lk['dirt']: e['surface'] = 'unpaved'
    links_out[str(link_ids[k])] = e
def fix(d):
    return {('from' if a == 'from_' else 'class' if a == 'class_' else a): b for a, b in d.items()}
lanes_out = {str(l['id']): fix({a: b for a, b in l.items() if a != 'id'}) for l in lanes}
conns_out = {str(c['id']): fix({a: b for a, b in c.items() if a != 'id'}) for c in conns}
links_out = {a: fix(b) for a, b in links_out.items()}
os.makedirs(OUT, exist_ok=True)
meta = dict(
    name='ai_land_traffic road network', version=1, generated='2026-10-11',
    source='GTA:SA nodes.dat car paths + navi links (via newtraffic nodes.lua), surface scan with the claude-mcp probe',
    coords='MTA world metres; a lane runs from points[1] to points[2] (Lua indices); right-hand traffic',
    conventions={
        'node ids': 'GTA path node id = area*4095 + index; nodes[].gps = v_radar vehiclenodes id (area*65536 + index)',
        'lane.index': '0 = innermost lane (next to the centre line / median), counting outward to the right',
        'lane.offset': 'metres to the right of the link centre line, in the lane travel direction',
        'lane.points': 'lane centre line [start, end] with z; junction ends are trimmed back so turn curves fit',
        'connection.curve': 'cubic Bezier control points [p0,p1,p2,p3] from lane end to next lane start; absent when the lanes touch',
        'connection.turn': 'straight | left | right | uturn (uturn only at dead ends)',
        'connection.signal': 'traffic light phase (GTA navi value): 1 = roughly north-south arms, 2 = east-west arms; links.trafficLight is the raw navi value',
        'node.type': 'road (2 links) | junction (3+) | deadend (1) | parking (GTA parking stub; lanes into it have lane.parking = true)',
        'lane.next / lane.prev': 'connection ids (connections.json) leaving / entering the lane',
        'link.lanesAB / lanesBA': 'lane count travelling a->b / b->a; oneway when one of them is 0',
        'link.estimated': 'lane data inherited from the neighbouring link (missing / broken navi record)',
        'link.surface': '"unpaved" when the probe surface scan found mostly dirt/sand/grass under the link (hint for manual removal); absent = paved',
        'link.class': 'highway (both nodes flagged highway) | road',
        'signals.json': 'signal groups: one per real intersection (signalled junction nodes within 35 m along the road); phases = signal values used by its connections',
        'flags': 'GTA node flags: highway, emergency (emergency-vehicles-only path in GTA), parking, roadblock',
    },
    laneWidth=LW, laneWidthHighway=LW_HW,
    counts=dict(nodes=len(nodes_out), links=len(links_out), lanes=len(lanes_out), connections=len(conns_out),
                unpavedLinks=sum(1 for l in links_out.values() if l.get('surface') == 'unpaved'), estimatedLinks=sum(1 for l in links_out.values() if l.get('estimated')),
                signalledJunctions=sum(1 for n in nodes_out.values() if n.get('signalled')), signalGroups=len(signal_groups),
                parkingStubs=sum(1 for n in nodes_out.values() if n['type'] == 'parking'), sinkLanes=len(no_next), sourceLanes=len(no_prev)),
    files=['nodes.json', 'links.json', 'lanes.json', 'connections.json', 'signals.json', 'validation.json'],
)
def dump(name, obj):
    with open(os.path.join(OUT, name), 'w') as f: json.dump(obj, f, separators=(',', ':'))
dump('meta.json', meta)
with open(os.path.join(OUT, 'meta.json'), 'w') as f: json.dump(meta, f, indent=2)
dump('nodes.json', nodes_out); dump('links.json', links_out); dump('lanes.json', lanes_out)
dump('connections.json', conns_out); dump('signals.json', signal_groups);
with open(os.path.join(OUT, 'validation.json'), 'w') as f: json.dump({k: v if k == 'note' else [fix(x) for x in v] for k, v in validation.items()}, f, indent=1)
print(json.dumps(meta['counts']), 'fixed_navi', fixed_navi, 'inherited', inherited, dict(stats), 'no_next', len(no_next), 'no_prev', len(no_prev))
