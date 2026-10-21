// navmesh open-terrain walk grid:   node tools/walkgrid.js ["C:/Games/GTA San Andreas"] [--area x0,y0,x1,y1]
// Rasterises the collision of every placed map model (COL faces, boxes, spheres of all IPL instances,
// interior 0, no LODs) into a 1 m height-span field (Recast-style), keeps the walkable floors (slope,
// clearance, under-water, tiny islands removed) in up to MAX_LAYERS levels per cell and marks them with the
// road lanes (data/runtime/roads.nav), the GTA ped paths and crossings (data/runtime/peds.nav).
// Output: data/runtime/walk.nav (server only, see README "walk.nav format"), data/build/walk_report.json
// Limit: vanilla map only (removeWorldModel / custom objects of the server are not in it).
'use strict';
const fs = require('fs'), path = require('path');

const ROOT = path.join(__dirname, '..');
const args = process.argv.slice(2);
const GTA = args.find(a => !a.startsWith('--') && !/^-?\d/.test(a)) || 'C:/Games/GTA San Andreas';
const areaArg = (() => { const i = args.indexOf('--area'); return i >= 0 ? args[i + 1].split(',').map(Number) : null; })();
const OUT = path.join(ROOT, 'data', 'runtime', areaArg ? 'walk_area.nav' : 'walk.nav');

// ---------------------------------------------------------------- settings
const CS = 1.0;                 // cell size (m)
const TILE = 32;                // cells per tile side
const ORIGIN = -3000;           // world min x / y
const TILES = Math.ceil(6000 / (TILE * CS));   // 188 tiles per side
const CHUNK = 4;                // tiles per processing chunk side (128 m)
const WALK_NZ = Math.cos(50 * Math.PI / 180);  // walkable slope
const STEEP_NZ = Math.cos(30 * Math.PI / 180); // steeper than this = steep flag
const CLEARANCE = 1.75;         // free height above a floor (ped)
const STEP = 0.55;              // climbable step between neighbour cells
const MERGE = 0.4;              // span tops this close merge their walkable flag (Recast flagMergeThr)
const MAX_LAYERS = 4;
const MIN_REGION = 24;          // connected floor areas smaller than this (cells) are dropped
const WATER_DEEP = 0.45;        // floor this far under the water level = not walkable (shallow: flag)
const NONE = -32768;

// flags byte
const F_CLASS = 7, F_EDGE = 8, F_ROAD = 16, F_CROSS = 32, F_PEDPATH = 64, F_STEEP = 128;
// classes: 0 unknown/default 1 tarmac 2 pavement 3 grass 4 dirt/sand 5 structure/indoor 6 shallow water 7 rough

// ---------------------------------------------------------------- IMG (from rw_customtracks/tools/rwdff.js)
function readImg(file) {
    const fd = fs.openSync(file, 'r');
    const hdr = Buffer.alloc(8); fs.readSync(fd, hdr, 0, 8, 0);
    const n = hdr.readUInt32LE(4);
    const dir = Buffer.alloc(n * 32); fs.readSync(fd, dir, 0, n * 32, 8);
    const entries = new Map();
    for (let i = 0; i < n; i++) {
        const name = dir.toString('latin1', i * 32 + 8, i * 32 + 32).replace(/\0.*$/, '').toLowerCase();
        entries.set(name, { off: dir.readUInt32LE(i * 32) * 2048, size: dir.readUInt16LE(i * 32 + 4) * 2048 });
    }
    return {
        entries,
        read(name) {
            const e = entries.get(name.toLowerCase());
            if (!e) return null;
            const b = Buffer.alloc(e.size); fs.readSync(fd, b, 0, e.size, e.off);
            return b;
        },
    };
}
function files(dir, ext, out = []) {
    for (const f of fs.readdirSync(dir)) {
        const p = path.join(dir, f);
        if (fs.statSync(p).isDirectory()) files(p, ext, out);
        else if (f.toLowerCase().endsWith(ext)) out.push(p);
    }
    return out;
}

// ---------------------------------------------------------------- materials (surfinfo.dat order = material id)
const matClass = new Uint8Array(256);
(() => {
    let id = 0;
    for (let line of fs.readFileSync(path.join(GTA, 'data', 'surfinfo.dat'), 'latin1').split(/\r?\n/)) {
        line = line.trim();
        if (!line || line.startsWith('#') || !/^[A-Z_0-9]+\s/.test(line + ' ') || /^processed/i.test(line)) continue;
        const n = line.split(/\s+/)[0];
        let c = 0;
        if (/^TARMAC/.test(n)) c = 1;
        else if (/PAVEMENT|CONCRETE|PAINTED_GROUND|POOLSIDE|AIRPORTGRND|DOCKLANDS|INDUSTRIAL|BUILDINGSITE|ALLEYRUBISH|LITTER/.test(n)) c = 2;
        else if (/GRASS|MEADOW|FLOWERBED|VEGETATION|WOODLAND|WOODDENSE|FOREST|PARKGRASS|SPARSEFLOWERS/.test(n)) c = 3;
        else if (/SAND|DIRT|MUD|GRAVEL|ROCK|WASTEGROUND|RUBBLE|DESERT|MOUNTAIN|JUNKYARD|DUMP|ROADSIDE|STUMPS|STICKS|LEAVES/.test(n)) c = 4;
        else if (/WOOD|FLOOR|STAIRS|CARPET|METAL|GIRDER|PLATE|SCAFFOLD|CONTAINER|DOOR|PLASTIC|RAILTRACK|DESK|SHELF|TABLE|GLASS/.test(n)) c = 5;
        else if (/WATER|RIVER|UNDERWATER|MARSH|SEAWEED/.test(n)) c = 6;
        else if (/CLIFF|SLIDY|HEDGE|CORNFIELD|BUSHY|CACTUS/.test(n)) c = 7;
        matClass[id] = c;
        id++;
    }
})();

