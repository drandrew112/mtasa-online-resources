// Builds data/network/base.json: the Sunline Rail network from GTA:SA's tracks*.dat, the physical
// track found in the map models (tools/survey/rails.json, made by tools/scan_rails.js) and the
// switches listed below.
//   node tools/scan_rails.js            (once, needs the game files)
//   node tools/build_network.js ["C:/Games/GTA San Andreas/data/Paths"]
//
// Tracks:
//   M  main line (tracks.dat, a loop LS - SF - LV - LS)
//   S  second track LS - SF (tracks4.dat), Cranberry hall track "2"
//   N  second track SF - LV - LS: follows the physical track 4 m outside the main line (rail centre
//      lines from the map models); where the map has none it is the main line shifted by 4 m and
//      drawn by the client (tag "drawn"); stretches where neither track was found in the models
//      (tunnels, bridges with other textures) are tagged "review". S and N together are a second
//      loop around the main line.
//   C  Cranberry spur (tracks2.dat): docks - Cranberry hall track "3" (buffer stop at its north end)
//   P4 Cranberry hall track "4"                                     (see EXTRA_TRACKS)
// The SF tram (tracks3.dat) is left out on purpose.
const fs = require('fs');
const path = require('path');

const dir = process.argv[2] || 'C:/Games/GTA San Andreas/data/Paths';
const OUT = path.join(__dirname, '..', 'data', 'network', 'base.json');
const RAILS = path.join(__dirname, 'survey', 'rails.json');
const MIN_GAP = 0.5;          // control points closer than this to a cut are dropped
const SECOND_OFFSET = 4.0;    // N: distance from the main line (left of +tp = outside of the loop)
const RAIL_TOP = 0.2;         // the models' rail top is 0.2 m above the network level
const SEAM = 60;              // gaps in the scanned second track shorter than this are model seams
const TURNOUT_TOE = 6;        // extra tracks: switch toe this far back from where the scanned branch begins
const TURNOUT_LEAD = 14;      // ... and the branch rejoins its scanned line this far from the toe
const UNSCANNED_IS_PHYSICAL = true;   // see the N ranges below

// Switch pairs: a diagonal from (track a @ x, y) to (track b @ x, y), a switch at both ends,
// thrown together. tags: "drawn" = no physical rails (the client draws them), "rwcore" = rw_core
// draws them while it runs, "review" = geometry to check in game. pts = inner points [x, y] of the
// diagonal measured in the map (z from the end points), instead of the default curve.
const CROSSOVERS = [
    // rw_core's crossovers (LS - SF)
    { id: 'W1', name: 'Switch W1/W2', a: [0, 2090, -1953.85], b: [3, 2050, -1957.9], tags: ['drawn', 'rwcore'] },
    { id: 'W3', name: 'Switch W3/W4', a: [3, 2012, -1957.9], b: [0, 1970, -1953.85], tags: ['drawn', 'rwcore'] },
    { id: 'W5', name: 'Switch W5/W6', a: [0, 1600, -1953.76], b: [3, 1560, -1957.68], tags: ['drawn', 'rwcore'] },
    { id: 'W7', name: 'Switch W7/W8', a: [3, 1600, -1957.73], b: [0, 1560, -1953.77], tags: ['drawn', 'rwcore'] },
    { id: 'W9', name: 'Switch W9/W10', a: [0, 987.22, -1539.43], b: [3, 957.03, -1512.86], tags: ['drawn', 'rwcore'] },
    { id: 'W11', name: 'Switch W11/W12', a: [3, 984.25, -1542.17], b: [0, 959.96, -1510.10], tags: ['drawn', 'rwcore'] },
    { id: 'W13', name: 'Switch W13/W14', a: [0, 703.69, -1271.37], b: [3, 669.61, -1249.95], tags: ['drawn', 'rwcore'] },
    { id: 'W15', name: 'Switch W15/W16', a: [3, 701.20, -1274.48], b: [0, 672.04, -1246.69], tags: ['drawn', 'rwcore'] },
    { id: 'W17', name: 'Switch W17/W18', a: [0, -1944.44, -130.0], b: [3, -1948.45, -90.0], tags: ['drawn', 'rwcore'] },
    { id: 'W19', name: 'Switch W19/W20', a: [3, -1948.39, -130.0], b: [0, -1944.47, -90.0], tags: ['drawn', 'rwcore'] },
    // Cranberry: hall track 3 runs on south of the spur's turnout and joins the main line (physical)
    // (inner points = the physical rail centre line from tools/survey/rails.json)
    { id: 'W21', name: 'Switch W21/W22', a: [1, -1934.1, 42], b: [0, -1944.5, -20], tags: [],
      pts: [[-1934.1, 30], [-1934.1, 18], [-1934.4, 12], [-1935.1, 8], [-1936.2, 4], [-1937.8, 0], [-1939.7, -4],
            [-1941.5, -8], [-1942.9, -12], [-1944.0, -16]] },
    // Yellow Bell: scissors west and east of the station (main <-> N)
    { id: 'W23', name: 'Switch W23/W24', a: [0, 1310, 2632.26], b: ['N', 1270, 2636.26], tags: ['drawn'] },
    { id: 'W25', name: 'Switch W25/W26', a: ['N', 1310, 2636.26], b: [0, 1270, 2632.26], tags: ['drawn'] },
    { id: 'W27', name: 'Switch W27/W28', a: [0, 1560, 2632.31], b: ['N', 1520, 2636.31], tags: ['drawn'] },
    { id: 'W29', name: 'Switch W29/W30', a: ['N', 1560, 2636.31], b: [0, 1520, 2632.31], tags: ['drawn'] },
    // Linden: scissors north and south of the station
    { id: 'W31', name: 'Switch W31/W32', a: [0, 2864.8, 1440], b: ['NC', 2868.8, 1400], tags: ['drawn'] },
    { id: 'W33', name: 'Switch W33/W34', a: ['NC', 2868.8, 1440], b: [0, 2864.8, 1400], tags: ['drawn'] },
    { id: 'W35', name: 'Switch W35/W36', a: [0, 2864.8, 1245], b: ['NC', 2868.4, 1205], tags: ['drawn'] },
    { id: 'W37', name: 'Switch W37/W38', a: ['NC', 2868.8, 1245], b: [0, 2860.5, 1205], tags: ['drawn'] },
];

