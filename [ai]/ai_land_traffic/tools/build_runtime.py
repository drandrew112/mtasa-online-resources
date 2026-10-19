# ai_land_traffic runtime data builder:  python tools/build_runtime.py [path/to/roads.nav]
# The road network is navmesh's (resources/[core]/navmesh/data/runtime/roads.nav, built by its tools/build_roads.py).
# This turns it into the two compact files the resource loads, with the SAME lane and connection ids, so the
# routes of the navmesh exports (lanes / connections) can be driven directly:
#   data/runtime/geo.dat  - geometry (server + client, downloaded): lanes and curved connections
#   data/runtime/sim.dat  - topology for the server simulation: lane flags/successors, connection
#                           turn/speed/signal, junction conflicts and right of way
# Rerun it whenever navmesh's roads.nav changes: the server uses no navmesh routes while the signature in sim.dat
# (md5 of roads.nav) differs from the loaded navmesh.
# Formats (one record per line, space separated, "-" = empty list):
#   geo:  L id x1 y1 z1 x2 y2 z2
#         C id fromLane toLane p1x p1y p1z p2x p2y p2z        (p0 = fromLane end, p3 = toLane start)
#   sim:  # navmesh <md5 of roads.nav> <lanes> <connections>
#         L id link flags count index next,next left right   (left / right = neighbouring lane of the
#                           same carriageway, 0 = none; index 0 is the leftmost lane)
#         C id from to node turn length vmax phase group conflicts yields
#         flags: 1 highway, 2 emergency-only path, 4 parking stub, 8 unpaved, 16 roadblock, 32 sink (no successor),
#                64 trap (cannot reach the main network: closed loops like the LS airport garage, stadium tracks)
#         turn: S L R U;  vmax: curve speed m/s (0 = no limit);  phase: 0 / 1 (N-S) / 2 (E-W)
import collections, hashlib, math, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'data', 'runtime')
NAV = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, '..', '..', '[core]', 'navmesh', 'data', 'runtime', 'roads.nav')

A_LAT = 3.2          # m/s^2 comfortable lateral acceleration for the curve speed
CONFLICT_DIST = 2.6  # m: two junction paths closer than this conflict (car width + margin)

# navmesh flags (navmesh shared/config.lua)
NF_JUNCTION = 1
KF_UNPAVED, KF_EMERGENCY, KF_ROADBLOCK = 1, 2, 4
LF_TRAP, LF_PARKING = 1, 2

# ---------------------------------------------------------------- read roads.nav
raw = open(NAV, 'rb').read()
signature = hashlib.md5(raw).hexdigest().upper()
nodes, links, lanes, conns, group_of = {}, {}, {}, {}, {}
for line in raw.decode('ascii').split('\n'):
    if not line or line[0] == '#': continue
    p = line.split()
    k = p[0]
    if k == 'N':
        nodes[int(p[1])] = dict(flags=int(p[6]))
    elif k == 'K':
        links[int(p[1])] = dict(cls=int(p[4]), flags=int(p[5]), ab=int(p[6]), ba=int(p[7]))
    elif k == 'A':
        i = int(p[1])
        lanes[i] = dict(link=int(p[2]), index=int(p[5]), count=int(p[6]), left=int(p[7]), right=int(p[8]),
                        flags=int(p[9]), points=[tuple(map(float, p[10:13])), tuple(map(float, p[13:16]))], next=[])
    elif k == 'C':
        i = int(p[1])
        c = dict(from_=int(p[2]), to=int(p[3]), node=int(p[4]), turn=p[5], signal=int(p[6]), length=float(p[8]))
        if len(p) >= 15:
            b = list(map(float, p[9:15]))
            c['b1'], c['b2'] = b[0:3], b[3:6]
        conns[i] = c
    elif k == 'S':
        for n in p[6].split(','):
            group_of[int(n)] = int(p[1])
for i in sorted(conns):
    lanes[conns[i]['from_']]['next'].append(i)
for l in lanes.values():
    (x1, y1, z1), (x2, y2, z2) = l['points']
    l['length'] = math.sqrt((x2 - x1) ** 2 + (y2 - y1) ** 2 + (z2 - z1) ** 2)


def f2(x):
    s = ('%.2f' % x).rstrip('0').rstrip('.')
    return '0' if s in ('-0', '') else s


def lane_dir(l):
    (x1, y1, _), (x2, y2, _) = l['points']
    d = math.hypot(x2 - x1, y2 - y1)
    return ((x2 - x1) / d, (y2 - y1) / d) if d > 1e-6 else None


def curve_of(c):
    if 'b1' not in c: return None
    return [lanes[c['from_']]['points'][1], c['b1'], c['b2'], lanes[c['to']]['points'][0]]


def bez(cv, t):
    u = 1 - t
    return [u * u * u * cv[0][i] + 3 * u * u * t * cv[1][i] + 3 * u * t * t * cv[2][i] + t * t * t * cv[3][i] for i in range(3)]


def path_points(c):
    """2D polyline of a connection (curve samples, or the touching point)."""
    cv = curve_of(c)
    if cv: return [bez(cv, i / 12) for i in range(13)]
    return [lanes[c['to']]['points'][0]]


def angle_between(a, b):
    if not a or not b: return 0.0
    cr = a[0] * b[1] - a[1] * b[0]
    dt = a[0] * b[0] + a[1] * b[1]
    return math.atan2(cr, dt)