// ---------------------------------------------------------------- IDE names + IPL instances
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
const img = readImg(path.join(GTA, 'models', 'gta3.img'));
const inst = [];
for (const f of files(path.join(GTA, 'data', 'maps'), '.ipl')) {
    let sec = null;
    for (let line of fs.readFileSync(f, 'latin1').split(/\r?\n/)) {
        line = line.replace(/#.*/, '').trim();
        if (!line) continue;
        if (/^[a-z]{4}$/i.test(line)) { sec = line.toLowerCase(); continue; }
        if (/^end$/i.test(line)) { sec = null; continue; }
        if (sec === 'inst') {
            const p = line.split(/\s*,\s*/);
            if ((+p[2] & 0xFF) !== 0) continue;
            inst.push({ id: +p[0], x: +p[3], y: +p[4], z: +p[5], qx: +p[6], qy: +p[7], qz: +p[8], qw: +p[9] });
        }
    }
}
for (const [name] of img.entries) {
    if (!name.endsWith('.ipl')) continue;
    const b = img.read(name);
    if (b.toString('latin1', 0, 4) !== 'bnry') continue;
    const count = b.readUInt32LE(4), off = b.readUInt32LE(0x1C);
    for (let k = 0; k < count; k++) {
        const o = off + k * 40;
        if ((b.readInt32LE(o + 32) & 0xFF) !== 0) continue;
        inst.push({ id: b.readInt32LE(o + 28), x: b.readFloatLE(o), y: b.readFloatLE(o + 4), z: b.readFloatLE(o + 8),
            qx: b.readFloatLE(o + 12), qy: b.readFloatLE(o + 16), qz: b.readFloatLE(o + 20), qw: b.readFloatLE(o + 24) });
    }
}

// ---------------------------------------------------------------- COL archives
// model -> { tris: Float32Array (9 per tri), tmat: Uint8Array, boxes: [[minx..maxz, mat]], spheres: [[x,y,z,r]], r: bounding radius, c: centre }
const cols = new Map();
function parseColEntry(b, o) {
    const four = b.toString('latin1', o, o + 4);
    const size = b.readUInt32LE(o + 4);
    const name = b.toString('latin1', o + 8, o + 30).replace(/\0.*$/, '').toLowerCase();
    const base = o + 4;              // COL2/3 offsets are relative to here
    let p = o + 32;
    const m = { tris: null, tmat: null, boxes: [], spheres: [] };
    if (four === 'COLL') {
        m.r = b.readFloatLE(p); m.c = [b.readFloatLE(p + 4), b.readFloatLE(p + 8), b.readFloatLE(p + 12)]; p += 40;
        const ns = b.readUInt32LE(p); p += 4;
        for (let i = 0; i < ns; i++, p += 20) m.spheres.push([b.readFloatLE(p + 4), b.readFloatLE(p + 8), b.readFloatLE(p + 12), b.readFloatLE(p)]);
        p += 4;   // unknown count (0)
        const nb = b.readUInt32LE(p); p += 4;
        for (let i = 0; i < nb; i++, p += 28) m.boxes.push([b.readFloatLE(p), b.readFloatLE(p + 4), b.readFloatLE(p + 8), b.readFloatLE(p + 12), b.readFloatLE(p + 16), b.readFloatLE(p + 20), b.readUInt8(p + 24)]);
        const nv = b.readUInt32LE(p); p += 4;
        const vs = new Float32Array(nv * 3);
        for (let i = 0; i < nv * 3; i++, p += 4) vs[i] = b.readFloatLE(p);
        const nf = b.readUInt32LE(p); p += 4;
        m.tris = new Float32Array(nf * 9); m.tmat = new Uint8Array(nf);
        for (let i = 0; i < nf; i++, p += 16) {
            const a = b.readUInt32LE(p), c = b.readUInt32LE(p + 4), d = b.readUInt32LE(p + 8);
            m.tmat[i] = b.readUInt8(p + 12);
            for (const [k, v] of [[0, a], [3, c], [6, d]]) { m.tris[i * 9 + k] = vs[v * 3]; m.tris[i * 9 + k + 1] = vs[v * 3 + 1]; m.tris[i * 9 + k + 2] = vs[v * 3 + 2]; }
        }
    } else if (four === 'COL2' || four === 'COL3' || four === 'COL4') {
        m.c = [b.readFloatLE(p + 24), b.readFloatLE(p + 28), b.readFloatLE(p + 32)]; m.r = b.readFloatLE(p + 36); p += 40;
        const ns = b.readUInt16LE(p), nb = b.readUInt16LE(p + 2), nf = b.readUInt16LE(p + 4);
        const offS = b.readUInt32LE(p + 12), offB = b.readUInt32LE(p + 16), offV = b.readUInt32LE(p + 24), offF = b.readUInt32LE(p + 28);
        for (let i = 0; i < ns; i++) { const q = base + offS + i * 20; m.spheres.push([b.readFloatLE(q), b.readFloatLE(q + 4), b.readFloatLE(q + 8), b.readFloatLE(q + 12)]); }
        for (let i = 0; i < nb; i++) { const q = base + offB + i * 28; m.boxes.push([b.readFloatLE(q), b.readFloatLE(q + 4), b.readFloatLE(q + 8), b.readFloatLE(q + 12), b.readFloatLE(q + 16), b.readFloatLE(q + 20), b.readUInt8(q + 24)]); }
        m.tris = new Float32Array(nf * 9); m.tmat = new Uint8Array(nf);
        for (let i = 0; i < nf; i++) {
            const q = base + offF + i * 8;
            const idx = [b.readUInt16LE(q), b.readUInt16LE(q + 2), b.readUInt16LE(q + 4)];
            m.tmat[i] = b.readUInt8(q + 6);
            for (let k = 0; k < 3; k++) {
                const v = base + offV + idx[k] * 6;
                m.tris[i * 9 + k * 3] = b.readInt16LE(v) / 128; m.tris[i * 9 + k * 3 + 1] = b.readInt16LE(v + 2) / 128; m.tris[i * 9 + k * 3 + 2] = b.readInt16LE(v + 4) / 128;
            }
        }
    } else return null;
    if (!cols.has(name)) cols.set(name, m);
    return o + 8 + size;
}
for (const [name, e] of img.entries) {
    if (!name.endsWith('.col')) continue;
    const b = img.read(name);
    let o = 0;
    while (o + 32 < b.length) {
        const four = b.toString('latin1', o, o + 4);
        if (!/^COL[L234]$/.test(four)) break;
        const n = parseColEntry(b, o);
        if (!n) break;
        o = n;
    }
}

// ---------------------------------------------------------------- water.dat
const water = [];   // { x0,y0,x1,y1, verts:[[x,y,z]...] }
for (const fname of ['water.dat']) {
    for (let line of fs.readFileSync(path.join(GTA, 'data', fname), 'latin1').split(/\r?\n/)) {
        line = line.trim();
        if (!line || line.startsWith('#') || /^processed/i.test(line)) continue;
        const v = line.split(/\s+/).map(Number);
        const nv = Math.floor((v.length - 1) / 7);
        if (nv < 3) continue;
        const verts = [];
        for (let i = 0; i < nv; i++) verts.push([v[i * 7], v[i * 7 + 1], v[i * 7 + 2]]);
        water.push({ x0: Math.min(...verts.map(p => p[0])), x1: Math.max(...verts.map(p => p[0])),
            y0: Math.min(...verts.map(p => p[1])), y1: Math.max(...verts.map(p => p[1])), verts });
    }
}
function waterLevel(x, y) {
    let lvl = -Infinity;
    for (const w of water) {
        if (x < w.x0 || x > w.x1 || y < w.y0 || y > w.y1) continue;
        // quads are axis aligned (4 verts: bilinear), triangles: barycentric
        const V = w.verts;
        if (V.length === 4) {
            const fx = (x - w.x0) / ((w.x1 - w.x0) || 1), fy = (y - w.y0) / ((w.y1 - w.y0) || 1);
            const z = V[0][2] * (1 - fx) * (1 - fy) + V[1][2] * fx * (1 - fy) + V[2][2] * (1 - fx) * fy + V[3][2] * fx * fy;
            if (z > lvl) lvl = z;
        } else {
            const [a, b, c] = V;
            const d = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1]);
            if (!d) continue;
            const l1 = ((b[1] - c[1]) * (x - c[0]) + (c[0] - b[0]) * (y - c[1])) / d;
            const l2 = ((c[1] - a[1]) * (x - c[0]) + (a[0] - c[0]) * (y - c[1])) / d;
            const l3 = 1 - l1 - l2;
            if (l1 >= 0 && l2 >= 0 && l3 >= 0) { const z = l1 * a[2] + l2 * b[2] + l3 * c[2]; if (z > lvl) lvl = z; }
        }
    }
    return lvl;
}

