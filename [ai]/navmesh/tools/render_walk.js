// Debug render of a walk.nav area (top-most floor per cell) to PNG:
//   node tools/render_walk.js x0 y0 x1 y1 [out.png] [walk.nav]
// colours: class (tarmac grey, pavement light, grass green, dirt brown, structure blue, shallow water cyan,
// rough olive, unknown white), road flag = dark grey, crossing = yellow, ped path = magenta, edge = black
'use strict';
const fs = require('fs'), path = require('path'), zlib = require('zlib');
const [x0, y0, x1, y1] = process.argv.slice(2, 6).map(Number);
const OUT = process.argv[6] || path.join(__dirname, '..', 'data', 'build', 'walk.png');
const FILE = process.argv[7] || path.join(__dirname, '..', 'data', 'runtime', 'walk.nav');
const b = fs.readFileSync(FILE);
const TILE = b.readUInt16LE(6), CS = b.readFloatLE(8), OX = b.readInt32LE(12), OY = b.readInt32LE(16), TX = b.readUInt16LE(20);
const cache = new Map();
function tile(tx, ty) {
    const k = ty * TX + tx;
    if (cache.has(k)) return cache.get(k);
    const off = b.readUInt32LE(24 + k * 8), len = b.readUInt32LE(28 + k * 8);
    let t = null;
    if (off) {
        const d = zlib.inflateSync(b.subarray(off, off + len)), L = d[0], n = L * 1024;
        t = { L, z: new Int16Array(n), f: d.subarray(1 + n * 2) };
        for (let l = 0; l < L; l++) {
            let prev = -32768;
            for (let c = 0; c < 1024; c++) {
                const i = l * 1024 + c; let v = d[1 + i] | (d[1 + n + i] << 8); if (v >= 32768) v -= 65536;
                const z = prev === -32768 ? v : (v === -32768 ? -32768 : prev + v);
                t.z[i] = z; prev = z;
            }
        }
    }
    cache.set(k, t); return t;
}
function cell(gx, gy) {
    const t = tile(Math.floor(gx / TILE), Math.floor(gy / TILE));
    if (!t) return null;
    const c = (gy % TILE) * TILE + (gx % TILE);
    let best = null;
    for (let l = 0; l < t.L; l++) {
        const z = t.z[l * 1024 + c];
        if (z === -32768) continue;
        if (!best || z > best[0]) best = [z, t.f[l * 1024 + c], t.L];
    }
    return best;
}
const CL = [[255, 255, 255], [120, 120, 120], [200, 200, 190], [70, 160, 60], [160, 120, 70], [90, 120, 200], [80, 200, 220], [120, 130, 50]];
const W = Math.round((x1 - x0) / CS), H = Math.round((y1 - y0) / CS);
const raw = Buffer.alloc((W * 3 + 1) * H);
for (let py = 0; py < H; py++) {
    raw[py * (W * 3 + 1)] = 0;
    for (let px = 0; px < W; px++) {
        const gx = Math.floor((x0 - OX) / CS) + px, gy = Math.floor((y1 - OY) / CS) - 1 - py;
        const c = cell(gx, gy);
        let col = [20, 20, 40];
        if (c) {
            const f = c[1];
            col = CL[f & 7].slice();
            if (f & 16) col = [60, 60, 60];
            if (f & 64) col = [220, 60, 200];
            if (f & 32) col = [240, 220, 40];
            if (f & 8) col = col.map(v => v * 0.45);
            if (f & 128) col = col.map(v => v * 0.75);
        }
        const o = py * (W * 3 + 1) + 1 + px * 3;
        raw[o] = col[0]; raw[o + 1] = col[1]; raw[o + 2] = col[2];
    }
}
function chunk(type, data) {
    const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
    const td = Buffer.concat([Buffer.from(type, 'latin1'), data]);
    const crc = Buffer.alloc(4); crc.writeUInt32BE(zlib.crc32 ? zlib.crc32(td) >>> 0 : crc32(td));
    return Buffer.concat([len, td, crc]);
}
function crc32(buf) { let c, crc = 0xFFFFFFFF; for (let n = 0; n < buf.length; n++) { c = (crc ^ buf[n]) & 0xFF; for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; crc = (crc >>> 8) ^ c; } return (crc ^ 0xFFFFFFFF) >>> 0; }
const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(W, 0); ihdr.writeUInt32BE(H, 4); ihdr[8] = 8; ihdr[9] = 2;
fs.mkdirSync(path.dirname(OUT), { recursive: true });
fs.writeFileSync(OUT, Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]));
console.log('wrote', OUT, W + 'x' + H);
