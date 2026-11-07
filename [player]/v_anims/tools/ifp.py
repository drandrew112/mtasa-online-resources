# Reads the GTA SA animation files (anim/ped.ifp + the IFPs inside anim/anim.img).
# dump() -> { block: { anim: { dur, dx, dy, dz, maxd } } }, maxd = farthest horizontal root travel (m).
import struct, json, sys, math

GTA = "C:/Games/GTA San Andreas/anim/"

def cstr(b):
    return b.split(b"\0", 1)[0].decode("latin1")

def parse_ifp(data):
    assert data[:4] == b"ANP3", data[:4]
    off = 8
    block = cstr(data[off:off+24]); off += 24
    count, = struct.unpack_from("<I", data, off); off += 4
    anims = {}
    for _ in range(count):
        name = cstr(data[off:off+24]); off += 24
        nobj, fsize, comp = struct.unpack_from("<III", data, off); off += 12
        info = {"dur": 0.0, "dx": 0.0, "dy": 0.0, "dz": 0.0, "maxd": 0.0}
        for _o in range(nobj):
            oname = cstr(data[off:off+24]); off += 24
            ftype, nfr, bone = struct.unpack_from("<III", data, off); off += 12
            frames = []
            for _f in range(nfr):
                if comp:
                    if ftype == 4:
                        q = struct.unpack_from("<5h3h", data, off); off += 16
                        t = q[4] / 60.0; tr = (q[5] / 1024.0, q[6] / 1024.0, q[7] / 1024.0)
                    else:
                        q = struct.unpack_from("<5h", data, off); off += 10
                        t = q[4] / 60.0; tr = None
                else:
                    if ftype == 2:
                        q = struct.unpack_from("<5f3f", data, off); off += 32
                        t = q[4]; tr = q[5:8]
                    else:
                        q = struct.unpack_from("<5f", data, off); off += 20
                        t = q[4]; tr = None
                frames.append((t, tr))
            if frames:
                info["dur"] = max(info["dur"], frames[-1][0])
            if frames and frames[0][1] is not None and bone == 0:
                x0, y0, z0 = frames[0][1]
                m = 0.0
                for t, tr in frames:
                    d = math.hypot(tr[0] - x0, tr[1] - y0)
                    m = max(m, d)
                x1, y1, z1 = frames[-1][1]
                info["dx"], info["dy"], info["dz"] = x1 - x0, y1 - y0, z1 - z0
                info["maxd"] = m
        anims[name] = info
    return block, anims

def img_entries(path):
    f = open(path, "rb")
    hdr = f.read(8)
    assert hdr[:4] == b"VER2"
    n, = struct.unpack("<I", hdr[4:8])
    ents = []
    for _ in range(n):
        e = f.read(32)
        o, s = struct.unpack("<IH", e[:6])
        ents.append((cstr(e[8:32]), o * 2048, s * 2048))
    return f, ents

def dump(gta_anim_dir=GTA):
    out = {}
    data = open(gta_anim_dir + "ped.ifp", "rb").read()
    b, a = parse_ifp(data)
    out[b] = a
    f, ents = img_entries(gta_anim_dir + "anim.img")
    for name, o, s in ents:
        if not name.lower().endswith(".ifp"):
            continue
        f.seek(o)
        d = f.read(s)
        try:
            b, a = parse_ifp(d)
            out[b] = a
        except Exception as ex:
            print("fail", name, ex, file=sys.stderr)
    return out
