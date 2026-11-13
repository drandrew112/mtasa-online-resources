"""numpy port of the road part of fx/snow_world.fx (RoadLanes + JunctionTracks + the road snow mix), for the
offline tools: tests/check_roadmap.py (seam score, path coverage) and tools/render_junction.py (top-down PNGs).

Every function takes numpy arrays of world points and works on the FULL lane map images in data/ (the client
windows them, tests/test_roadwindow.py proves the window holds the same pixels).

    m = RoadMap()                      # format 4 (data/roadmap*.png + data/road/jpaths.png, jlists.png)
    m = RoadMap(old_dir)               # format 3 (roadmap.png / roadmap2.png / roadmapz.png of an older build)
    r = m.road(x, y, z, px)            # px = metres per pixel (noise mip level) -> dict of arrays
"""
import json
import math
import os

import numpy as np
from PIL import Image

RES = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
JK = 8


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def sat(x):
    return np.clip(x, 0, 1)


def raw16(hi, lo):
    return hi.astype(np.float64) * 256 + lo


class Noise:
    """tex/noise.png with a box filtered mip chain; sample(channel, u, v, footprint in texture units)"""

    def __init__(self):
        img = np.asarray(Image.open(os.path.join(RES, "tex", "noise.png")).convert("RGBA")).astype(np.float32) / 255
        self.mips = [img]
        while self.mips[-1].shape[0] > 1:
            m = self.mips[-1]
            self.mips.append((m[0::2, 0::2] + m[1::2, 0::2] + m[0::2, 1::2] + m[1::2, 1::2]) / 4)

    def sample(self, ch, u, v, fp):
        size = self.mips[0].shape[0]
        lvl = np.clip(np.round(np.log2(np.maximum(fp * size, 1e-6))), 0, len(self.mips) - 1).astype(int)
        out = np.zeros(np.shape(u), dtype=np.float64)
        for L in np.unique(lvl):
            sel = lvl == L
            tex = self.mips[L][..., ch]
            n = tex.shape[0]
            x = u[sel] * n - 0.5
            y = v[sel] * n - 0.5
            x0, y0 = np.floor(x), np.floor(y)
            fx, fy = x - x0, y - y0
            x0, y0 = x0.astype(int) % n, y0.astype(int) % n
            x1, y1 = (x0 + 1) % n, (y0 + 1) % n
            out[sel] = (tex[y0, x0] * (1 - fx) * (1 - fy) + tex[y0, x1] * fx * (1 - fy)
                        + tex[y1, x0] * (1 - fx) * fy + tex[y1, x1] * fx * fy)
        return out