// ---------------------------------------------------------------- instance transforms + chunk bins
function rot(q, x, y, z, out, o) {   // rotate by the conjugate of q (IPL quaternions are stored inverted)
    const qx = -q.qx, qy = -q.qy, qz = -q.qz, w = q.qw;
    const tx = 2 * (qy * z - qz * y), ty = 2 * (qz * x - qx * z), tz = 2 * (qx * y - qy * x);
    out[o] = x + w * tx + (qy * tz - qz * ty) + q.x;
    out[o + 1] = y + w * ty + (qz * tx - qx * tz) + q.y;
    out[o + 2] = z + w * tz + (qx * ty - qy * tx) + q.z;
}
const CHUNKS = Math.ceil(TILES / CHUNK);
const CHUNK_M = CHUNK * TILE * CS;
const bins = new Map();
let usedInst = 0, noCol = 0;
for (const i of inst) {
    const name = names.get(i.id);
    if (!name || name.startsWith('lod')) continue;
    const m = cols.get(name);
    if (!m) { noCol++; continue; }
    if (!m.tris.length && !m.boxes.length && !m.spheres.length) continue;
    const c = new Float64Array(3); rot(i, m.c[0], m.c[1], m.c[2], c, 0);
    const r = m.r + 1;
    const cx0 = Math.floor((c[0] - r - ORIGIN) / CHUNK_M), cx1 = Math.floor((c[0] + r - ORIGIN) / CHUNK_M);
    const cy0 = Math.floor((c[1] - r - ORIGIN) / CHUNK_M), cy1 = Math.floor((c[1] + r - ORIGIN) / CHUNK_M);
    usedInst++;
    for (let cx = Math.max(0, cx0); cx <= Math.min(CHUNKS - 1, cx1); cx++)
        for (let cy = Math.max(0, cy0); cy <= Math.min(CHUNKS - 1, cy1); cy++) {
            const k = cx * 1000 + cy;
            if (!bins.has(k)) bins.set(k, []);
            bins.get(k).push(i);
        }
}
console.log(`instances ${inst.length}, used ${usedInst}, without collision ${noCol}, col models ${cols.size}, water polys ${water.length}`);

