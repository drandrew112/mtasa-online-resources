// Minimal RenderWare reader for the rail scanner (tools/scan_rails.js): IMG v2 archives and DFF
// geometries (vertices, uvs, triangles + material index, material texture names).
const fs = require('fs'), path = require('path');

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

function readDff(b) {
    const geoms = [];
    function walk(off, end, ctx) {
        while (off + 12 <= end) {
            const type = b.readUInt32LE(off), size = b.readUInt32LE(off + 4), body = off + 12;
            if (size > end - body) return;
            if (type === 0x0F) {               // geometry
                const g = { mats: [] };
                geoms.push(g);
                walk(body, body + size, { geom: g });
            } else if (type === 0x01 && ctx.geom && !ctx.geom.verts && !ctx.inMat) {
                const g = ctx.geom;
                const flags = b.readUInt16LE(body), nuv = b.readUInt8(body + 2) || ((flags & 4) ? 1 : 0);
                const nt = b.readUInt32LE(body + 4), nv = b.readUInt32LE(body + 8);
                let p = body + 16;
                if (flags & 8) p += nv * 4;                     // prelit colours
                g.uv = [];
                for (let k = 0; k < nuv; k++) {
                    const set = [];
                    for (let i = 0; i < nv; i++) set.push([b.readFloatLE(p + i * 8), b.readFloatLE(p + i * 8 + 4)]);
                    g.uv.push(set);
                    p += nv * 8;
                }
                g.tris = [];
                for (let i = 0; i < nt; i++) {
                    // v2, v1, material, v3 (uint16 each)
                    const v2 = b.readUInt16LE(p), v1 = b.readUInt16LE(p + 2), m = b.readUInt16LE(p + 4), v3 = b.readUInt16LE(p + 6);
                    g.tris.push([v1, v2, v3, m]);
                    p += 8;
                }
                p += 24;                                         // bounding sphere + hasVertices + hasNormals
                g.verts = [];
                for (let i = 0; i < nv; i++) g.verts.push([b.readFloatLE(p + i * 12), b.readFloatLE(p + i * 12 + 4), b.readFloatLE(p + i * 12 + 8)]);
            } else if (type === 0x07 && ctx.geom) {          // material
                const m = { tex: null };
                ctx.geom.mats.push(m);
                walk(body, body + size, { geom: ctx.geom, mat: m, inMat: true });
            } else if (type === 0x02 && ctx.mat && ctx.inTex && ctx.mat.tex === null) {
                ctx.mat.tex = b.toString('latin1', body, body + size).replace(/\0.*$/s, '').toLowerCase();
            } else if (type === 0x06 && ctx.mat) {
                walk(body, body + size, Object.assign({}, ctx, { inTex: true }));
            } else if ([0x10, 0x1A, 0x08, 0x03].includes(type) || (type === 0x0E)) {
                walk(body, body + size, ctx);
            }
            off = body + size;
        }
    }
    walk(0, b.length, {});
    return geoms;
}

module.exports = { readImg, readDff };