// Further tracks given as polylines (x, y, z) with what their ends are joined to:
//   { type: 'buffer' } | { type: 'turnout', track, x, y, id, name } (a switch on that track)
const EXTRA_TRACKS = [
    // Cranberry hall track 4: leaves track 3 at W39 south of the hall (curve from the map scan),
    // runs along the east platform (axis from the bed profile) to its buffer stop
    { id: 'P4', kind: 'station', name: 'Cranberry track 4',
      pts: [[-1934.1, 52, 24.71], [-1933.5, 56, 24.71], [-1932.5, 60, 24.71], [-1931.2, 64, 24.71], [-1930.3, 68, 24.71],
            [-1930.25, 80, 24.71], [-1930.25, 100, 24.71], [-1930.15, 130, 24.71], [-1929.9, 140, 24.71],
            [-1929.55, 150, 24.71], [-1929.15, 160, 24.71], [-1928.8, 166, 24.71], [-1928.45, 173.9, 24.71]],
      start: { type: 'turnout', track: 1, id: 'W39', name: 'Switch W39', toe: 0, lead: 0 }, end: { type: 'buffer' } },
    // LV freight yard at Linden (centre lines from the map scan, rail level 9.82): a third track
    // beside the second track, a ladder from it and six sidings, all ending at buffer stops
    { id: 'Y1', kind: 'yard', name: 'LV yard track 1',
      pts: yard([[2785.6, 1826], [2786.9, 1821.5], [2787.6, 1819.8], [2788.6, 1815.8], [2789, 1811.8], [2789, 1807.5],
                 [2789, 1803.5], [2789, 1795.8], [2789, 1782.8], [2789, 1762.8], [2789, 1746.8], [2789, 1738.8]]),
      start: { type: 'turnout', track: 'NC', id: 'W41', name: 'Switch W41' }, end: { type: 'buffer' } },
    { id: 'Y2', kind: 'yard', name: 'LV yard ladder / track 6',
      pts: yard([[2789, 1803], [2790.7, 1800.3], [2791.6, 1795.8], [2793.0, 1791.9], [2794.6, 1787.9], [2796.4, 1783.0],
                 [2798.4, 1777.5], [2799.8, 1773.8], [2801.1, 1770.0], [2802.9, 1765.0], [2805.6, 1762.0], [2808.6, 1757.9],
                 [2811.4, 1754.8], [2814.2, 1751.5], [2818.1, 1746.9], [2821.9, 1742.3], [2825.8, 1737.7], [2828.3, 1734.6],
                 [2831.7, 1730.6], [2834.3, 1727.5], [2836.4, 1725.1], [2839.3, 1721.6], [2842.5, 1717.8], [2845.1, 1714.7],
                 [2848.9, 1710.1], [2852.3, 1706.1], [2854.9, 1703.0], [2856.9, 1700.6], [2859.8, 1697.1], [2862.4, 1694.0],
                 [2865.0, 1691.0], [2868.2, 1687.1], [2870.8, 1684.1], [2874.6, 1679.5], [2878.5, 1674.9], [2882.3, 1670.3],
                 [2886.2, 1665.7], [2889.6, 1661.0], [2891.9, 1656.2], [2893.4, 1651.5], [2894.2, 1646.8], [2894.6, 1642.1],
                 [2894.6, 1631.5], [2894.6, 1611.5], [2894.6, 1593.5]]),
      start: { type: 'turnout', track: 'Y1', id: 'W43', name: 'Switch W43' }, end: { type: 'buffer' } },
    { id: 'Y3', kind: 'yard', name: 'LV yard track 2',
      pts: yard([[2804.3, 1762.3], [2804.0, 1762.0], [2805.6, 1757.8], [2806.9, 1754.0], [2808.3, 1750.3], [2809.8, 1746.2],
                 [2811.2, 1742.5], [2811.3, 1737.5], [2811.4, 1733.4], [2811.2, 1724.9], [2811.2, 1700.9], [2811.2, 1668.9],
                 [2811.2, 1636.9]]),
      start: { type: 'turnout', track: 'Y2', id: 'W45', name: 'Switch W45' }, end: { type: 'buffer' } },
    { id: 'Y4', kind: 'yard', name: 'LV yard track 3',
      pts: yard([[2811.25, 1741.5], [2812.2, 1739.5], [2813.8, 1735.2], [2815.2, 1731.5], [2816.5, 1727.7], [2818.2, 1723.0],
                 [2819.6, 1719.3], [2821.0, 1715.5], [2822.3, 1711.7], [2824.4, 1706.1], [2825.8, 1701.9], [2826.7, 1697.4],
                 [2826.9, 1692.9], [2826.9, 1680.9], [2826.9, 1660.9], [2826.9, 1636.9]]),
      start: { type: 'turnout', track: 'Y3', id: 'W47', name: 'Switch W47' }, end: { type: 'buffer' } },
    { id: 'Y5', kind: 'yard', name: 'LV yard track 4',
      pts: yard([[2834.9, 1726.6], [2835.1, 1724.0], [2837.3, 1720.0], [2838.7, 1716.1], [2840.1, 1712.0], [2841.5, 1707.2],
                 [2842.4, 1702.5], [2843.0, 1696.9], [2843.2, 1692.9], [2843.2, 1680.8], [2843.2, 1660.8], [2843.2, 1634.8]]),
      start: { type: 'turnout', track: 'Y2', id: 'W49', name: 'Switch W49' }, end: { type: 'buffer' } },
    { id: 'Y6', kind: 'yard', name: 'LV yard track 5',
      pts: yard([[2855.4, 1702.0], [2855.7, 1699.5], [2857.9, 1695.5], [2859.2, 1691.6], [2860.6, 1687.5], [2862.1, 1683.4],
                 [2863.5, 1679.6], [2864.5, 1676.6], [2866.1, 1672.4], [2867.5, 1668.6], [2868.8, 1664.9], [2870.5, 1660.2],
                 [2871.9, 1656.4], [2873.3, 1652.7], [2875.3, 1647.0], [2876.7, 1643.3], [2878.1, 1639.1], [2879.0, 1634.5],
                 [2879.2, 1630.0], [2879.2, 1614.0], [2879.2, 1594.0]]),
      start: { type: 'turnout', track: 'Y2', id: 'W51', name: 'Switch W51' }, end: { type: 'buffer' } },
    { id: 'Y7', kind: 'yard', name: 'LV yard track 7',
      pts: yard([[2863.8, 1678.6], [2863.0, 1676.1], [2863.6, 1674.7], [2863.7, 1670.5], [2863.6, 1666.4], [2863.5, 1658.0],
                 [2863.5, 1630.0], [2863.5, 1594.0]]),
      start: { type: 'turnout', track: 'Y6', id: 'W53', name: 'Switch W53' }, end: { type: 'buffer' } },
];
function yard(pts) { return pts.map(p => [p[0], p[1], 9.82]); }