// ---------------------------------------------------------------- span field of one chunk
const N = CHUNK * TILE;          // cells per chunk side
let spans;                       // per cell: flat [zmin, zmax, area, ...] sorted by zmin
let chunkX0, chunkY0;            // world min corner
// area: bit 0 walkable top, bits 1-3 class, bit 4 steep
function addSpan(ci, smin, smax, area) {
    let s = spans[ci];
    if (!s) { spans[ci] = [smin, smax, area]; return; }
    // merge with every overlapping span (Recast addSpan)
    let i = 0;
    while (i < s.length) {
        const cmin = s[i], cmax = s[i + 1];
        if (cmin > smax) break;
        if (cmax < smin) { i += 3; continue; }
        if (cmin < smin) smin = cmin;
        if (Math.abs(smax - cmax) <= MERGE) area = (area & 1) >= (s[i + 2] & 1) ? area : s[i + 2];
        else if (cmax > smax) area = s[i + 2];
        if (cmax > smax) smax = cmax;
        s.splice(i, 3);
    }
    s.splice(i, 0, smin, smax, area);
}
// polygon clip helpers (Recast dividePoly): out1 = part with coord <= x, out2 = part with coord >= x
const dTmp = new Float64Array(16);
function dividePoly(inp, n, out1, out2, x, axis) {
    const d = dTmp;
    for (let i = 0; i < n; i++) d[i] = x - inp[i * 3 + axis];
    let m = 0, k = 0;
    for (let i = 0, j = n - 1; i < n; j = i, i++) {
        const ina = d[j] >= 0, inb = d[i] >= 0;
        if (ina !== inb) {
            const s = d[j] / (d[j] - d[i]);
            for (let q = 0; q < 3; q++) { const v = inp[j * 3 + q] + (inp[i * 3 + q] - inp[j * 3 + q]) * s; out1[m * 3 + q] = v; out2[k * 3 + q] = v; }
            m++; k++;
            if (d[i] > 0) { out1[m * 3] = inp[i * 3]; out1[m * 3 + 1] = inp[i * 3 + 1]; out1[m * 3 + 2] = inp[i * 3 + 2]; m++; }
            else if (d[i] < 0) { out2[k * 3] = inp[i * 3]; out2[k * 3 + 1] = inp[i * 3 + 1]; out2[k * 3 + 2] = inp[i * 3 + 2]; k++; }
        } else {
            if (d[i] >= 0) { out1[m * 3] = inp[i * 3]; out1[m * 3 + 1] = inp[i * 3 + 1]; out1[m * 3 + 2] = inp[i * 3 + 2]; m++; if (d[i] !== 0) continue; }
            out2[k * 3] = inp[i * 3]; out2[k * 3 + 1] = inp[i * 3 + 1]; out2[k * 3 + 2] = inp[i * 3 + 2]; k++;
        }
    }
    return m * 16 + k;   // packed: n1 * 16 + n2 (polygons stay below 16 vertices)
}
const PB = 16 * 3;
let bA = new Float64Array(PB), bB = new Float64Array(PB), rA = new Float64Array(PB), rB = new Float64Array(PB);
const bCell = new Float64Array(PB), bJunk = new Float64Array(PB);
function rasterTri(t, area) {
    const minx = Math.min(t[0], t[3], t[6]), maxx = Math.max(t[0], t[3], t[6]);
    const miny = Math.min(t[1], t[4], t[7]), maxy = Math.max(t[1], t[4], t[7]);
    const W = N * CS;
    if (maxx < chunkX0 || minx >= chunkX0 + W || maxy < chunkY0 || miny >= chunkY0 + W) return;
    let inp = bA, rest = bB;
    for (let i = 0; i < 9; i++) inp[i] = t[i];
    let nin = 3;
    if (miny < chunkY0) {   // drop the part below the chunk
        const r = dividePoly(inp, nin, bJunk, rest, chunkY0, 1); nin = r & 15;
        const tmp = inp; inp = rest; rest = tmp;
        if (nin < 3) return;
    }
    const y0 = Math.max(0, Math.floor((miny - chunkY0) / CS)), y1 = Math.min(N - 1, Math.floor((maxy - chunkY0) / CS));
    for (let y = y0; y <= y1 && nin >= 3; y++) {
        const r = dividePoly(inp, nin, rA, rest, chunkY0 + (y + 1) * CS, 1);
        const nr = r >> 4; nin = r & 15;
        const tmp = inp; inp = rest; rest = tmp;
        if (nr < 3) continue;
        let row = rA, rrest = rB, nri = nr;
        let rminx = row[0], rmaxx = row[0];
        for (let i = 1; i < nri; i++) { if (row[i * 3] < rminx) rminx = row[i * 3]; if (row[i * 3] > rmaxx) rmaxx = row[i * 3]; }
        if (rminx < chunkX0) {
            const q = dividePoly(row, nri, bJunk, rrest, chunkX0, 0); nri = q & 15;
            const tmp2 = row; row = rrest; rrest = tmp2;
            if (nri < 3) continue;
        }
        const x0 = Math.max(0, Math.floor((rminx - chunkX0) / CS)), x1 = Math.min(N - 1, Math.floor((rmaxx - chunkX0) / CS));
        for (let x = x0; x <= x1 && nri >= 3; x++) {
            const q = dividePoly(row, nri, bCell, rrest, chunkX0 + (x + 1) * CS, 0);
            const nc = q >> 4; nri = q & 15;
            const tmp2 = row; row = rrest; rrest = tmp2;
            if (nc < 3) continue;
            let smin = bCell[2], smax = bCell[2];
            for (let i = 1; i < nc; i++) { const z = bCell[i * 3 + 2]; if (z < smin) smin = z; if (z > smax) smax = z; }
            addSpan(y * N + x, smin, smax, area);
        }
    }
}
function triArea(t, mat) {
    const ax = t[3] - t[0], ay = t[4] - t[1], az = t[5] - t[2], bx = t[6] - t[0], by = t[7] - t[1], bz = t[8] - t[2];
    const nx = ay * bz - az * by, ny = az * bx - ax * bz, nz = ax * by - ay * bx;
    const l = Math.hypot(nx, ny, nz);
    if (l < 1e-9) return -1;
    const anz = Math.abs(nz) / l;
    let a = (matClass[mat] & 7) << 1;
    if (anz >= WALK_NZ) a |= 1;
    if (anz < STEEP_NZ) a |= 16;
    return a;
}
const tri = new Float64Array(9);
const BOX_TRIS = [[0, 1, 3], [0, 3, 2], [4, 6, 7], [4, 7, 5], [0, 4, 5], [0, 5, 1], [2, 3, 7], [2, 7, 6], [0, 2, 6], [0, 6, 4], [1, 5, 7], [1, 7, 3]];
function rasterInstance(i, m) {
    const T = m.tris;
    for (let f = 0; f < m.tmat.length; f++) {
        rot(i, T[f * 9], T[f * 9 + 1], T[f * 9 + 2], tri, 0);
        rot(i, T[f * 9 + 3], T[f * 9 + 4], T[f * 9 + 5], tri, 3);
        rot(i, T[f * 9 + 6], T[f * 9 + 7], T[f * 9 + 8], tri, 6);
        const a = triArea(tri, m.tmat[f]);
        if (a >= 0) rasterTri(tri, a);
    }
    const corners = new Float64Array(24);
    for (const b of m.boxes) {
        for (let c = 0; c < 8; c++) rot(i, c & 1 ? b[3] : b[0], c & 2 ? b[4] : b[1], c & 4 ? b[5] : b[2], corners, c * 3);
        for (const [p, q, r] of BOX_TRIS) {
            for (let k = 0; k < 3; k++) { tri[k] = corners[p * 3 + k]; tri[3 + k] = corners[q * 3 + k]; tri[6 + k] = corners[r * 3 + k]; }
            const a = triArea(tri, b[6]);
            if (a >= 0) rasterTri(tri, a);
        }
    }
    const c = new Float64Array(3);
    for (const s of m.spheres) {
        rot(i, s[0], s[1], s[2], c, 0);
        const r = s[3];
        const x0 = Math.max(0, Math.floor((c[0] - r - chunkX0) / CS)), x1 = Math.min(N - 1, Math.floor((c[0] + r - chunkX0) / CS));
        const y0 = Math.max(0, Math.floor((c[1] - r - chunkY0) / CS)), y1 = Math.min(N - 1, Math.floor((c[1] + r - chunkY0) / CS));
        for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) {
            const px = Math.max(chunkX0 + x * CS, Math.min(c[0], chunkX0 + (x + 1) * CS));
            const py = Math.max(chunkY0 + y * CS, Math.min(c[1], chunkY0 + (y + 1) * CS));
            const d2 = (px - c[0]) ** 2 + (py - c[1]) ** 2;
            if (d2 > r * r) continue;
            const h = Math.sqrt(r * r - d2);
            addSpan(y * N + x, c[2] - h, c[2] + h, 0);
        }
    }
}