class RoadMap:
    def __init__(self, old_dir=None):
        data = os.path.join(RES, "data")
        if old_dir:
            self.info = json.load(open(os.path.join(old_dir, "roadmap.json")))[0]
            src = old_dir
        else:
            self.info = json.load(open(os.path.join(data, "roadmap.json")))[0]
            src = data
        self.format = self.info["format"]
        load = lambda n: np.asarray(Image.open(os.path.join(src, n)).convert("RGBA")).astype(np.int64)
        self.L1, self.L2, self.LZ = load("roadmap.png"), load("roadmap2.png"), load("roadmapz.png")
        self.cell = self.info["size"] / self.info["cells"]
        self.n = self.info["cells"]
        self.noise = Noise()
        if self.format >= 4:
            self.LJ = load("roadmapj.png")
            jp = np.asarray(Image.open(os.path.join(data, "road", "jpaths.png")).convert("RGBA")).astype(np.int64)
            jl = np.asarray(Image.open(os.path.join(data, "road", "jlists.png")).convert("RGBA")).astype(np.int64)
            self.jlists = jl.reshape(-1, 4)
            t = jp.reshape(-1, 4)
            npaths = self.info["jPaths"]
            t = t[:npaths * 4].reshape(npaths, 4, 4)
            hi = raw16(t[:, 0, 0], t[:, 0, 1])
            rel = self.info["jRel"]
            self.p_origin = np.stack([self.info["minX"] + (hi % 2048) * self.cell,
                                      self.info["minY"] + raw16(t[:, 0, 2], t[:, 0, 3]) * self.cell], 1)
            self.p_type = (hi // 2048) % 4
            self.p_fa = (hi // 8192) % 2
            self.p_fb = hi // 16384
            pts = []
            for m in (1, 2, 3):
                pts.append(self.p_origin + np.stack([raw16(t[:, m, 0], t[:, m, 1]), raw16(t[:, m, 2], t[:, m, 3])], 1)
                           / 65535.0 * 2 * rel - rel)
            self.p0, self.p1, self.p2 = pts

    # ------------------------------------------------------------------ RoadLanes
    def lanes(self, x, y, z):
        """-> dict: lf, on, dir (2 arrays), edge, jc (offset, count, mask), ij"""
        info, c = self.info, self.cell
        i = np.floor((x - info["minX"]) / c).astype(int)
        j = np.floor((y - info["minY"]) / c).astype(int)
        ok = (i >= 0) & (j >= 0) & (i < self.n) & (j < self.n)
        i, j = np.clip(i, 0, self.n - 1), np.clip(j, 0, self.n - 1)
        zz = self.LZ[j, i]
        zr = info["zMax"] - info["zMin"]
        z1 = (zz[..., 0] * 256 + zz[..., 1]) / 65535 * zr + info["zMin"]
        z2 = (zz[..., 2] * 256 + zz[..., 3]) / 65535 * zr + info["zMin"]
        out = {"lf": np.full(x.shape, 0.5), "on": np.zeros(x.shape), "dx": np.ones(x.shape), "dy": np.zeros(x.shape),
               "edge": np.full(x.shape, 99.0), "joff": np.zeros(x.shape), "jcnt": np.zeros(x.shape),
               "jmask": np.zeros(x.shape), "junction_code": np.zeros(x.shape, dtype=bool), "i": i, "j": j}
        if self.format >= 4:
            at1 = ok & (np.abs(z - z1) < 3.5)
            jj = self.LJ[j, i]
            out["joff"] = np.where(at1, raw16(jj[..., 0], jj[..., 1]), 0)
            out["jcnt"] = np.where(at1, jj[..., 2], 0)
            # bilinear mask (D3D linear filter: texel centres at cell centres)
            u = (x - info["minX"]) / c - 0.5
            v = (y - info["minY"]) / c - 0.5
            u0, v0 = np.floor(u).astype(int), np.floor(v).astype(int)
            fu, fv = u - u0, v - v0
            A = self.LJ[..., 3] / 255.0
            g = lambda a, b: A[np.clip(b, 0, self.n - 1), np.clip(a, 0, self.n - 1)]
            m = (g(u0, v0) * (1 - fu) * (1 - fv) + g(u0 + 1, v0) * fu * (1 - fv)
                 + g(u0, v0 + 1) * (1 - fu) * fv + g(u0 + 1, v0 + 1) * fu * fv)
            out["jmask"] = np.where(at1, m, 0)
        r1, r2 = self.L1[j, i], self.L2[j, i]
        use1 = ok & (r1[..., 3] > 0) & (np.abs(z - z1) < 3.5)
        use2 = ok & ~use1 & (r2[..., 3] > 0) & (np.abs(z - z2) < 3.5)
        r = np.where(use1[..., None], r1, r2)
        have = use1 | use2
        a8 = r[..., 3]
        dc = (r[..., 0] * 256 + r[..., 1]) / 65535 * 2 * info["dRange"] - info["dRange"]
        ang = r[..., 2] / 256 * 2 * math.pi
        nx, ny = np.cos(ang), np.sin(ang)
        cx = info["minX"] + (i + 0.5) * c
        cy = info["minY"] + (j + 0.5) * c
        d = dc + (x - cx) * nx + (y - cy) * ny
        left, right, med = a8 % 4, (a8 // 4) % 4, (a8 // 16) * 0.5 * 2
        junc = have & (left + right == 0)
        out["junction_code"] = junc
        have = have & ~junc
        leftW = left * 5
        width = (left + right) * 5 + med
        xx = d + width * 0.5
        inL = sat(xx * 4 + 1) * sat((leftW - xx) * 4 + 1) * (left > 0)
        xr = xx - leftW - med
        inR = sat(xr * 4 + 1) * sat((right * 5 - xr) * 4 + 1) * (right > 0)
        lf = np.where(xx < leftW + med * 0.5, np.mod(np.maximum(xx, 0) / 5, 1), np.mod(np.maximum(xr, 0) / 5, 1))
        out["lf"] = np.where(have, lf, 0.5)
        out["on"] = np.where(have, sat(inL + inR), 0)
        out["dx"] = np.where(have, -ny, 1.0)
        out["dy"] = np.where(have, nx, 0.0)
        out["edge"] = np.where(have, np.minimum(xx, width - xx), 99.0)
        return out

    # ------------------------------------------------------------------ noise in a lane frame
    def frame_noise(self, x, y, dx, dy, px):
        px_ = -dy
        py_ = dx
        along = x * dx + y * dy
        across = x * px_ + y * py_
        st1 = self.noise.sample(1, along * 0.011, across * 0.31, px * 0.31)
        st2 = self.noise.sample(2, along * 0.035 + 0.5, across * 1.7, px * 1.7)
        st3 = self.noise.sample(0, along * 0.09 + 0.2, across * 4.5, px * 4.5)
        return st1, st2, st3

    # ------------------------------------------------------------------ JunctionTracks
    def path_of_list(self, joff, k):
        t = (joff + k // 2).astype(int)
        e = self.jlists[np.clip(t, 0, len(self.jlists) - 1)]
        return np.where(k % 2 == 0, raw16(e[..., 0], e[..., 1]), raw16(e[..., 2], e[..., 3])).astype(int)

    def bezier_nearest(self, x, y, p0, p1, p2):
        qa = p0 - 2 * p1 + p2
        qb = 2 * (p1 - p0)
        ch = p2 - p0
        X = np.stack([x, y], -1)
        t = np.sum((X - p0) * ch, -1) / np.maximum(np.sum(ch * ch, -1), 0.01)
        for _ in range(3):
            r = (qa * t[..., None] + qb) * t[..., None] + p0 - X
            d1 = 2 * qa * t[..., None] + qb
            f = np.sum(r * d1, -1)
            fp = np.sum(d1 * d1, -1) + 2 * np.sum(r * qa, -1)
            t = np.clip(t - f / np.maximum(fp, 0.05), -0.5, 1.5)
        bp = (qa * t[..., None] + qb) * t[..., None] + p0
        tg = 2 * qa * t[..., None] + qb + np.array([1e-5, 0])
        tg = tg / np.linalg.norm(tg, axis=-1, keepdims=True)
        s = (X[..., 0] - bp[..., 0]) * -tg[..., 1] + (X[..., 1] - bp[..., 1]) * tg[..., 0]
        return t, s, bp

    def junction_tracks(self, x, y, joff, jcnt, mask, px, only=None, pf=1.0):
        """-> tracks, rim, stop (arrays); only = a path index: that path alone (coverage test)"""
        tr_all = np.zeros(x.shape)
        rim_all = np.zeros(x.shape)
        stop_all = np.zeros(x.shape)
        for k in range(JK):
            act = k < jcnt
            if not act.any():
                break
            idx = self.path_of_list(joff, k)
            if only is not None:
                act = act & (idx == only)
            idx = np.where(act, idx, 0)
            p0, p1, p2 = self.p0[idx], self.p1[idx], self.p2[idx]
            t, s, _ = self.bezier_nearest(x, y, p0, p1, p2)
            ch = p2 - p0
            L = (np.linalg.norm(ch, axis=-1) + np.linalg.norm(p1 - p0, axis=-1) + np.linalg.norm(p2 - p1, axis=-1)) * 0.5
            endF = 1 - smoothstep(0, 1, np.maximum(-t, t - 1) * L)
            on = act & (np.abs(s) < 2.6) & (endF > 0.001)
            if not on.any():
                continue
            tin = p1 - p0 + ch * 0.001 + np.array([1e-5, 0])
            tin = tin / np.linalg.norm(tin, axis=-1, keepdims=True)
            tout = p2 - p1 + ch * 0.001 + np.array([1e-5, 0])
            tout = tout / np.linalg.norm(tout, axis=-1, keepdims=True)
            bl = smoothstep(0.3, 0.7, t)
            fa = np.where(self.p_fa[idx] > 0, -1.0, 1.0)[..., None]
            fb = np.where(self.p_fb[idx] > 0, -1.0, 1.0)[..., None]
            a1, a2, _ = self.frame_noise(x, y, tin[..., 0] * fa[..., 0], tin[..., 1] * fa[..., 0], px)
            b1, b2, _ = self.frame_noise(x, y, tout[..., 0] * fb[..., 0], tout[..., 1] * fb[..., 0], px)
            n1 = np.where(bl < 0.999, a1, 0.5) * (1 - bl) + np.where(bl > 0.001, b1, 0.5) * bl
            n2 = np.where(bl < 0.999, a2, 0.5) * (1 - bl) + np.where(bl > 0.001, b2, 0.5) * bl
            ptype = self.p_type[idx]
            w = np.where(ptype == 0, 1.0, np.where(ptype == 1, 0.7, 0.5))
            sp = np.where(ptype == 0, 0.0, 0.012)
            wob = (n1 - 0.5) * 0.07
            lf = s / 5 + 0.5
            d1 = np.abs(lf - 0.32 - wob)
            d2 = np.abs(lf - 0.68 - wob)
            tr = np.maximum(1 - smoothstep(0.03 + sp, 0.085 + 2 * sp, d1), 1 - smoothstep(0.03 + sp, 0.085 + 2 * sp, d2))
            arcT = np.clip(t, 0, 1) * L
            g = w * endF * smoothstep(0, 4, arcT) * smoothstep(0, 4, L - arcT) * pf
            tr_all = np.where(on, np.maximum(tr_all, sat(tr * (0.6 + 0.6 * n2)) * g * (1 - 0.3 * mask)), tr_all)
            dm = np.minimum(d1, d2)
            rim = smoothstep(0.05, 0.1, dm) * (1 - smoothstep(0.1, 0.2, dm)) * g * (1 - smoothstep(2.0, 2.5, np.abs(s)))
            rim_all = np.where(on, np.maximum(rim_all, rim), rim_all)
            stop = smoothstep(0.5, 2, arcT) * (1 - smoothstep(5, 7, arcT)) * (1 - smoothstep(1.8, 2.5, np.abs(s))) * 0.6
            stop_all = np.where(on, np.maximum(stop_all, stop), stop_all)
        return tr_all, rim_all, stop_all

    def lane_tracks(self, ln, x, y, px):
        """wheel tracks of the layer 1 / 2 lanes alone (no junction), from a lanes() result"""
        st1, st2, st3 = self.frame_noise(x, y, ln["dx"], ln["dy"], px)
        wob = (st1 - 0.5) * 0.07
        lf = ln["lf"]
        t = np.maximum(1 - smoothstep(0.03, 0.085, np.abs(lf - 0.32 - wob)), 1 - smoothstep(0.03, 0.085, np.abs(lf - 0.68 - wob)))
        return sat(t * (0.6 + 0.6 * st2) * (0.8 + 0.4 * st3)) * ln["on"]

    # ------------------------------------------------------------------ the road branch of the pixel shader
    def road(self, x, y, z, px, coverage=0.85):
        """-> dict: tracks, packed, rim, roadMask, on, jm (as the pixel shader computes them, gRoad = 1, near)"""
        z = np.broadcast_to(z, x.shape)
        ln = self.lanes(x, y, z)
        on, lf = ln["on"], ln["lf"]
        st1, st2, st3 = self.frame_noise(x, y, ln["dx"], ln["dy"], px)
        centre = 1 - np.abs(lf - 0.5) * 2
        wob = (st1 - 0.5) * 0.07
        d1 = np.abs(lf - 0.32 - wob)
        d2 = np.abs(lf - 0.68 - wob)
        t1 = 1 - smoothstep(0.03, 0.085, d1)
        t2 = 1 - smoothstep(0.03, 0.085, d2)
        tracks = sat(np.maximum(t1, t2) * (0.6 + 0.6 * st2) * (0.8 + 0.4 * st3)) * on
        packed = on * smoothstep(0.1, 0.55, centre)
        dm = np.minimum(d1, d2)
        rim = on * smoothstep(0.05, 0.1, dm) * (1 - smoothstep(0.1, 0.2, dm))
        jm = np.zeros(x.shape)
        if self.format >= 4:
            jm = smoothstep(0.51, 0.75, ln["jmask"])
            pf = smoothstep(0.251, 0.5, ln["jmask"])
            jt, jr, js = self.junction_tracks(x, y, ln["joff"], ln["jcnt"], jm, px, pf=pf)
            keep = 1 - jm
            tracks = np.maximum(tracks * keep, jt)
            rim = np.maximum(rim * keep, np.maximum(jr, jm * 0.3))
            packed = np.maximum(packed * keep, np.maximum(jm * 0.85, js))
            on = on * keep
        else:                                   # format 3: junction cells = trodden snow, no tracks
            junc = ln["junction_code"].astype(float)
            packed = np.maximum(packed, junc * 0.85)
            rim = np.maximum(rim, junc * 0.3)
            jm = junc
        c = coverage
        refill = smoothstep(0.9, 1.0, c)
        road_snow = c * (1 - packed * (0.5 - 0.3 * c)) * (1 - tracks * (0.97 - 0.45 * refill))
        road_snow += on * (1 - centre) * 0.25 * c
        road_snow += on * (1 - smoothstep(0.4, 3.2, ln["edge"])) * 0.22 * c
        return {"tracks": tracks, "packed": packed, "rim": rim, "roadSnow": road_snow, "on": on, "jm": jm,
                "jcnt": ln["jcnt"], "st1": st1}