const TRACKS = {
    0: { file: 'tracks.dat', prefix: 'M', kind: 'main', name: 'Main line' },
    3: { file: 'tracks4.dat', prefix: 'S', kind: 'second', name: 'Second track' },
    1: { file: 'tracks2.dat', prefix: 'C', kind: 'spur', name: 'Cranberry spur' },
};

const r2 = v => Math.round(v * 100) / 100;
const hyp = (x, y) => Math.sqrt(x * x + y * y);
const norm = (x, y) => { const l = hyp(x, y) || 1; return [x / l, y / l]; };

function initTrack(t) {
    const a = t.nodes[0], b = t.nodes[t.nodes.length - 1];
    if (t.closed === undefined) t.closed = hyp(a[0] - b[0], a[1] - b[1]) < 30;
    t.cum = [0];
    for (let i = 1; i < t.nodes.length; i++)
        t.cum[i] = t.cum[i - 1] + hyp(t.nodes[i][0] - t.nodes[i - 1][0], t.nodes[i][1] - t.nodes[i - 1][1]);
    t.len = t.cum[t.nodes.length - 1] + (t.closed ? hyp(a[0] - b[0], a[1] - b[1]) : 0);
    t.cuts = [];
    t.endLinks = t.endLinks || {};
}

for (const [id, t] of Object.entries(TRACKS)) {
    const lines = fs.readFileSync(path.join(dir, t.file), 'utf8').trim().split(/\r?\n/);
    t.id = Number(id);
    t.nodes = lines.slice(1).map(s => s.trim().split(/\s+/).map(Number).slice(0, 3));
    initTrack(t);
}

function nodeAt(t, i) { return t.nodes[(i + t.nodes.length) % t.nodes.length]; }

// closest point of a track to (x, y) -> { tp, x, y, z, dir:[dx,dy] }
function project(t, x, y) {
    let best = null;
    const segs = t.closed ? t.nodes.length : t.nodes.length - 1;
    for (let i = 0; i < segs; i++) {
        const p = t.nodes[i], q = nodeAt(t, i + 1);
        const dx = q[0] - p[0], dy = q[1] - p[1], l2 = dx * dx + dy * dy;
        let f = l2 > 0 ? ((x - p[0]) * dx + (y - p[1]) * dy) / l2 : 0;
        f = Math.max(0, Math.min(1, f));
        const px = p[0] + dx * f, py = p[1] + dy * f, d = hyp(x - px, y - py);
        if (!best || d < best.d)
            best = { d, tp: t.cum[i] + f * Math.sqrt(l2), x: px, y: py, z: p[2] + (q[2] - p[2]) * f, dir: norm(dx, dy) };
    }
    return best;
}

