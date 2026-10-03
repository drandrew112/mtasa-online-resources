// Cache module: list / read / write / delete cached data, plus the cached
// surface map (live ground scan of a whole area) and patch search on it.
import { z } from 'zod';
import { defineTool } from './registry.js';
import { ToolError } from '../errors.js';
import { cacheKey, DataCache } from '../cache.js';

// rough city rectangles (getZoneName citiesonly decides the real city)
export const CITY_BOUNDS = {
  los_santos: { minX: 44, maxX: 2997, minY: -2892, maxY: -768 },
  san_fierro: { minX: -2997, maxX: -1213, minY: -1115, maxY: 1659 },
  las_venturas: { minX: 869, maxX: 2997, minY: 596, maxY: 2993 },
};
const CITY = z.enum(['los_santos', 'san_fierro', 'las_venturas']);
const bounds = z.object({ minX: z.number(), maxX: z.number(), minY: z.number(), maxY: z.number() });
const UNLOADED = '?';

const inRegion = (r, x, y) => !r || (x >= r.minX && x <= r.maxX && y >= r.minY && y <= r.maxY);

defineTool({
  name: 'cache_list',
  module: 'cache', kind: 'read', needsProbe: false,
  title: 'List cached data',
  description: 'Lists the persistent data cache (survives MCP / MTA restarts): key, kind (surface_map, locations...), description, params, complete flag, item count, size, created / updated. Check it before generating expensive world data (surface maps take minutes) and reuse what is there. Read-only.',
  input: { kind: z.string().optional(), prefix: z.string().optional() },
  returns: ['entries[] (meta)', 'stats'],
  related: ['cache_get', 'build_surface_map', 'cache_put'],
  async handler(a, ctx) { return { entries: ctx.cache.list(a), stats: ctx.cache.stats() }; },
});

defineTool({
  name: 'cache_get',
  module: 'cache', kind: 'read', needsProbe: false,
  title: 'Read cached data',
  description: 'Reads a cache entry by key. metaOnly = true returns only the meta. Surface maps: region {minX,maxX,minY,maxY} returns the cells inside as [x, y, groundZ, surface] (max 5000, use surfaces to filter) plus per-class counts; without region only meta + class counts. Array data: offset / limit paging; region filters items with x / y (or position.x / .y). Read-only.',
  input: {
    key: z.string(), metaOnly: z.boolean().optional(), region: bounds.optional(),
    surfaces: z.array(z.string()).optional().describe('surface maps: only these surface classes'),
    offset: z.number().int().min(0).optional(), limit: z.number().int().min(1).max(5000).optional(),
  },
  returns: ['meta', 'data | cells | items', 'total'],
  related: ['cache_list', 'find_surface_patches'],
  async handler(a, ctx) {
    const e = ctx.cache.get(a.key);
    if (!e) throw new ToolError('NOT_FOUND', `No cache entry '${a.key}'.`, { suggestion: 'cache_list shows the keys.' });
    if (a.metaOnly) return { meta: e.meta };
    if (e.meta.kind === 'surface_map') {
      const m = e.data;
      const counts = classCounts(m);
      if (!a.region) return { meta: e.meta, counts, hint: 'Pass region (and surfaces) to get cells, or use find_surface_patches.' };
      const want = a.surfaces ? new Set(a.surfaces) : null;
      const limit = a.limit || 5000;
      const cells = [];
      let total = 0;
      forEachCell(m, (x, y, zz, s) => {
        if (!inRegion(a.region, x, y) || (want && !want.has(s))) return;
        total++;
        if (cells.length < limit) cells.push([x, y, zz, s]);
      });
      return { meta: e.meta, counts, total, truncated: total > cells.length, cells, cellFormat: '[x, y, groundZ, surface]' };
    }
    let data = e.data;
    if (Array.isArray(data)) {
      if (a.region) data = data.filter((it) => inRegion(a.region, it?.x ?? it?.position?.x ?? it?.[0], it?.y ?? it?.position?.y ?? it?.[1]));
      const total = data.length;
      const off = a.offset || 0;
      const items = data.slice(off, off + (a.limit || 1000));
      return { meta: e.meta, total, offset: off, items, truncated: off + items.length < total };
    }
    if ((e.meta.bytes || 0) > 400000) throw new ToolError('TOO_LARGE', `Entry '${a.key}' is ${e.meta.bytes} bytes.`, { suggestion: 'Use metaOnly or a more specific tool.' });
    return { meta: e.meta, data };
  },
});

