// Scans the whole map for physical railway track: every placed model (text IPLs + binary IPLs in
// gta3.img) whose DFF has track-bed geometry (textures TEXES: a quad spanning u 0..1 across the
// track, sometimes split into strips) contributes the bed's centre line (the u = 0.5 iso-line) in
// world coordinates.
// (cunte_traintraxx2 is only used by LOD models, the LOD models are skipped.)
//   node tools/scan_rails.js ["C:/Games/GTA San Andreas"]  -> tools/survey/rails.json
//   { segs: [ [x1, y1, z1, x2, y2, z2, model], ... ] }   z = rail top (bed + 0.2 m)
const fs = require('fs');
const path = require('path');
const { readImg, readDff } = require('./rwdff.js');

const GTA = process.argv[2] || 'C:/Games/GTA San Andreas';
const OUT = path.join(__dirname, 'survey', 'rails.json');
const TEXES = ['ws_traintrax1', 'ws_traxonconcdirty'];
const RAIL_TOP = 0.2;            // rail head above the bed quad (measured in TRNTRK7_LAS)

function files(dir, ext, out = []) {
    for (const f of fs.readdirSync(dir)) {
        const p = path.join(dir, f);
        if (fs.statSync(p).isDirectory()) files(p, ext, out);
        else if (f.toLowerCase().endsWith(ext)) out.push(p);
    }
    return out;
}