// ---------------------------------------------------------------- floors per tile (whole world, sparse)
const tiles = new Map();   // key tx*1000+ty -> { L, z: Int16Array(L*1024) dm, f: Uint8Array(L*1024) }
function tileAt(tx, ty) { return tiles.get(tx * 1000 + ty); }
const stats = { chunks: 0, floors: 0, water: 0, shallow: 0, multi: 0 };
const t0 = Date.now();
const [ax0, ay0, ax1, ay1] = areaArg || [ORIGIN, ORIGIN, ORIGIN + 6000, ORIGIN + 6000];
for (let cxi = 0; cxi < CHUNKS; cxi++) for (let cyi = 0; cyi < CHUNKS; cyi++) {
    chunkX0 = ORIGIN + cxi * CHUNK_M; chunkY0 = ORIGIN + cyi * CHUNK_M;
    if (chunkX0 + CHUNK_M <= ax0 || chunkX0 >= ax1 || chunkY0 + CHUNK_M <= ay0 || chunkY0 >= ay1) continue;
    const list = bins.get(cxi * 1000 + cyi);
    if (!list) continue;
    spans = new Array(N * N);
    for (const i of list) rasterInstance(i, cols.get(names.get(i.id)));
    stats.chunks++;
    // floors
    for (let ty = 0; ty < CHUNK; ty++) for (let tx = 0; tx < CHUNK; tx++) {
        const gtx = cxi * CHUNK + tx, gty = cyi * CHUNK + ty;
        if (gtx >= TILES || gty >= TILES) continue;
        const cellFloors = new Array(TILE * TILE);
        let L = 0;
        for (let y = 0; y < TILE; y++) for (let x = 0; x < TILE; x++) {
            const ci = (ty * TILE + y) * N + tx * TILE + x;
            const s = spans[ci];
            if (!s) continue;
            const wx = chunkX0 + (tx * TILE + x + 0.5) * CS, wy = chunkY0 + (ty * TILE + y + 0.5) * CS;
            let wl = null;
            const fl = [];
            for (let k = 0; k < s.length; k += 3) {
                const top = s[k + 1], area = s[k + 2];
                if (!(area & 1)) continue;
                const next = k + 3 < s.length ? s[k + 3] : Infinity;
                if (next - top < CLEARANCE) continue;
                if (wl === null) wl = water.length ? waterLevel(wx, wy) : -Infinity;
                let cls = (area >> 1) & 7, fbits = area & 16 ? F_STEEP : 0;
                if (top < wl - WATER_DEEP) { stats.water++; continue; }
                if (top < wl) { cls = 6; stats.shallow++; }
                fl.push(top, cls | fbits);
            }
            if (!fl.length) continue;
            if (fl.length > MAX_LAYERS * 2) fl.splice(0, fl.length - MAX_LAYERS * 2);   // keep the top ones
            cellFloors[y * TILE + x] = fl;
            L = Math.max(L, fl.length / 2);
        }
        if (!L) continue;
        const t = { L, z: new Int16Array(L * 1024).fill(NONE), f: new Uint8Array(L * 1024) };
        for (let c = 0; c < 1024; c++) {
            const fl = cellFloors[c];
            if (!fl) continue;
            for (let l = 0; l < fl.length / 2; l++) {
                t.z[l * 1024 + c] = Math.max(-32767, Math.min(32767, Math.round(fl[l * 2] * 10)));
                t.f[l * 1024 + c] = fl[l * 2 + 1];
            }
            if (fl.length > 2) stats.multi++;
            stats.floors += fl.length / 2;
        }
        tiles.set(gtx * 1000 + gty, t);
    }
    if (stats.chunks % 40 === 0) console.log(`chunk ${stats.chunks}, ${((Date.now() - t0) / 1000).toFixed(0)} s, floors ${stats.floors}`);
}
spans = null;
console.log(`rasterised ${stats.chunks} chunks in ${((Date.now() - t0) / 1000).toFixed(0)} s, floors ${stats.floors}`);