// point at a tp -> { x, y, z, dir }
function pointAt(t, tp) {
    if (t.closed) tp = ((tp % t.len) + t.len) % t.len;
    tp = Math.max(0, Math.min(t.len, tp));
    const n = t.nodes.length;
    for (let i = 0; i < (t.closed ? n : n - 1); i++) {
        const segLen = (i + 1 < n ? t.cum[i + 1] : t.len) - t.cum[i];
        if (tp <= t.cum[i] + segLen || i === (t.closed ? n : n - 1) - 1) {
            const p = t.nodes[i], q = nodeAt(t, i + 1);
            const f = segLen > 0 ? (tp - t.cum[i]) / segLen : 0;
            return { x: p[0] + (q[0] - p[0]) * f, y: p[1] + (q[1] - p[1]) * f, z: p[2] + (q[2] - p[2]) * f,
                dir: norm(q[0] - p[0], q[1] - p[1]), tp };
        }
    }
}

// cubic Hermite from P (tangent tp) to Q (tangent tq), 2D tangents, z linear-smooth; inner points
function hermite(P, tpv, Q, tqv, count) {
    const L = hyp(Q.x - P.x, Q.y - P.y);
    const pts = [];
    for (let k = 1; k < count; k++) {
        const u = k / count, u2 = u * u, u3 = u2 * u;
        const h00 = 2 * u3 - 3 * u2 + 1, h10 = u3 - 2 * u2 + u, h01 = -2 * u3 + 3 * u2, h11 = u3 - u2;
        const zs = 3 * u2 - 2 * u3;
        pts.push([P.x * h00 + tpv[0] * L * h10 + Q.x * h01 + tqv[0] * L * h11,
                  P.y * h00 + tpv[1] * L * h10 + Q.y * h01 + tqv[1] * L * h11,
                  P.z + (Q.z - P.z) * zs]);
    }
    return pts;
}

// centripetal Catmull-Rom through a closed / open point list, every ~step metres (same as
// shared/geometry.lua) -> [[x, y, z], ...]
function catmull(P, closed, step) {
    const n = P.length, out = [];
    const at = i => closed ? P[(i + n) % n] : P[Math.max(0, Math.min(n - 1, i))];
    const knot = (a, b) => Math.max(Math.hypot(b[0] - a[0], b[1] - a[1], b[2] - a[2]), 1e-4) ** 0.5;
    const lerp = (a, b, ta, tb, t) => { const u = (t - ta) / (tb - ta); return [0, 1, 2].map(k => a[k] + (b[k] - a[k]) * u); };
    const spans = closed ? n : n - 1;
    for (let k = 0; k < spans; k++) {
        const p0 = at(k - 1), p1 = at(k), p2 = at(k + 1), p3 = at(k + 2);
        const t0 = 0, t1 = knot(p0, p1), t2 = t1 + knot(p1, p2), t3 = t2 + knot(p2, p3);
        const cnt = Math.max(1, Math.ceil(Math.hypot(p2[0] - p1[0], p2[1] - p1[1]) / step));
        for (let j = 0; j < cnt; j++) {
            const t = t1 + (t2 - t1) * j / cnt;
            const a1 = lerp(p0, p1, t0, t1, t), a2 = lerp(p1, p2, t1, t2, t), a3 = lerp(p2, p3, t2, t3, t);
            const b1 = lerp(a1, a2, t0, t2, t), b2 = lerp(a2, a3, t1, t3, t);
            out.push(lerp(b1, b2, t1, t2, t));
        }
    }
    if (!closed) out.push(P[n - 1]);
    return out;
}

// ------------------------------------------------------------------ physical rails (scan)
const rails = JSON.parse(fs.readFileSync(RAILS, 'utf8')).segs;
const RCELL = 20, rgrid = new Map();
rails.forEach((s, i) => {
    const k = Math.floor((s[0] + s[3]) / 2 / RCELL) + ',' + Math.floor((s[1] + s[4]) / 2 / RCELL);
    if (!rgrid.has(k)) rgrid.set(k, []);
    rgrid.get(k).push(i);
});
// nearest scanned rail centre line -> { d, x, y, z (network level) }
function nearRail(x, y) {
    let best = { d: 1e9 };
    const cx = Math.floor(x / RCELL), cy = Math.floor(y / RCELL);
    for (let ox = -2; ox <= 2; ox++) for (let oy = -2; oy <= 2; oy++) for (const i of rgrid.get((cx + ox) + ',' + (cy + oy)) || []) {
        const s = rails[i], dx = s[3] - s[0], dy = s[4] - s[1], l2 = dx * dx + dy * dy;
        let f = l2 ? ((x - s[0]) * dx + (y - s[1]) * dy) / l2 : 0;
        f = Math.max(0, Math.min(1, f));
        const px = s[0] + dx * f, py = s[1] + dy * f, d = Math.hypot(x - px, y - py);
        if (d < best.d) best = { d, x: px, y: py, z: s[2] + (s[5] - s[2]) * f - RAIL_TOP };
    }
    return best;
}

