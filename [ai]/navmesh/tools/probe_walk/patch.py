# raw probe scan -> walk grid patch:  python tools/probe_walk/patch.py data/build/probe_<name>_raw.json data/source/probe_walk/<name>.json <name>
# A blocked centre-to-centre link removes one of its two cells: the one with more blocked links (the wall cell, not the
# doorway next to it). Then rerun node tools/walkgrid.js.
import json,sys,collections
src,out,name=sys.argv[1],sys.argv[2],sys.argv[3]
d=json.load(open(src))
F={}   # (gx,gy) -> {zdm: [mat,nz]}
for gx,gy,z,mat,nz in d['floors']:
    c=F.setdefault((gx,gy),{})
    if not any(abs(q-z)<3 for q in c): c[z]=[mat,nz]
def key(gx,gy,z):
    for q in F.get((gx,gy),{}):
        if abs(q-z)<=2: return (gx,gy,q)
    return None
links=[]
deg=collections.Counter()
for gx,gy,z,dr,nz,t in d['blocks']:
    a=key(gx,gy,z); b=key(gx+(dr==1),gy+(dr==2),nz)
    if not a or not b: continue
    links.append((a,b,t)); deg[a]+=1; deg[b]+=1
removed=set()
# most blocked first: wall cells go before door cells
links.sort(key=lambda l:-max(deg[l[0]],deg[l[1]]))
for a,b,t in links:
    if a in removed or b in removed: continue
    if deg[a]!=deg[b]: r=a if deg[a]>deg[b] else b
    else: r=a if t<50 else b
    removed.add(r)
for gx,gy,z in removed: del F[(gx,gy)][z]
cells=[]
for (gx,gy),c in sorted(F.items()):
    zs=sorted(c)
    for z in zs:
        mat,nz=c[z]
        roofed=1 if any(q>z+17 for q in zs) else 0
        cells.append([gx,gy,z,mat,nz,roofed])
json.dump({'name':name,'source':'claude-mcp probe scan (live collision, doors open)','box':d['box'],
    'format':'cells: [gx (world x of the cell min), gy, z dm, surface material id, |normal z| * 100, roofed]','cells':cells},
    open(out,'w'),separators=(',',':'))
print('cells',len(cells),'links',len(links),'removed',len(removed))