# ---------------------------------------------------------------- lane flags
lane_flags = {}
for i, l in lanes.items():
    lk = links[l['link']]
    parking = bool(l['flags'] & LF_PARKING)
    fl = 0
    if lk['cls'] == 1: fl |= 1
    if lk['flags'] & KF_EMERGENCY: fl |= 2
    if parking: fl |= 4
    if lk['flags'] & KF_UNPAVED: fl |= 8
    if lk['flags'] & KF_ROADBLOCK: fl |= 16
    if not l['next']: fl |= 32
    if l['flags'] & LF_TRAP and not parking and l['next']: fl |= 64
    lane_flags[i] = fl


# ---------------------------------------------------------------- curve speed
def curve_speed(c):
    lin, lout = lanes[c['from_']], lanes[c['to']]
    dth = abs(angle_between(lane_dir(lin), lane_dir(lout)))
    if c['turn'] == 'U': return 4.0
    if dth < 0.03: return 0.0
    if 'b1' in c and c['length'] > 0.5:
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
    if nodes[c['node']]['flags'] & NF_JUNCTION:
        by_node[c['node']].append(i)


def approach_rank(ci):
    lk = links[lanes[conns[ci]['from_']]['link']]
    return lk['ab'] + lk['ba'] + (4 if lk['cls'] == 1 else 0)


def min_dist(pa, pb):
    best = 1e9
    for a in pa:
        for b in pb:
            d = math.hypot(a[0] - b[0], a[1] - b[1])
            if d < best: best = d
    return best


def is_right_of(ci, cj):
    """True when cj's approach comes from ci's right (right-hand priority)."""
    di = lane_dir(lanes[conns[ci]['from_']])
    dj = lane_dir(lanes[conns[cj]['from_']])
    if not di or not dj: return False
    # a vehicle coming from my right drives to my left: its heading is my heading turned +90 deg
    a = angle_between(di, dj)
    return 0.6 < a < 2.5


def yields_to(ci, cj):
    a, b = conns[ci], conns[cj]
    sa, sb = a['signal'], b['signal']
    ta, tb = a['turn'], b['turn']
    if sa and sb:
        if sa != sb: return False                      # never green together: occupancy only
        return ta == 'L' and tb != 'L'                 # permitted left turn yields to oncoming
    if sb and not sa: return True                      # unsignalled arm of a signalled junction
    if sa and not sb: return False
    ra, rb = approach_rank(ci), approach_rank(cj)
    if ra != rb: return ra < rb                        # minor road yields to the major one
    di = lane_dir(lanes[a['from_']]); dj = lane_dir(lanes[b['from_']])
    opposing = di and dj and (di[0] * dj[0] + di[1] * dj[1]) < -0.7
    if opposing:
        return ta == 'L' and tb != 'L'
    if a['to'] == b['to'] and ta != tb:                # merging: turning yields to straight
        if ta != 'S' and tb == 'S': return True
        if tb != 'S' and ta == 'S': return False
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
            if a['from_'] == b['from_']: continue                          # same queue: car following
            same_target = a['to'] == b['to']
            if not same_target and min_dist(pts_cache[ci], pts_cache[cj]) > CONFLICT_DIST: continue
            conflicts[ci].append(cj); conflicts[cj].append(ci)
            if yields_to(ci, cj): yields[ci].append(cj)
            elif yields_to(cj, ci): yields[cj].append(ci)

# ---------------------------------------------------------------- write
os.makedirs(OUT, exist_ok=True)
geo = ['# ai_land_traffic geometry, generated by tools/build_runtime.py from navmesh roads.nav']
sim = ['# ai_land_traffic topology, generated by tools/build_runtime.py from navmesh roads.nav',
       '# navmesh %s %d %d' % (signature, len(lanes), len(conns))]
for i in sorted(lanes):
    l = lanes[i]
    (x1, y1, z1), (x2, y2, z2) = l['points']
    geo.append('L %d %s %s %s %s %s %s' % (i, f2(x1), f2(y1), f2(z1), f2(x2), f2(y2), f2(z2)))
    nxt = ','.join(str(c) for c in l['next']) or '-'
    sim.append('L %d %d %d %d %d %s %d %d' % (i, l['link'], lane_flags[i], l['count'], l['index'], nxt, l['left'], l['right']))
for i in sorted(conns):
    c = conns[i]
    if 'b1' in c:
        p1, p2 = c['b1'], c['b2']
        geo.append('C %d %d %d %s %s %s %s %s %s' % (i, c['from_'], c['to'], f2(p1[0]), f2(p1[1]), f2(p1[2]), f2(p2[0]), f2(p2[1]), f2(p2[2])))
    sim.append('C %d %d %d %d %s %s %s %d %d %s %s' % (
        i, c['from_'], c['to'], c['node'], c['turn'], f2(c['length'] if 'b1' in c else 0),
        f2(curve_speed(c)), c['signal'], group_of.get(c['node'], 0),
        ','.join(map(str, sorted(conflicts[i]))) or '-', ','.join(map(str, sorted(yields[i]))) or '-'))

for name, rows in (('geo.dat', geo), ('sim.dat', sim)):
    with open(os.path.join(OUT, name), 'w', encoding='ascii', newline='\n') as f:
        f.write('\n'.join(rows) + '\n')
    print(name, len(rows), 'lines', os.path.getsize(os.path.join(OUT, name)) // 1024, 'KB')
print('navmesh signature:', signature, 'lanes:', len(lanes), 'connections:', len(conns))
print('trap lanes:', sum(1 for f in lane_flags.values() if f & 64))
print('junction connections with conflicts:', sum(1 for v in conflicts.values() if v), 'yield pairs:', sum(len(v) for v in yields.values()))