defineTool({
  name: 'cache_put',
  module: 'cache', kind: 'mutate', needsProbe: false,
  title: 'Store data in the cache',
  description: 'Stores any JSON data under a key (kind groups entries, e.g. "locations" for hand-verified spots, "notes"). Replaces an existing key only with overwrite = true. Use it for results that took effort to verify (accessible platforms, park spots...) so later tasks reuse them.',
  input: {
    key: z.string(), kind: z.string(), description: z.string().optional(), data: z.any(),
    params: z.record(z.any()).optional(), tags: z.array(z.string()).optional(), overwrite: z.boolean().optional(),
  },
  returns: ['meta'],
  sideEffects: 'Writes a cache file.',
  related: ['cache_list', 'cache_get', 'cache_delete'],
  async handler(a, ctx) {
    DataCache.checkKey(a.key);
    if (ctx.cache.has(a.key) && !a.overwrite) throw new ToolError('EXISTS', `Cache entry '${a.key}' exists.`, { suggestion: 'overwrite: true to replace it.' });
    return { meta: ctx.cache.put(a.key, { kind: a.kind, description: a.description || '', params: a.params, tags: a.tags, complete: true }, a.data) };
  },
});

defineTool({
  name: 'cache_delete',
  module: 'cache', kind: 'mutate', needsProbe: false,
  title: 'Delete cached data',
  description: 'Removes a cache entry (e.g. a stale surface map after map edits). The data is regenerated by its tool the next time.',
  input: { key: z.string() },
  returns: ['deleted'],
  sideEffects: 'Deletes a cache file.',
  related: ['cache_list'],
  async handler(a, ctx) { return { key: a.key, deleted: ctx.cache.delete(a.key) }; },
});

// ------------------------------------------------------------ surface map
// data: { bounds, step, nx, ny, classes[], s[] (class index per cell, -1 = not scanned),
//         z[] (ground z, 1 decimal), blocks: { "bx:by": "done" | "unloaded" } }
// cell (i, j): x = minX + (i + 0.5) * step, y = minY + (j + 0.5) * step, index j * nx + i

function forEachCell(m, fn) {
  for (let j = 0; j < m.ny; j++) for (let i = 0; i < m.nx; i++) {
    const k = j * m.nx + i;
    if (m.s[k] < 0) continue;
    fn(m.bounds.minX + (i + 0.5) * m.step, m.bounds.minY + (j + 0.5) * m.step, m.z[k], m.classes[m.s[k]], i, j);
  }
}

function classCounts(m) {
  const c = {};
  let unscanned = 0;
  for (const v of m.s) if (v < 0) unscanned++; else c[m.classes[v]] = (c[m.classes[v]] || 0) + 1;
  return { ...c, unscanned };
}

function resolveArea(a) {
  if (a.city) return { b: CITY_BOUNDS[a.city], name: a.city };
  if (a.bounds) return { b: a.bounds, name: `${Math.round(a.bounds.minX)}_${Math.round(a.bounds.minY)}_${Math.round(a.bounds.maxX)}_${Math.round(a.bounds.maxY)}` };
  throw new ToolError('INVALID_PARAMS', 'Give city or bounds.');
}