// ---------------------------------------------------------------- floor access by world cell
function floorsAt(gx, gy) {          // global cell -> [tile, cellIndex] or null
    if (gx < 0 || gy < 0) return null;
    const t = tileAt(Math.floor(gx / TILE), Math.floor(gy / TILE));
    if (!t) return null;
    return [t, (gy % TILE) * TILE + (gx % TILE)];
}
const D4 = [[1, 0], [-1, 0], [0, 1], [0, -1]];
function connectedLayer(t2, c2, z) {   // layer of t2/c2 within STEP of z (dm), -1 none
    let best = -1, bd = STEP * 10 + 0.01;
    for (let l = 0; l < t2.L; l++) {
        const z2 = t2.z[l * 1024 + c2];
        if (z2 === NONE) continue;
        const d = Math.abs(z2 - z);
        if (d <= bd) { bd = d; best = l; }
    }
    return best;
}

// ---------------------------------------------------------------- remove small islands (roof tops, wall tops, props)
(() => {
    const seen = new Map();   // tile key -> Uint8Array(L*1024)
    for (const [k, t] of tiles) seen.set(k, new Uint8Array(t.L * 1024));
    let removed = 0, regions = 0;
    for (const [k, t] of tiles) {
        const tx = Math.floor(k / 1000), ty = k % 1000, sn = seen.get(k);
        for (let l = 0; l < t.L; l++) for (let c = 0; c < 1024; c++) {
            if (t.z[l * 1024 + c] === NONE || sn[l * 1024 + c]) continue;
            const region = []; const stack = [[tx * TILE + (c % TILE), ty * TILE + Math.floor(c / TILE), l]];
            sn[l * 1024 + c] = 1;
            while (stack.length) {
                const [gx, gy, gl] = stack.pop();
                region.push([gx, gy, gl]);
                const [ta, ca] = floorsAt(gx, gy);
                const z = ta.z[gl * 1024 + ca];
                for (const [dx, dy] of D4) {
                    const r = floorsAt(gx + dx, gy + dy);
                    if (!r) continue;
                    const nl = connectedLayer(r[0], r[1], z);
                    if (nl < 0) continue;
                    const s2 = seen.get(Math.floor((gx + dx) / TILE) * 1000 + Math.floor((gy + dy) / TILE));
                    if (s2[nl * 1024 + r[1]]) continue;
                    s2[nl * 1024 + r[1]] = 1;
                    stack.push([gx + dx, gy + dy, nl]);
                }
            }
            regions++;
            if (region.length < MIN_REGION) {
                for (const [gx, gy, gl] of region) { const [ta, ca] = floorsAt(gx, gy); ta.z[gl * 1024 + ca] = NONE; ta.f[gl * 1024 + ca] = 0; }
                removed += region.length;
            }
        }
    }
    stats.regions = regions; stats.islandCells = removed;
})();

