# Parses the old newtraffic nodes.lua (decoded GTA SA nodes.dat) into data/source/gta_paths.json.
# python tools/parse_nodes.py
import re, json, sys, os
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src = open(os.path.join(ROOT, 'data', 'source', 'resource newtraffic', 'nodes.lua'), encoding='latin-1').read()
veh, navi, ped = {}, [], {}
section = None
rx_node = re.compile(r'\[(\d+)\]=\{id=(\d+),x=([-\d.]+),y=([-\d.]+),z=([-\d.]+),width=([-\d.]+),type=(\d+),flags=\{([^}]*)\},nbs=\{([^}]*)\},navinbs=\{([^}]*)\}\}')
rx_navi = re.compile(r'\[(\d+)\]=\{id=(\d+),x=([-\d.]+),y=([-\d.]+),dx=([-\d.]+),dy=([-\d.]+),width=([-\d.]+),leftlanes=(\d+),rightlanes=(\d+),trafficlight=(\d+),nb=(\d+)\}')
other = set()
for line in src.splitlines():
    s = line.strip()
    if s.startswith('veh='): section='veh'; continue
    if s.startswith('ped='): section='ped'; continue
    if s.startswith('navi'): section='navi'; continue
    if not s.startswith('['): continue
    if section in ('veh','ped'):
        m = rx_node.match(s)
        if not m: other.add(s[:120]); continue
        i=int(m[2]); flags=[f.split('=')[0] for f in m[8].split(',') if f]
        nbs={int(a):float(b) for a,b in re.findall(r'\[(\d+)\]=([-\d.]+)', m[9])}
        nv=[int(v) for v in m[10].split(',') if v]
        (veh if section=='veh' else ped)[i]=dict(x=float(m[3]),y=float(m[4]),z=float(m[5]),w=float(m[6]),type=int(m[7]),flags=flags,nbs=nbs,navi=nv)
    elif section=='navi':
        m = rx_navi.match(s)
        if not m: other.add(s[:120]); continue
        navi.append(dict(x=float(m[3]),y=float(m[4]),dx=float(m[5]),dy=float(m[6]),w=float(m[7]),l=int(m[8]),r=int(m[9]),tl=int(m[10]),nb=int(m[11])))  # navi ids repeat across areas: kept as a list
print(len(veh), 'car nodes', len(navi), 'navi links')
json.dump(dict(veh=veh, navi=navi), open(os.path.join(ROOT, 'data', 'source', 'gta_paths.json'), 'w'), separators=(',', ':'))