defineTool({
  name: 'build_surface_map',
  module: 'cache', kind: 'read', needsProbe: true,
  title: 'Cached surface map of an area',
  description: 'Scans the ground of a whole city / rectangle on a grid (default 20 m) with the probe: surface class (grass, sidewalk, road, sand, dirt, structure...) + ground z per cell, stored in the persistent cache (key surface_map.<area>.<step>m). Reuses the cache: an existing complete map returns at once; a partial one resumes. Each call scans at most maxBlocks blocks of blockCells x blockCells cells (the camera is focused on the block centre so collision streams in), so call again while complete = false. refresh = true rescans. Then use find_surface_patches / cache_get. Read-only for the world.',
  input: {
    city: CITY.optional(), bounds: bounds.optional(), step: z.number().min(5).max(100).optional(),
    blockCells: z.number().int().min(4).max(20).optional().describe('cells per block edge (default 10; block = step * blockCells metres, keep <= 250 m)'),
    maxBlocks: z.number().int().min(1).max(500).optional().describe('blocks per call (default 80)'),
    refresh: z.boolean().optional(), key: z.string().optional(),
  },
  returns: ['key', 'complete', 'blocks {done, unloaded, total}', 'counts', 'meta'],
  sideEffects: 'Writes the cache. Moves the probe camera temporarily.',
  related: ['find_surface_patches', 'cache_get', 'cache_list'],
  async handler(a, ctx) {
    const { b, name } = resolveArea(a);
    const step = a.step || 20;
    const key = a.key || cacheKey('surface_map', name, `${step}m`);
    DataCache.checkKey(key);
    const bc = a.blockCells || 10;
    let m = !a.refresh && ctx.cache.get(key)?.data;
    if (!m || m.step !== step) {
      const nx = Math.ceil((b.maxX - b.minX) / step), ny = Math.ceil((b.maxY - b.minY) / step);
      m = { bounds: b, step, nx, ny, classes: [], s: new Array(nx * ny).fill(-1), z: new Array(nx * ny).fill(null), blocks: {} };
    }
    const blocks = [];
    for (let bj = 0; bj < Math.ceil(m.ny / bc); bj++) for (let bi = 0; bi < Math.ceil(m.nx / bc); bi++) blocks.push([bi, bj]);
    const meta = () => ({
      kind: 'surface_map', description: `Surface class + ground z grid of ${name} (${step} m)`,
      params: { area: name, bounds: b, step, blockCells: bc }, complete: blocks.every(([bi, bj]) => m.blocks[`${bi}:${bj}`] === 'done'),
    });
    let scanned = 0;
    const started = Date.now();
    for (const [bi, bj] of blocks) {
      const bk = `${bi}:${bj}`;
      if (m.blocks[bk] === 'done') continue;
      if (scanned >= (a.maxBlocks || 80)) break;
      const cells = [];
      for (let j = bj * bc; j < Math.min(m.ny, (bj + 1) * bc); j++) for (let i = bi * bc; i < Math.min(m.nx, (bi + 1) * bc); i++) cells.push([i, j]);
      const cx = m.bounds.minX + ((bi * bc + Math.min(m.nx, (bi + 1) * bc)) / 2) * step;
      const cy = m.bounds.minY + ((bj * bc + Math.min(m.ny, (bj + 1) * bc)) / 2) * step;
      // first point = block centre: the bridge focuses the probe camera on it
      const pts = [{ x: cx, y: cy, z: 0 }, ...cells.map(([i, j]) => ({ x: m.bounds.minX + (i + 0.5) * step, y: m.bounds.minY + (j + 0.5) * step, z: 150 }))];
      let res;
      for (let attempt = 0; attempt < 2; attempt++) {
        res = (await ctx.call('world', 'ground', { points: pts, includeObjects: false, topmost: true }, { timeoutMs: 90000 })).points || [];
        const unloaded = res.slice(1).filter((p) => !p.surfaceClass && p.waterLevel === undefined).length;
        if (unloaded < cells.length * 0.9) break; // mostly water / no ground is fine; nothing at all = not streamed
      }
      let hits = 0;
      cells.forEach(([i, j], n) => {
        const p = res[n + 1] || {};
        const cls = p.underwater ? 'water' : p.surfaceClass || (p.waterLevel !== undefined ? 'water' : UNLOADED);
        if (cls !== UNLOADED) hits++;
        let ci = m.classes.indexOf(cls);
        if (ci < 0) { m.classes.push(cls); ci = m.classes.length - 1; }
        m.s[j * m.nx + i] = ci;
        m.z[j * m.nx + i] = typeof p.groundZ === 'number' ? Math.round(p.groundZ * 10) / 10 : null;
      });
      m.blocks[bk] = hits > 0 ? 'done' : 'unloaded';
      scanned++;
      if (scanned % 10 === 0) ctx.cache.put(key, meta(), m);
    }
    const saved = ctx.cache.put(key, meta(), m);
    const vals = Object.values(m.blocks);
    return {
      key, complete: saved.complete, scannedThisCall: scanned, seconds: Math.round((Date.now() - started) / 1000),
      blocks: { done: vals.filter((v) => v === 'done').length, unloaded: vals.filter((v) => v === 'unloaded').length, total: blocks.length },
      counts: classCounts(m), meta: saved,
      next: saved.complete ? 'find_surface_patches { map: key }' : 'call build_surface_map again with the same area to continue',
    };
  },
});