// ------------------------------------------------------------------ N: second track SF - LV - LS
const N_RUNS = [];
{
    const main = TRACKS[0], S = TRACKS[3];
    const sEnd = S.nodes[S.nodes.length - 1];          // Cranberry hall, track 2
    const sStart = S.nodes[0];                          // NE Los Santos
    const dense = catmull(main.nodes, true, 1);
    const dcum = [0];
    for (let i = 1; i < dense.length; i++) dcum[i] = dcum[i - 1] + Math.hypot(dense[i][0] - dense[i - 1][0], dense[i][1] - dense[i - 1][1]);
    const dlen = dcum[dense.length - 1] + Math.hypot(dense[0][0] - dense[dense.length - 1][0], dense[0][1] - dense[dense.length - 1][1]);
    const closest = (x, y) => { let b = 0, bd = 1e9; dense.forEach((p, i) => { const d = Math.hypot(p[0] - x, p[1] - y); if (d < bd) { bd = d; b = i; } }); return b; };
    const i0 = closest(sEnd[0], sEnd[1]), i1 = closest(sStart[0], sStart[1]);
    let run = dcum[i1] - dcum[i0];
    if (run < 0) run += dlen;
    // samples every 5 m along the main line, 4 m to its left
    const samples = [];
    let i = i0, acc = 0;
    const N = dense.length;
    while (acc <= run) {
        const p = dense[i % N], q = dense[(i + 1) % N];
        const [tx, ty] = norm(q[0] - p[0], q[1] - p[1]);
        const lx = -ty, ly = tx;
        let best = null;
        for (let o = 3.0; o <= 5.01; o += 0.1) {
            const r = nearRail(p[0] + lx * o, p[1] + ly * o);
            if (r.d < 0.3 && (!best || r.d < best.d)) best = r;
        }
        const mainHere = nearRail(p[0], p[1]).d < 0.3;
        samples.push(best ? { x: best.x, y: best.y, z: best.z, phys: true, mainScan: mainHere, s: acc }
            : { x: p[0] + lx * SECOND_OFFSET, y: p[1] + ly * SECOND_OFFSET, z: p[2], phys: false, mainScan: mainHere, s: acc });
        // advance 5 m
        let adv = 0;
        while (adv < 5 && acc + adv <= run) {
            const a = dense[i % N], b = dense[(i + 1) % N];
            adv += Math.hypot(b[0] - a[0], b[1] - a[1]);
            i++;
        }
        acc += adv;
    }
    // ranges: physical / single (main scanned, no second track: drawn) / unknown (review)
    const ranges = [];
    for (const smp of samples) {
        // neither track in the scan: tunnel / bridge models with other textures. Checked in game
        // (2026-10-04: the tunnel north of Cranberry and both SF bridges are double track).
        const type = smp.phys ? 'phys' : (smp.mainScan ? 'drawn' : (UNSCANNED_IS_PHYSICAL ? 'phys' : 'review'));
        const last = ranges[ranges.length - 1];
        if (last && last.type === type) last.b = smp.s; else ranges.push({ type, a: smp.s, b: smp.s });
    }
    // short stretches between two of the same kind are seams of the models
    for (let k = 1; k + 1 < ranges.length; k++) {
        const r = ranges[k];
        if (r.b - r.a < SEAM && ranges[k - 1].type === ranges[k + 1].type) r.type = ranges[k - 1].type;
    }
    // a short unknown stretch next to a drawn one (where a model ends) is drawn too
    for (let k = 0; k < ranges.length; k++) {
        const r = ranges[k];
        if (r.type === 'review' && r.b - r.a < SEAM && ((ranges[k - 1] || {}).type === 'drawn' || (ranges[k + 1] || {}).type === 'drawn')) r.type = 'drawn';
    }
    const merged = [];
    for (const r of ranges) {
        const last = merged[merged.length - 1];
        if (last && last.type === r.type) last.b = r.b; else merged.push({ ...r });
    }
    // Single-track stretches ("drawn" ranges): the map has no second track there because the main
    // line itself swings over onto the outer alignment (checked in game 2026-10-04: Yellow Bell
    // east - fences / a level crossing, the NE curve of LV - a single-track tunnel). So the second
    // track is split into runs N, NB, NC...; each run ends at a switch where the main line has
    // joined its alignment.
    const ids = ['N', 'NB', 'NC', 'ND', 'NE'];
    const runs = [];
    let cur = null;
    for (const r of merged) {
        if (r.type === 'drawn') { if (cur) { cur.endGap = true; cur = null; } continue; }
        if (!cur) { cur = { a: r.a, b: r.b, startGap: runs.length > 0 }; runs.push(cur); } else cur.b = r.b;
    }
    // the main line point where it has joined the second track's line, walking from the run end P
    // in direction d (along the main line)
    const mainIdxNear = (x, y) => closest(x, y);
    function mergePoint(P, d) {
        let i = mainIdxNear(P.x, P.y);
        const step = Math.sign(((dense[(i + 1) % N][0] - dense[i][0]) * d[0] + (dense[(i + 1) % N][1] - dense[i][1]) * d[1])) || 1;
        for (let k = 0; k < 120; k++) {
            const q = dense[(i + N) % N];
            const lat = Math.abs((q[0] - P.x) * -d[1] + (q[1] - P.y) * d[0]);
            const along = (q[0] - P.x) * d[0] + (q[1] - P.y) * d[1];
            if (along > 2 && lat < 0.25) return { x: q[0], y: q[1], z: q[2] };
            if (process.env.DEBUG_MERGE && k % 10 === 0) console.log('    merge?', k, q[0].toFixed(1), q[1].toFixed(1), 'lat', lat.toFixed(2), 'along', along.toFixed(1));
            i += step;
        }
        console.log('  no merge point after', P.x.toFixed(1), P.y.toFixed(1), 'dir', d.map(v => v.toFixed(2)).join(','));
        return null;
    }
    runs.forEach((run, k) => {
        let smp = samples.filter(x => x.s >= run.a && x.s <= run.b);
        // next to a single-track stretch the main line already bends over and the last samples can
        // catch the curved rail: drop 15 m there
        if (run.endGap) smp = smp.slice(0, -3);
        if (run.startGap) smp = smp.slice(3);
        const pts = smp.filter((_, j) => j % 2 === 0 || j === smp.length - 1).map(x => [x.x, x.y, x.z]);
        const id = ids[k];
        let startSpec = { type: 'node', node: 'E_CR' }, endSpec = { type: 'node', node: 'E_NE' };
        if (k === 0) pts[0] = sEnd.slice();
        if (k === runs.length - 1) pts[pts.length - 1] = sStart.slice();
        if (run.endGap) {
            const a = smp[smp.length - 3], b = smp[smp.length - 1];
            const m = mergePoint(b, norm(b.x - a.x, b.y - a.y));
            pts.push([m.x, m.y, m.z]);
            endSpec = { type: 'turnout', track: 0, id: 'J' + id + 'b', group: 'J' + id + 'b', name: 'Single track (' + id + ' end)', toe: 0, lead: 0 };
        }
        if (run.startGap) {
            const a = smp[2], b = smp[0];
            const m = mergePoint(b, norm(b.x - a.x, b.y - a.y));
            pts.unshift([m.x, m.y, m.z]);
            startSpec = { type: 'turnout', track: 0, id: 'J' + id + 'a', group: 'J' + id + 'a', name: 'Single track (' + id + ' start)', toe: 0, lead: 0 };
        }
        N_RUNS.push({ id, kind: 'second', name: 'Second track', pts, start: startSpec, end: endSpec, prefix: id === 'N' ? 'N' : id });
    });
    console.log('N ranges:');
    for (const r of merged) console.log(`  ${(r.type === 'drawn' ? 'single' : r.type).padEnd(6)} s ${r.a.toFixed(0).padStart(5)} - ${r.b.toFixed(0).padStart(5)} (${(r.b - r.a).toFixed(0)} m)`);
    console.log('N runs:', N_RUNS.map(r => r.id + ' ' + r.pts.length + ' pts').join(', '));
}