// ---------------------------------------------------------------- edge flag (a 4-neighbour is not reachable: wall, drop, nothing)
for (const [k, t] of tiles) {
    const tx = Math.floor(k / 1000), ty = k % 1000;
    for (let l = 0; l < t.L; l++) for (let c = 0; c < 1024; c++) {
        const z = t.z[l * 1024 + c];
        if (z === NONE) continue;
        const gx = tx * TILE + (c % TILE), gy = ty * TILE + Math.floor(c / TILE);
        for (const [dx, dy] of D4) {
            const r = floorsAt(gx + dx, gy + dy);
            if (!r || connectedLayer(r[0], r[1], z) < 0) { t.f[l * 1024 + c] |= F_EDGE; break; }
        }
    }
}

// ---------------------------------------------------------------- road lanes, ped paths, crossings
function markCapsule(x1, y1, z1, x2, y2, z2, halfW, bit, dzMax) {
    const minx = Math.min(x1, x2) - halfW, maxx = Math.max(x1, x2) + halfW, miny = Math.min(y1, y2) - halfW, maxy = Math.max(y1, y2) + halfW;
    const dx = x2 - x1, dy = y2 - y1, L2 = dx * dx + dy * dy || 1e-9;
    let n = 0;
    for (let gy = Math.floor((miny - ORIGIN) / CS); gy <= Math.floor((maxy - ORIGIN) / CS); gy++)
        for (let gx = Math.floor((minx - ORIGIN) / CS); gx <= Math.floor((maxx - ORIGIN) / CS); gx++) {
            const px = ORIGIN + (gx + 0.5) * CS, py = ORIGIN + (gy + 0.5) * CS;
            let u = ((px - x1) * dx + (py - y1) * dy) / L2; u = Math.max(0, Math.min(1, u));
            const qx = x1 + dx * u, qy = y1 + dy * u;
            if ((px - qx) ** 2 + (py - qy) ** 2 > halfW * halfW) continue;
            const r = floorsAt(gx, gy);
            if (!r) continue;
            const z = (z1 + (z2 - z1) * u) * 10;
            for (let l = 0; l < r[0].L; l++) {
                const fz = r[0].z[l * 1024 + r[1]];
                if (fz !== NONE && Math.abs(fz - z) <= dzMax * 10) { r[0].f[l * 1024 + r[1]] |= bit; n++; }
            }
        }
    return n;
}
function readLines(file) { return fs.existsSync(file) ? fs.readFileSync(file, 'latin1').split('\n') : []; }
let roadCells = 0, pedCells = 0, crossCells = 0;
for (const line of readLines(path.join(ROOT, 'data', 'runtime', 'roads.nav'))) {
    if (line[0] !== 'A') continue;
    const p = line.split(' ');
    const v = p.slice(10, 16).map(Number);
    roadCells += markCapsule(v[0], v[1], v[2], v[3], v[4], v[5], 2.4, F_ROAD, 2.0);
}
{
    const pn = new Map();
    for (const line of readLines(path.join(ROOT, 'data', 'runtime', 'peds.nav'))) {
        const p = line.split(' ');
        if (p[0] === 'N') pn.set(p[1], [+p[2], +p[3], +p[4], +p[5]]);
        else if (p[0] === 'E') {
            const a = pn.get(p[1]), b = pn.get(p[2]); if (!a || !b) continue;
            const kind = +p[3];
            if (kind >= 3) crossCells += markCapsule(a[0], a[1], a[2], b[0], b[1], b[2], 1.6, F_CROSS, 2.0);
            else pedCells += markCapsule(a[0], a[1], a[2], b[0], b[1], b[2], Math.max(0.8, Math.min(a[3], b[3]) / 2), F_PEDPATH, 1.5);
        }
    }
}
// crossings are walkable road: drop the road flag there? no - keep both, the cost model treats CROSS first