defineTool({
  name: 'find_surface_patches',
  module: 'cache', kind: 'read', needsProbe: false,
  title: 'Find surface patches (parks, plazas...)',
  description: 'Connected patches of the given surface classes in a cached surface map (e.g. grass -> parks / lawns, sand -> beaches, sidewalk -> plazas), with size, centroid, a spot deep inside the patch (all 8 neighbours same class), height range and the nearest road node (road graph). Filters: minCells, maxRoadDistance (EMS access), maxHeightRange (flat), avoid circles, minSpacing between results. Instant, no probe needed. Verify spots with get_area_summary / find_safe_position / capture_view before use. Read-only.',
  input: {
    map: z.string().optional().describe('surface map key (cache_list) — or give city'),
    city: CITY.optional(), step: z.number().optional(),
    surfaces: z.array(z.string()).optional().describe('default ["grass"]'),
    minCells: z.number().int().min(1).optional().describe('default 9 (= 60 x 60 m at 20 m)'),
    maxRoadDistance: z.number().optional().describe('spot -> nearest road node, default 40'),
    maxHeightRange: z.number().optional().describe('max z range inside the patch, default 6'),
    region: bounds.optional(), avoid: z.array(z.object({ x: z.number(), y: z.number(), radius: z.number() })).optional(),
    minSpacing: z.number().optional().describe('min distance between returned spots (default 0)'),
    limit: z.number().int().min(1).max(500).optional(),
  },
  returns: ['patches[] {spot {x,y,z}, cells, areaM2, centroid, heightRange, road {node, distance}}', 'total'],
  related: ['build_surface_map', 'find_safe_position', 'get_area_summary'],
  async handler(a, ctx) {
    const key = a.map || cacheKey('surface_map', a.city, `${a.step || 20}m`);
    const e = ctx.cache.get(key);
    if (!e || e.meta.kind !== 'surface_map') throw new ToolError('NOT_FOUND', `No surface map '${key}'.`, { suggestion: 'build_surface_map first (or cache_list).' });
    const m = e.data;
    const want = new Set((a.surfaces || ['grass']).map((s) => m.classes.indexOf(s)).filter((i) => i >= 0));
    const minCells = a.minCells ?? 9, maxRoad = a.maxRoadDistance ?? 40, maxH = a.maxHeightRange ?? 6;
    const seen = new Uint8Array(m.nx * m.ny);
    const at = (i, j) => (i < 0 || j < 0 || i >= m.nx || j >= m.ny ? -2 : m.s[j * m.nx + i]);
    const cellXY = (i, j) => [m.bounds.minX + (i + 0.5) * m.step, m.bounds.minY + (j + 0.5) * m.step];
    const patches = [];
    for (let j0 = 0; j0 < m.ny; j0++) for (let i0 = 0; i0 < m.nx; i0++) {
      const k0 = j0 * m.nx + i0;
      if (seen[k0] || !want.has(m.s[k0])) continue;
      const stack = [[i0, j0]], cells = [];
      seen[k0] = 1;
      while (stack.length) {
        const [i, j] = stack.pop();
        cells.push([i, j]);
        for (const [di, dj] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
          const ni = i + di, nj = j + dj;
          if (ni < 0 || nj < 0 || ni >= m.nx || nj >= m.ny) continue;
          const nk = nj * m.nx + ni;
          if (!seen[nk] && want.has(m.s[nk])) { seen[nk] = 1; stack.push([ni, nj]); }
        }
      }
      if (cells.length < minCells) continue;
      let sx = 0, sy = 0, zmin = Infinity, zmax = -Infinity;
      for (const [i, j] of cells) {
        const [x, y] = cellXY(i, j); sx += x; sy += y;
        const zz = m.z[j * m.nx + i];
        if (zz !== null) { zmin = Math.min(zmin, zz); zmax = Math.max(zmax, zz); }
      }
      const cx = sx / cells.length, cy = sy / cells.length;
      if (zmax - zmin > maxH) continue;
      // spot: interior cell (8 neighbours same patch class) with the best road access, else nearest to the centroid
      const interior = cells.filter(([i, j]) => [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [1, -1], [-1, 1], [-1, -1]].every(([di, dj]) => want.has(at(i + di, j + dj))));
      const pool = interior.length ? interior : cells;
      let best = null;
      for (const [i, j] of pool) {
        const [x, y] = cellXY(i, j);
        const zz = m.z[j * m.nx + i] ?? 0;
        const near = ctx.roads.nearestNodes(x, y, null, { count: 1, maxDistance: maxRoad + 1 })[0];
        if (!near) continue;
        const d = near.distance;
        if (d > maxRoad) continue;
        // prefer deep inside but close to the road, near the centroid
        const score = d + 0.15 * Math.hypot(x - cx, y - cy);
        if (!best || score < best.score) best = { score, x, y, z: zz, node: near.node.id, d };
      }
      if (!best) continue;
      if (!inRegion(a.region, best.x, best.y)) continue;
      if ((a.avoid || []).some((c) => Math.hypot(c.x - best.x, c.y - best.y) < c.radius)) continue;
      patches.push({
        spot: { x: best.x, y: best.y, z: best.z }, interiorSpot: interior.length > 0, cells: cells.length, areaM2: cells.length * m.step * m.step,
        centroid: { x: Math.round(cx), y: Math.round(cy) }, heightRange: Math.round((zmax - zmin) * 10) / 10,
        road: { node: best.node, distance: Math.round(best.d * 10) / 10 },
      });
    }
    patches.sort((p, q) => q.cells - p.cells);
    const out = [];
    for (const p of patches) {
      if (a.minSpacing && out.some((o) => Math.hypot(o.spot.x - p.spot.x, o.spot.y - p.spot.y) < a.minSpacing)) continue;
      out.push(p);
      if (out.length >= (a.limit || 50)) break;
    }
    return { map: key, surfaces: a.surfaces || ['grass'], total: patches.length, returned: out.length, patches: out, mapComplete: e.meta.complete };
  },
});