const segments = [];
const nodes = [];
const groups = [];
const crossings = [];
const nodeById = {};

function addNode(n) { nodes.push(n); nodeById[n.id] = n; return n; }

// A switch point on a track at tp. `branchDir` = direction the branch leaves the point.
// The track side the branch leans towards is `normal`, the other one `trunk`.
function cutSwitch(t, tp, nodeId, branchEnd, branchDir, extra) {
    const p = pointAt(t, tp);
    const n = addNode(Object.assign({ id: nodeId, type: 'switch', x: r2(p.x), y: r2(p.y), z: r2(p.z), reverse: branchEnd }, extra || {}));
    t.cuts.push({ tp: p.tp, node: n, pt: [p.x, p.y, p.z], role: (branchDir[0] * p.dir[0] + branchDir[1] * p.dir[1]) > 0 ? 'ahead' : 'behind' });
    return p;
}

// a plain joint on a track (to change tags between two stretches)
function cutLink(t, tp, nodeId) {
    const p = pointAt(t, tp);
    const n = addNode({ id: nodeId, type: 'link', x: r2(p.x), y: r2(p.y), z: r2(p.z), ends: [] });
    t.cuts.push({ tp: p.tp, node: n, pt: [p.x, p.y, p.z] });
}


// ------------------------------------------------------------------ ends
// S and N meet at both ends (Cranberry hall track 2, NE Los Santos): one second-track loop
{
    const S = TRACKS[3];
    const a = S.nodes[S.nodes.length - 1], b = S.nodes[0];
    addNode({ id: 'E_CR', type: 'link', x: r2(a[0]), y: r2(a[1]), z: r2(a[2]), ends: [] });
    addNode({ id: 'E_NE', type: 'link', x: r2(b[0]), y: r2(b[1]), z: r2(b[2]), ends: [] });
    S.endLinks = { start: 'E_NE', end: 'E_CR' };
}
// the spur: buffer stops at the docks and at the north end of Cranberry hall track 3
{
    const C = TRACKS[1], a = C.nodes[0], b = C.nodes[C.nodes.length - 1];
    addNode({ id: 'B_SP', type: 'buffer', x: r2(a[0]), y: r2(a[1]), z: r2(a[2]), ends: [] });
    addNode({ id: 'B_C3', type: 'buffer', x: r2(b[0]), y: r2(b[1]), z: r2(b[2]), ends: [] });
    C.endLinks = { start: 'B_SP', end: 'B_C3' };
}