// ---------------------------------------------------------------- write walk.nav (v2)
// header 24 bytes: "NAVW" u16 version u16 tileCells f32 cellSize i32 originX i32 originY u16 tilesX u16 tilesY
// index: tilesX*tilesY * (u32 offset, u32 length), 0 = no tile; tile blob = zlib( u8 L, z low bytes[L*1024],
// z high bytes[L*1024], flags[L*1024] ) with z (decimetres, int16) delta-coded per layer in cell order:
// first cell / after an empty cell = absolute value, empty cell = -32768, else z - previous z.
const zlib = require('zlib');
const index = Buffer.alloc(TILES * TILES * 8);
const blobs = [];
let off = 24 + index.length, rawBytes = 0;
for (let ty = 0; ty < TILES; ty++) for (let tx = 0; tx < TILES; tx++) {
    const t = tileAt(tx, ty);
    if (!t) continue;
    let L = 0;   // drop empty top layers
    for (let l = 0; l < t.L; l++) for (let c = 0; c < 1024; c++) if (t.z[l * 1024 + c] !== NONE) { L = l + 1; break; }
    if (!L) continue;
    const n = L * 1024;
    const b = Buffer.alloc(1 + n * 3);
    b[0] = L;
    for (let l = 0; l < L; l++) {
        let prev = NONE;
        for (let c = 0; c < 1024; c++) {
            const i = l * 1024 + c, z = t.z[i];
            const v = prev === NONE ? z : (z === NONE ? NONE : z - prev);
            b[1 + i] = v & 255; b[1 + n + i] = (v >> 8) & 255;
            prev = z;
        }
    }
    Buffer.from(t.f.buffer, t.f.byteOffset, n).copy(b, 1 + n * 2);
    const zb = zlib.deflateSync(b, { level: 9 });
    rawBytes += b.length;
    index.writeUInt32LE(off, (ty * TILES + tx) * 8); index.writeUInt32LE(zb.length, (ty * TILES + tx) * 8 + 4);
    blobs.push(zb); off += zb.length;
}
const hdr = Buffer.alloc(24);
hdr.write('NAVW', 0, 'latin1'); hdr.writeUInt16LE(2, 4); hdr.writeUInt16LE(TILE, 6); hdr.writeFloatLE(CS, 8);
hdr.writeInt32LE(ORIGIN, 12); hdr.writeInt32LE(ORIGIN, 16); hdr.writeUInt16LE(TILES, 20); hdr.writeUInt16LE(TILES, 22);
fs.writeFileSync(OUT, Buffer.concat([hdr, index, ...blobs]));
const report = Object.assign(stats, { tiles: blobs.length, bytes: off, rawBytes, roadCells, pedCells, crossCells, seconds: Math.round((Date.now() - t0) / 1000),
    instances: inst.length, usedInstances: usedInst, noCollision: noCol });
fs.mkdirSync(path.join(ROOT, 'data', 'build'), { recursive: true });
fs.writeFileSync(path.join(ROOT, 'data', 'build', areaArg ? 'walk_area_report.json' : 'walk_report.json'), JSON.stringify(report, null, 1));
console.log(JSON.stringify(report));