// ---------------------------------------------------------------- IDE: id -> model name
const names = new Map();
for (const f of files(path.join(GTA, 'data'), '.ide')) {
    let sec = null;
    for (let line of fs.readFileSync(f, 'latin1').split(/\r?\n/)) {
        line = line.replace(/#.*/, '').trim();
        if (!line) continue;
        if (/^(objs|tobj|anim|cars|peds|weap|hier|txdp|2dfx|path)$/i.test(line)) { sec = line.toLowerCase(); continue; }
        if (/^end$/i.test(line)) { sec = null; continue; }
        if (sec === 'objs' || sec === 'tobj' || sec === 'anim') {
            const p = line.split(/\s*,\s*/);
            names.set(+p[0], p[1].toLowerCase());
        }
    }
}

// ---------------------------------------------------------------- IPL instances
const inst = [];   // { id, x, y, z, qx, qy, qz, qw }
for (const f of files(path.join(GTA, 'data', 'maps'), '.ipl')) {
    let sec = null;
    for (let line of fs.readFileSync(f, 'latin1').split(/\r?\n/)) {
        line = line.replace(/#.*/, '').trim();
        if (!line) continue;
        if (/^[a-z]{4}$/i.test(line)) { sec = line.toLowerCase(); continue; }
        if (/^end$/i.test(line)) { sec = null; continue; }
        if (sec === 'inst') {
            const p = line.split(/\s*,\s*/);
            if (+p[2] !== 0) continue;                         // interiors
            inst.push({ id: +p[0], x: +p[3], y: +p[4], z: +p[5], qx: +p[6], qy: +p[7], qz: +p[8], qw: +p[9] });
        }
    }
}
const img = readImg(path.join(GTA, 'models', 'gta3.img'));
for (const [name, e] of img.entries) {
    if (!name.endsWith('.ipl')) continue;
    const b = img.read(name);
    if (b.toString('latin1', 0, 4) !== 'bnry') continue;
    const count = b.readUInt32LE(4), off = b.readUInt32LE(0x1C);
    for (let k = 0; k < count; k++) {
        const o = off + k * 40;
        if (b.readInt32LE(o + 32) !== 0) continue;             // interiors
        inst.push({ id: b.readInt32LE(o + 28), x: b.readFloatLE(o), y: b.readFloatLE(o + 4), z: b.readFloatLE(o + 8),
            qx: b.readFloatLE(o + 12), qy: b.readFloatLE(o + 16), qz: b.readFloatLE(o + 20), qw: b.readFloatLE(o + 24) });
    }
}

// ---------------------------------------------------------------- centre lines per model (local)
const cache = new Map();
function modelLines(name) {
    if (cache.has(name)) return cache.get(name);
    let lines = [];
    const b = img.read(name + '.dff');
    if (b && TEXES.some(t => b.indexOf(t) >= 0)) {
        for (const g of readDff(b)) {
            const mis = new Set(g.mats.map((m, i) => TEXES.includes(m.tex) ? i : -1).filter(i => i >= 0));
            if (!mis.size || !g.uv || !g.uv[0]) continue;
            const uv = g.uv[0];
            for (const t of g.tris) {
                if (!mis.has(t[3])) continue;
                const vs = [t[0], t[1], t[2]];
                const us = vs.map(i => uv[i][0]);
                // the bed (possibly split into several strips across the track) crosses u = 0.5;
                // the rail boxes use u 0.19-0.24 / 0.77-0.79 and never do
                if (!(Math.min(...us) < 0.5 && Math.max(...us) > 0.5)) continue;
                // the bed is flat: skip steep faces
                const P = vs.map(i => g.verts[i]);
                const ax = P[1][0] - P[0][0], ay = P[1][1] - P[0][1], az = P[1][2] - P[0][2];
                const bx = P[2][0] - P[0][0], by = P[2][1] - P[0][1], bz = P[2][2] - P[0][2];
                const nx = ay * bz - az * by, ny = az * bx - ax * bz, nz = ax * by - ay * bx;
                if (Math.abs(nz) < 0.8 * Math.hypot(nx, ny, nz)) continue;
                // u = 0.5 iso-line through the triangle
                const pts = [];
                for (let k = 0; k < 3; k++) {
                    const i = k, j = (k + 1) % 3;
                    const u1 = us[i] - 0.5, u2 = us[j] - 0.5;
                    if ((u1 <= 0 && u2 > 0) || (u1 > 0 && u2 <= 0)) {
                        const f = u1 / (u1 - u2);
                        pts.push([P[i][0] + (P[j][0] - P[i][0]) * f, P[i][1] + (P[j][1] - P[i][1]) * f, P[i][2] + (P[j][2] - P[i][2]) * f]);
                    }
                }
                if (pts.length === 2 && Math.hypot(pts[1][0] - pts[0][0], pts[1][1] - pts[0][1]) > 0.05) lines.push(pts);
            }
        }
    }
    cache.set(name, lines);
    return lines;
}

// rotate v by the conjugate of q (IPL quaternions are stored inverted)
function rot(q, v) {
    const x = -q.qx, y = -q.qy, z = -q.qz, w = q.qw;
    const tx = 2 * (y * v[2] - z * v[1]), ty = 2 * (z * v[0] - x * v[2]), tz = 2 * (x * v[1] - y * v[0]);
    return [v[0] + w * tx + (y * tz - z * ty), v[1] + w * ty + (z * tx - x * tz), v[2] + w * tz + (x * ty - y * tx)];
}

const segs = [];
const used = {};
for (const i of inst) {
    const name = names.get(i.id);
    if (!name || name.startsWith('lod')) continue;
    const lines = modelLines(name);
    if (!lines.length) continue;
    used[name] = (used[name] || 0) + 1;
    for (const l of lines) {
        const a = rot(i, l[0]), b = rot(i, l[1]);
        segs.push([a[0] + i.x, a[1] + i.y, a[2] + i.z + RAIL_TOP, b[0] + i.x, b[1] + i.y, b[2] + i.z + RAIL_TOP, name]
            .map(v => typeof v === 'number' ? Math.round(v * 1000) / 1000 : v));
    }
}
fs.mkdirSync(path.dirname(OUT), { recursive: true });
fs.writeFileSync(OUT, JSON.stringify({ about: 'GENERATED by tools/scan_rails.js - track centre lines (rail top z) from the map models', segs }));
let len = 0;
for (const s of segs) len += Math.hypot(s[3] - s[0], s[4] - s[1]);
console.log('instances', inst.length, 'track models', Object.keys(used).length, 'placements', Object.values(used).reduce((a, b) => a + b, 0),
    'centre-line pieces', segs.length, 'length', (len / 1000).toFixed(1), 'km');