// ------------------------------------------------------------------ extra tracks
for (const x of [...N_RUNS, ...EXTRA_TRACKS]) {
    const t = { id: x.id, prefix: x.prefix || x.id, kind: x.kind || 'other', name: x.name, nodes: x.pts, closed: false, tags: x.tags };
    initTrack(t);
    for (const [end, spec] of [['start', x.start], ['end', x.end]]) {
        const p = end === 'start' ? t.nodes[0] : t.nodes[t.nodes.length - 1];
        if (spec.type === 'node') { t.endLinks[end] = spec.node; continue; }
        const nid = (spec.type === 'buffer' ? 'B_' : 'E_') + x.id + (end === 'start' ? 'a' : 'b');
        if (spec.type === 'buffer') {
            addNode({ id: nid, type: 'buffer', x: r2(p[0]), y: r2(p[1]), z: r2(p[2]), ends: [] });
        } else {
            // the track leaves a switch on another track: the switch node replaces the end node
            const host = TRACKS[spec.track];
            let q = project(host, p[0], p[1]);
            // The scanned branch starts where it is already off the host: put the switch toe TOE
            // metres back along the host and lead the branch out tangentially (Hermite) to its first
            // point LEAD metres away, so there is no kink at the switch.
            // (toe 0 + lead 0: the points already start with a measured lead-in, keep them)
            if (!(spec.toe === 0 && spec.lead === 0)) {
                const list = t.nodes;
                const away = end === 'start' ? list : list.slice().reverse();
                const sgn = ((away[1][0] - q.x) * q.dir[0] + (away[1][1] - q.y) * q.dir[1]) > 0 ? 1 : -1;
                const toe = pointAt(host, q.tp - sgn * (spec.toe ?? TURNOUT_TOE));
                let k = 1;
                while (k < away.length - 1 && Math.hypot(away[k][0] - toe.x, away[k][1] - toe.y) < (spec.lead ?? TURNOUT_LEAD)) k++;
                const P = away[k], Pn = away[Math.min(k + 1, away.length - 1)];
                const tb = norm(Pn[0] - P[0], Pn[1] - P[1]);
                const curve = hermite(toe, [toe.dir[0] * sgn, toe.dir[1] * sgn], { x: P[0], y: P[1], z: P[2] }, tb, 6);
                const rebuilt = [[toe.x, toe.y, toe.z], ...curve, ...away.slice(k)];
                t.nodes = end === 'start' ? rebuilt : rebuilt.reverse();
                initTrack(t);
                q = project(host, toe.x, toe.y);
            }
            p[0] = q.x; p[1] = q.y; p[2] = q.z;           // the track starts exactly on the switch
            const inner = end === 'start' ? t.nodes[1] : t.nodes[t.nodes.length - 2];
            cutSwitch(host, q.tp, spec.id, null, norm(inner[0] - q.x, inner[1] - q.y), { group: spec.group || spec.id });
            nodeById[spec.id].pendingBranch = { track: x.id, end };
            if (!groups.find(g => g.id === (spec.group || spec.id))) groups.push({ id: spec.group || spec.id, name: spec.name, nodes: [] });
            groups.find(g => g.id === (spec.group || spec.id)).nodes.push(spec.id);
            addNode({ id: nid, type: 'link', x: r2(q.x), y: r2(q.y), z: r2(q.z), ends: [], placeholder: spec.id });
        }
        t.endLinks[end] = nid;
    }
    TRACKS[x.id] = t;
}

// ------------------------------------------------------------------ crossovers
const diagonals = [];
for (const c of CROSSOVERS) {
    const A = TRACKS[c.a[0]], B = TRACKS[c.b[0]];
    const pa = project(A, c.a[1], c.a[2]), pb = project(B, c.b[1], c.b[2]);
    const u = norm(pb.x - pa.x, pb.y - pa.y);
    const sa = (pa.dir[0] * u[0] + pa.dir[1] * u[1]) > 0 ? 1 : -1;
    const sb = (pb.dir[0] * u[0] + pb.dir[1] * u[1]) > 0 ? 1 : -1;
    const ta = [pa.dir[0] * sa, pa.dir[1] * sa], tb = [pb.dir[0] * sb, pb.dir[1] * sb];
    const segId = 'X_' + c.id;
    const inner = c.pts ? c.pts.map((p, k) => [p[0], p[1], pa.z + (pb.z - pa.z) * (k + 1) / (c.pts.length + 1)])
        : hermite(pa, ta, pb, tb, c.div || 8);
    const seg = { id: segId, kind: 'crossover', name: c.name, a: c.id + 'a', b: c.id + 'b', tags: c.tags || [],
        pts: [[pa.x, pa.y, pa.z], ...inner, [pb.x, pb.y, pb.z]] };
    segments.push(seg);
    diagonals.push(seg);
    cutSwitch(A, pa.tp, c.id + 'a', segId + '@a', ta, { group: c.id });
    cutSwitch(B, pb.tp, c.id + 'b', segId + '@b', [-tb[0], -tb[1]], { group: c.id });
    groups.push({ id: c.id, name: c.name, nodes: [c.id + 'a', c.id + 'b'] });
}

// ------------------------------------------------------------------ cut the tracks
function endRef(segId, end) { return segId + '@' + end; }

// the segment starting at a cut ("after") / ending at it ("before") is normal or trunk
function setRole(cut, side, ref) {
    const n = cut.node;
    if (n.type === 'link') { n.ends.push(ref); return; }
    // role 'ahead': branch leans towards increasing tp -> the segment after the cut is normal
    const normalSide = cut.role === 'ahead' ? 'after' : 'before';
    if (side === normalSide) n.normal = ref; else n.trunk = ref;
}

