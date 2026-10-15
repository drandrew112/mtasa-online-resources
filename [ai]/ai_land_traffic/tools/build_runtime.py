# ai_land_traffic runtime data builder:  python tools/build_runtime.py
# Run after tools/build_network.py. Turns the readable network JSON (data/*.json) into the two compact
# text files the resource loads:
#   data/runtime/geo.dat  - geometry (server + client, downloaded): lanes and curved connections
#   data/runtime/sim.dat  - topology for the server simulation: lane flags/successors, connection
#                           turn/speed/signal, junction conflicts and right of way
# Formats (one record per line, space separated, "-" = empty list):
#   geo:  L id x1 y1 z1 x2 y2 z2
#         C id fromLane toLane p1x p1y p1z p2x p2y p2z        (p0 = fromLane end, p3 = toLane start)
#   sim:  L id link flags count index next,next left right   (left / right = neighbouring lane of the
#                           same carriageway, 0 = none; index 0 is the leftmost lane)
#         C id from to node turn length vmax phase group conflicts yields
#         flags: 1 highway, 2 emergency-only path, 4 parking stub, 8 unpaved, 16 roadblock, 32 sink (no successor),
#                64 trap (cannot reach the main network: closed loops like the LS airport garage, stadium tracks)
#         turn: S L R U;  vmax: curve speed m/s (0 = no limit);  phase: 0 / 1 (N-S) / 2 (E-W)
import json, math, os, collections

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, 'data')
OUT = os.path.join(DATA, 'runtime')

A_LAT = 3.2          # m/s^2 comfortable lateral acceleration for the curve speed
CONFLICT_DIST = 2.6  # m: two junction paths closer than this conflict (car width + margin)


def load(name):
    with open(os.path.join(DATA, name), encoding='utf-8') as f:
        return json.load(f)


nodes, links, lanes, conns = load('nodes.json'), load('links.json'), load('lanes.json'), load('connections.json')
lanes = {int(k): v for k, v in lanes.items()}
conns = {int(k): v for k, v in conns.items()}
links = {int(k): v for k, v in links.items()}


def f2(x):
    s = ('%.2f' % x).rstrip('0').rstrip('.')
    return '0' if s in ('-0', '') else s


def lane_dir(l):
    (x1, y1, _), (x2, y2, _) = l['points']
    d = math.hypot(x2 - x1, y2 - y1)
    return ((x2 - x1) / d, (y2 - y1) / d) if d > 1e-6 else None


def bez(c, t):
    u = 1 - t
    return [u * u * u * c[0][i] + 3 * u * u * t * c[1][i] + 3 * u * t * t * c[2][i] + t * t * t * c[3][i] for i in range(3)]


def path_points(c):
    """2D polyline of a connection (curve samples, or the touching point)."""
    if 'curve' in c:
        return [bez(c['curve'], i / 12) for i in range(13)]
    p = lanes[c['to']]['points'][0]
    return [p]


def angle_between(a, b):
    if not a or not b: return 0.0
    cr = a[0] * b[1] - a[1] * b[0]
    dt = a[0] * b[0] + a[1] * b[1]
    return math.atan2(cr, dt)


# ---------------------------------------------------------------- main network (largest strongly connected part)
def main_component():
    adj = {i: [conns[c]['to'] for c in l['next']] for i, l in lanes.items()}
    index, low, stack, on, comp, idx, cid = {}, {}, [], set(), {}, 0, 0
    for root in lanes:
        if root in index: continue
        work = [(root, iter(adj[root]))]
        index[root] = low[root] = idx; idx += 1; stack.append(root); on.add(root)
        while work:
            v, it = work[-1]
            w = next(it, None)
            if w is not None:
                if w not in index:
                    index[w] = low[w] = idx; idx += 1; stack.append(w); on.add(w); work.append((w, iter(adj[w])))
                elif w in on:
                    low[v] = min(low[v], index[w])
            else:
                work.pop()
                if work: low[work[-1][0]] = min(low[work[-1][0]], low[v])
                if low[v] == index[v]:
                    while True:
                        x = stack.pop(); on.discard(x); comp[x] = cid
                        if x == v: break
                    cid += 1
    main = collections.Counter(comp.values()).most_common(1)[0][0]
    # lanes that can reach the main component (reverse search)
    radj = collections.defaultdict(list)
    for v, ws in adj.items():
        for w in ws: radj[w].append(v)
    reach = {i for i in lanes if comp[i] == main}
    todo = list(reach)
    while todo:
        w = todo.pop()
        for v in radj[w]:
            if v not in reach: reach.add(v); todo.append(v)
    return reach


reach_main = main_component()

# ---------------------------------------------------------------- lane flags
lane_flags = {}
for i, l in lanes.items():
    lk = links[l['link']]
    fl = 0
    if lk['class'] == 'highway': fl |= 1
    if 'emergency' in lk.get('flags', []): fl |= 2
    if l.get('parking'): fl |= 4
    if lk.get('surface') == 'unpaved': fl |= 8
    if 'roadblock' in lk.get('flags', []): fl |= 16
    if not l['next']: fl |= 32
    if i not in reach_main and not l.get('parking') and l['next']: fl |= 64
    lane_flags[i] = fl

# ---------------------------------------------------------------- curve speed
def curve_speed(c):
    lin, lout = lanes[c['from']], lanes[c['to']]
    dth = abs(angle_between(lane_dir(lin), lane_dir(lout)))
    if c['turn'] == 'uturn': return 4.0
    if dth < 0.03: return 0.0
    if c.get('length', 0) > 0.5:
        r = c['length'] / dth
    else:
        # kink between two touching lanes: the vehicle rounds it over about half of the shorter lane
        r = max(4.0, min(lin['length'], lout['length'], 30.0)) / dth
    v = math.sqrt(A_LAT * r)
    if v > 35: return 0.0
    return max(4.0, v)

