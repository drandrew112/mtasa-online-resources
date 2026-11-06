import sys, json, os, time
import mcp
HERE = os.path.dirname(os.path.abspath(__file__))
SKIP = [1491, 1492, 1493, 1494, 1495, 1496, 1497, 1498, 1499, 1500, 1501, 1502, 1504, 1505, 1506, 1507, 1523, 1532, 1535, 1536, 1537, 1555, 1556, 1557, 1566, 1567, 1569, 3051, 2911, 3089, 2949, 2948]

def scan(name, x0, y0, x1, y1, zf, cell=0.2, hlow=1.1, hhigh=1.9):
    code = open(os.path.join(HERE, "scan.lua")).read()
    pre = "CEIL=%s\nX0,Y0,X1,Y1,CELL,ZF,HLOW,HHIGH=%r,%r,%r,%r,%r,%r,%r,%r\nSKIP={%s}\n" % (
        os.environ.get("CEIL", "4.5"), x0, y0, x1, y1, cell, zf, hlow, hhigh, ",".join("[%d]=true" % m for m in SKIP))
    t = time.time()
    r = mcp.lua(pre + code, timeout=240)
    if not r.get("success"):
        print(r); sys.exit(1)
    res = r["results"][0]
    nx, ny = int(res[0]), int(res[1])
    s = "".join(res[2:])
    assert len(s) == nx * ny, (len(s), nx, ny)
    json.dump({"x0": x0, "y0": y0, "x1": x1, "y1": y1, "cell": cell, "zf": zf, "nx": nx, "ny": ny, "data": s},
              open(os.path.join(HERE, name + ".json"), "w"))
    print(name, nx, ny, "%.1fs" % (time.time() - t))

def scan_tiled(name, x0, y0, x1, y1, zf, cell=0.2, tile=30, hlow=1.1, hhigh=1.9):
    nx = int(round((x1 - x0) / cell)); ny = int(round((y1 - y0) / cell))
    tc = int(tile / cell)
    rows = [bytearray(b"0" * nx) for _ in range(ny)]
    for ty in range(0, ny, tc):
        for tx in range(0, nx, tc):
            tnx = min(tc, nx - tx); tny = min(tc, ny - ty)
            ax = x0 + tx * cell; ay = y0 + ty * cell
            scan("_tile", ax, ay, ax + tnx * cell, ay + tny * cell, zf, cell, hlow, hhigh)
            t = json.load(open(os.path.join(HERE, "_tile.json")))
            assert t["nx"] == tnx and t["ny"] == tny, (t["nx"], t["ny"], tnx, tny)
            for j in range(tny):
                rows[ty + j][tx:tx + tnx] = t["data"][j * tnx:(j + 1) * tnx].encode()
    json.dump({"x0": x0, "y0": y0, "x1": x1, "y1": y1, "cell": cell, "zf": zf, "nx": nx, "ny": ny,
               "data": b"".join(rows).decode()}, open(os.path.join(HERE, name + ".json"), "w"))
    print("done", name, nx, ny)

if __name__ == "__main__":
    a = sys.argv
    scan_tiled(a[1], *map(float, a[2:7]))