for (const t of Object.values(TRACKS)) {
    const cuts = t.cuts.sort((a, b) => a.tp - b.tp);
    const pieces = [];   // { from: cut|null, to: cut|null }
    if (t.closed) {
        for (let k = 0; k < cuts.length; k++) pieces.push({ from: cuts[k], to: cuts[(k + 1) % cuts.length] });
    } else {
        let prev = null;
        for (const c of cuts) { pieces.push({ from: prev, to: c }); prev = c; }
        pieces.push({ from: prev, to: null });
    }
    pieces.forEach((pc, k) => {
        const segId = t.prefix + String(k + 1).padStart(2, '0');
        const tpFrom = pc.from ? pc.from.tp : 0;
        let tpTo = pc.to ? pc.to.tp : t.len;
        if (t.closed && tpTo <= tpFrom) tpTo += t.len;
        const pts = [pc.from ? pc.from.pt : t.nodes[0]];
        const n = t.nodes.length;
        const laps = t.closed ? 2 : 1;
        for (let lap = 0; lap < laps; lap++) {
            for (let i = 0; i < n; i++) {
                const tp = t.cum[i] + lap * t.len;
                if (tp > tpFrom + MIN_GAP && tp < tpTo - MIN_GAP) pts.push(t.nodes[i]);
            }
        }
        pts.push(pc.to ? pc.to.pt : t.nodes[n - 1]);
        const tags = t.tagsAt ? t.tagsAt((tpFrom + tpTo) / 2) : (t.tags || []);
        const seg = { id: segId, kind: t.kind, name: t.name, a: null, b: null, tags, pts };
        for (const [end, cut, side] of [['a', pc.from, 'after'], ['b', pc.to, 'before']]) {
            const ref = endRef(segId, end);
            if (cut) {
                seg[end] = cut.node.id;
                setRole(cut, side, ref);
            } else {
                const nid = t.endLinks[end === 'a' ? 'start' : 'end'];
                const node = nodeById[nid];
                if (node.placeholder) {
                    // the track starts at a switch on another track: it is that switch's branch
                    seg[end] = node.placeholder;
                    nodeById[node.placeholder].reverse = ref;
                    node.drop = true;
                } else {
                    seg[end] = nid;
                    node.ends.unshift(ref);
                }
            }
        }
        segments.push(seg);
    });
}
for (let i = nodes.length - 1; i >= 0; i--) if (nodes[i].drop) nodes.splice(i, 1);
for (const n of nodes) { delete n.pendingBranch; delete n.placeholder; }

// ------------------------------------------------------------------ crossings (scissors)
function segIntersect(p, q, r, s) {
    const d = (q[0] - p[0]) * (s[1] - r[1]) - (q[1] - p[1]) * (s[0] - r[0]);
    if (Math.abs(d) < 1e-9) return false;
    const u = ((r[0] - p[0]) * (s[1] - r[1]) - (r[1] - p[1]) * (s[0] - r[0])) / d;
    const v = ((r[0] - p[0]) * (q[1] - p[1]) - (r[1] - p[1]) * (q[0] - p[0])) / d;
    return u > 0 && u < 1 && v > 0 && v < 1;
}
for (let i = 0; i < diagonals.length; i++) {
    for (let j = i + 1; j < diagonals.length; j++) {
        const A = diagonals[i].pts, B = diagonals[j].pts;
        let hit = false;
        for (let a = 0; a + 1 < A.length && !hit; a++)
            for (let b = 0; b + 1 < B.length && !hit; b++)
                if (segIntersect(A[a], A[a + 1], B[b], B[b + 1])) hit = true;
        if (hit) crossings.push([diagonals[i].id, diagonals[j].id]);
    }
}

// ------------------------------------------------------------------ write
const order = { main: 0, second: 1, spur: 2, station: 3, yard: 4, crossover: 5, other: 6 };
segments.sort((a, b) => ((order[a.kind] ?? 9) - (order[b.kind] ?? 9)) || a.id.localeCompare(b.id, 'en', { numeric: true }));
for (const n of nodes) if (n.type !== 'switch' && n.ends && n.ends.length === 0) delete n.ends;

function fmtPts(pts) {
    const rows = [];
    for (let i = 0; i < pts.length; i += 4)
        rows.push('        ' + pts.slice(i, i + 4).map(p => `[${r2(p[0])}, ${r2(p[1])}, ${r2(p[2])}]`).join(', '));
    return '[\n' + rows.join(',\n') + '\n      ]';
}
let out = '{\n  "about": "GENERATED by tools/build_network.js (GTA:SA tracks*.dat + map model rail scan + switch list). Rebuild instead of editing; extra tracks go into their own files.",\n';
out += '  "segments": [\n' + segments.map(s => {
    const head = { id: s.id, kind: s.kind, name: s.name, a: s.a, b: s.b, tags: s.tags };
    return '    { ' + Object.entries(head).map(([k, v]) => `"${k}": ${JSON.stringify(v)}`).join(', ') + ',\n      "pts": ' + fmtPts(s.pts) + ' }';
}).join(',\n') + '\n  ],\n';
out += '  "nodes": [\n' + nodes.map(n => '    ' + JSON.stringify(n)).join(',\n') + '\n  ],\n';
out += '  "groups": [\n' + groups.map(g => '    ' + JSON.stringify(g)).join(',\n') + '\n  ],\n';
out += '  "crossings": ' + JSON.stringify(crossings) + '\n}\n';
fs.mkdirSync(path.dirname(OUT), { recursive: true });
fs.writeFileSync(OUT, out);

// report
const len = s => { let L = 0; for (let i = 1; i < s.pts.length; i++) L += Math.hypot(s.pts[i][0] - s.pts[i - 1][0], s.pts[i][1] - s.pts[i - 1][1], s.pts[i][2] - s.pts[i - 1][2]); return L; };
for (const s of segments) console.log(s.id.padEnd(7), s.kind.padEnd(9), String(s.pts.length).padStart(4), 'pts', len(s).toFixed(0).padStart(6), 'm', s.a, '->', s.b, s.tags.join(','));
console.log('nodes', nodes.length, 'groups', groups.length, 'crossings', JSON.stringify(crossings));
for (const n of nodes) if (n.type === 'switch' && !(n.trunk && n.normal && n.reverse)) console.log('INCOMPLETE switch', JSON.stringify(n));
console.log('written', OUT, out.length, 'bytes');