# ---------------------------------------------------------------- junction conflicts and priority
by_node = collections.defaultdict(list)
for i, c in conns.items():
    if nodes[str(c['node'])]['type'] == 'junction':
        by_node[c['node']].append(i)


def approach_rank(ci):
    c = conns[ci]
    lk = links[lanes[c['from']]['link']]
    return lk['lanesAB'] + lk['lanesBA'] + (4 if lk['class'] == 'highway' else 0)


def min_dist(pa, pb):
    best = 1e9
    for a in pa:
        for b in pb:
            d = math.hypot(a[0] - b[0], a[1] - b[1])
            if d < best: best = d
    return best


def is_right_of(ci, cj):
    """True when cj's approach comes from ci's right (right-hand priority)."""
    di = lane_dir(lanes[conns[ci]['from']])
    dj = lane_dir(lanes[conns[cj]['from']])
    if not di or not dj: return False
    # a vehicle coming from my right drives to my left: its heading is my heading turned +90 deg
    a = angle_between(di, dj)
    return 0.6 < a < 2.5


def yields_to(ci, cj):
    a, b = conns[ci], conns[cj]
    sa, sb = a.get('signal', 0), b.get('signal', 0)
    ta, tb = a['turn'], b['turn']
    if sa and sb:
        if sa != sb: return False                      # never green together: occupancy only
        return ta == 'left' and tb != 'left'           # permitted left turn yields to oncoming
    if sb and not sa: return True                      # unsignalled arm of a signalled junction
    if sa and not sb: return False
    ra, rb = approach_rank(ci), approach_rank(cj)
    if ra != rb: return ra < rb                        # minor road yields to the major one
    di = lane_dir(lanes[a['from']]); dj = lane_dir(lanes[b['from']])
    opposing = di and dj and (di[0] * dj[0] + di[1] * dj[1]) < -0.7
    if opposing:
        return ta == 'left' and tb != 'left'
    if a['to'] == b['to'] and ta != tb:                # merging: turning yields to straight
        if ta != 'straight' and tb == 'straight': return True
        if tb != 'straight' and ta == 'straight': return False
    return is_right_of(ci, cj)


conflicts = collections.defaultdict(list)
yields = collections.defaultdict(list)
pts_cache = {}
for node, ids in by_node.items():
    for i in ids: pts_cache[i] = path_points(conns[i])
    for x in range(len(ids)):
        for y in range(x + 1, len(ids)):
            ci, cj = ids[x], ids[y]
            a, b = conns[ci], conns[cj]
            if a['from'] == b['from']: continue                            # same queue: car following
            same_target = a['to'] == b['to']
            if not same_target and min_dist(pts_cache[ci], pts_cache[cj]) > CONFLICT_DIST: continue
            conflicts[ci].append(cj); conflicts[cj].append(ci)
            if yields_to(ci, cj): yields[ci].append(cj)
            elif yields_to(cj, ci): yields[cj].append(ci)

# ---------------------------------------------------------------- write
os.makedirs(OUT, exist_ok=True)
geo, sim = [], []
group = collections.defaultdict(dict)
for i, l in lanes.items():
    group[(l['link'], l['from'], l['to'])][l['index']] = i
geo.append('# ai_land_traffic geometry, generated by tools/build_runtime.py')
sim.append('# ai_land_traffic topology, generated by tools/build_runtime.py')
for i in sorted(lanes):
    l = lanes[i]
    (x1, y1, z1), (x2, y2, z2) = l['points']
    geo.append('L %d %s %s %s %s %s %s' % (i, f2(x1), f2(y1), f2(z1), f2(x2), f2(y2), f2(z2)))
    nxt = ','.join(str(c) for c in l['next']) or '-'
    g = group[(l['link'], l['from'], l['to'])]
    sim.append('L %d %d %d %d %d %s %d %d' % (i, l['link'], lane_flags[i], l['count'], l['index'], nxt,
                                            g.get(l['index'] - 1, 0), g.get(l['index'] + 1, 0)))
TURN = dict(straight='S', left='L', right='R', uturn='U')
for i in sorted(conns):
    c = conns[i]
    if 'curve' in c:
        p1, p2 = c['curve'][1], c['curve'][2]
        geo.append('C %d %d %d %s %s %s %s %s %s' % (i, c['from'], c['to'], f2(p1[0]), f2(p1[1]), f2(p1[2]), f2(p2[0]), f2(p2[1]), f2(p2[2])))
    group = nodes[str(c['node'])].get('signalGroup', 0)
    sim.append('C %d %d %d %d %s %s %s %d %d %s %s' % (
        i, c['from'], c['to'], c['node'], TURN[c['turn']], f2(c['length'] if 'curve' in c else 0),
        f2(curve_speed(c)), c.get('signal', 0), group,
        ','.join(map(str, sorted(conflicts[i]))) or '-', ','.join(map(str, sorted(yields[i]))) or '-'))

for name, rows in (('geo.dat', geo), ('sim.dat', sim)):
    with open(os.path.join(OUT, name), 'w', encoding='ascii', newline='\n') as f:
        f.write('\n'.join(rows) + '\n')
    print(name, len(rows), 'lines', os.path.getsize(os.path.join(OUT, name)) // 1024, 'KB')
print('trap lanes:', sum(1 for f in lane_flags.values() if f & 64))
print('junction connections with conflicts:', sum(1 for v in conflicts.values() if v), 'yield pairs:', sum(len(v) for v in yields.values()))
