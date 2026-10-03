// Road network from assets/vehiclenodes.lua (the vehicle path nodes used by v_radar's GPS).
//
// File shape: vehicleNodes = { [area] = { [nodeId] = { x, y, z, id, neighbours = { [id] = cost } } } }
// with nodeId = area * 65536 + index. The data has positions and links only: no lane
// counts, widths or one-way flags (a link listed in one direction only is reported
// as possibly one-way). Live road geometry comes from the bridge (cross-sections).
//
// Indexes: id -> node, adjacency (undirected + directed), uniform spatial grid of
// nodes and segments (CELL m), lazily built road stretches between intersections.

import fs from 'node:fs';
import { headingTo, angleDiff, dist2, dist3, round, compass, projectOnSegment, norm } from '../geo.js';

const CELL = 64;

export class RoadGraph {
  constructor() {
    this.nodes = new Map(); // id -> { id, area, x, y, z, out: Map(id -> cost), adj: Set(id) }
    this.segments = []; // { a, b, length, heading, bidirectional }
    this.segIndex = new Map(); // "a:b" (a<b) -> segment
    this.grid = new Map(); // "cx:cy" -> { nodes: [], segs: [] }
    this.loadedAt = null;
    this.loadMs = 0;
    this.source = null;
    this.stretchCache = new Map();
  }

  static parse(text) {
    const src = text.replace(/--[^\n]*/g, '');
    const nodes = [];
    const re = /\[(\d+)\]\s*=\s*\{([^{}]*?)neighbours\s*=\s*\{([^{}]*)\}([^{}]*)\}/g;
    let m;
    while ((m = re.exec(src))) {
      const fields = {};
      for (const f of (m[2] + m[4]).matchAll(/(\w+)\s*=\s*(-?[\d.]+(?:e-?\d+)?)/g)) fields[f[1]] = Number(f[2]);
      const out = new Map();
      for (const n of m[3].matchAll(/\[(\d+)\]\s*=\s*(-?[\d.]+)/g)) out.set(Number(n[1]), Number(n[2]));
      const id = fields.id ?? Number(m[1]);
      if (Number.isFinite(fields.x) && Number.isFinite(fields.y)) nodes.push({ id, x: fields.x, y: fields.y, z: fields.z ?? 0, out });
    }
    return nodes;
  }

  load(file) {
    const t0 = Date.now();
    const text = fs.readFileSync(file, 'utf8');
    const parsed = RoadGraph.parse(text);
    for (const n of parsed) {
      this.nodes.set(n.id, { id: n.id, area: Math.floor(n.id / 65536), x: n.x, y: n.y, z: n.z, out: n.out, adj: new Set() });
    }
    let dangling = 0;
    for (const n of this.nodes.values()) {
      for (const to of n.out.keys()) {
        const o = this.nodes.get(to);
        if (!o) { dangling++; continue; }
        n.adj.add(to);
        o.adj.add(n.id);
      }
    }
    for (const n of this.nodes.values()) {
      for (const to of n.adj) {
        if (n.id < to) {
          const o = this.nodes.get(to);
          const seg = {
            a: n.id, b: to,
            length: dist3(n.x, n.y, n.z, o.x, o.y, o.z),
            heading: headingTo(n.x, n.y, o.x, o.y),
            bidirectional: n.out.has(to) && o.out.has(n.id),
            dirAB: n.out.has(to), dirBA: o.out.has(n.id),
          };
          this.segments.push(seg);
          this.segIndex.set(`${n.id}:${to}`, seg);
        }
      }
      this.#cell(n.x, n.y).nodes.push(n);
    }
    for (const s of this.segments) {
      const a = this.nodes.get(s.a), b = this.nodes.get(s.b);
      const x0 = Math.floor(Math.min(a.x, b.x) / CELL), x1 = Math.floor(Math.max(a.x, b.x) / CELL);
      const y0 = Math.floor(Math.min(a.y, b.y) / CELL), y1 = Math.floor(Math.max(a.y, b.y) / CELL);
      for (let cx = x0; cx <= x1; cx++) for (let cy = y0; cy <= y1; cy++) this.#cellAt(cx, cy).segs.push(s);
    }
    this.dangling = dangling;
    this.loadedAt = new Date().toISOString();
    this.loadMs = Date.now() - t0;
    this.source = file;
    return this;
  }

  #cellAt(cx, cy) {
    const k = `${cx}:${cy}`;
    let c = this.grid.get(k);
    if (!c) { c = { nodes: [], segs: [] }; this.grid.set(k, c); }
    return c;
  }
  #cell(x, y) { return this.#cellAt(Math.floor(x / CELL), Math.floor(y / CELL)); }

  *#cellsAround(x, y, radius) {
    const x0 = Math.floor((x - radius) / CELL), x1 = Math.floor((x + radius) / CELL);
    const y0 = Math.floor((y - radius) / CELL), y1 = Math.floor((y + radius) / CELL);
    for (let cx = x0; cx <= x1; cx++) for (let cy = y0; cy <= y1; cy++) {
      const c = this.grid.get(`${cx}:${cy}`);
      if (c) yield c;
    }
  }

  stats() {
    let inter = 0, dead = 0, oneway = 0;
    for (const n of this.nodes.values()) {
      if (n.adj.size >= 3) inter++;
      else if (n.adj.size <= 1) dead++;
    }
    for (const s of this.segments) if (!s.bidirectional) oneway++;
    const total = this.segments.reduce((a, s) => a + s.length, 0);
    return {
      nodes: this.nodes.size, segments: this.segments.length, intersections: inter, deadEnds: dead,
      singleDirectionLinks: oneway, totalLengthKm: round(total / 1000, 1), gridCells: this.grid.size, cellSize: CELL,
      danglingLinks: this.dangling, loadMs: this.loadMs, loadedAt: this.loadedAt, source: this.source,
    };
  }

  get(id) {
    return this.nodes.get(Number(id));
  }

  nodeType(n) {
    const d = n.adj.size;
    return d >= 3 ? 'intersection' : d === 2 ? 'road' : d === 1 ? 'dead_end' : 'isolated';
  }

  /** Public view of a node. */
  describe(n, { links = true } = {}) {
    if (!n) return null;
    const out = {
      id: n.id, area: n.area, position: { x: n.x, y: n.y, z: n.z },
      type: this.nodeType(n), degree: n.adj.size,
    };
    if (links) {
      out.links = [...n.adj].map((id) => {
        const o = this.nodes.get(id);
        const h = headingTo(n.x, n.y, o.x, o.y);
        return {
          id, heading: round(h, 1), compass: compass(h), distance: round(dist3(n.x, n.y, n.z, o.x, o.y, o.z), 2),
          direction: n.out.has(id) && o.out.has(n.id) ? 'both' : n.out.has(id) ? 'outgoing only' : 'incoming only',
        };
      }).sort((a, b) => a.heading - b.heading);
      out.roadHeading = this.roadHeading(n);
    }
    return out;
  }

  /** Travel heading through a node (road nodes: prev->next; else first link). */
  roadHeading(n) {
    const links = [...n.adj].sort((a, b) => a - b).map((id) => this.nodes.get(id));
    if (links.length === 2) {
      const [p, q] = links;
      const h = headingTo(p.x, p.y, q.x, q.y);
      return { heading: round(h, 1), compass: compass(h), from: p.id, to: q.id, note: 'from the lower-id neighbour to the higher-id one; the opposite direction is heading+180' };
    }
    if (links.length >= 1) {
      const h = headingTo(n.x, n.y, links[0].x, links[0].y);
      return { heading: round(h, 1), compass: compass(h), from: n.id, to: links[0].id, note: links.length > 2 ? 'intersection: see links for every direction' : 'dead end: towards its only neighbour' };
    }
    return null;
  }

  nearestNodes(x, y, z, { count = 1, maxDistance = 300, filter } = {}) {
    let radius = 32;
    let found = [];
    while (radius <= maxDistance * 1.01 || found.length === 0) {
      found = [];
      for (const c of this.#cellsAround(x, y, radius)) {
        for (const n of c.nodes) {
          if (filter && !filter(n)) continue;
          const d2 = dist2(x, y, n.x, n.y);
          if (d2 > Math.min(radius, maxDistance)) continue;
          const d = z === undefined || z === null ? d2 : Math.hypot(d2, (n.z - z) * 1.5);
          found.push({ n, d, d2 });
        }
      }
      if (found.length >= count || radius >= maxDistance) break;
      radius *= 2;
    }
    found.sort((a, b) => a.d - b.d);
    return found.slice(0, count).map((f) => ({ node: f.n, distance: f.d2, weighted: f.d }));
  }

  nearestSegments(x, y, z, { count = 1, maxDistance = 200 } = {}) {
    const seen = new Set();
    const out = [];
    for (const c of this.#cellsAround(x, y, maxDistance)) {
      for (const s of c.segs) {
        const key = `${s.a}:${s.b}`;
        if (seen.has(key)) continue;
        seen.add(key);
        const a = this.nodes.get(s.a), b = this.nodes.get(s.b);
        const p = projectOnSegment(a.x, a.y, b.x, b.y, x, y);
        if (p.distance > maxDistance) continue;
        const zOn = a.z + (b.z - a.z) * p.t;
        const weighted = z === undefined || z === null ? p.distance : Math.hypot(p.distance, (zOn - z) * 1.5);
        out.push({ seg: s, a, b, ...p, z: zOn, weighted });
      }
    }
    out.sort((p, q) => p.weighted - q.weighted);
    return out.slice(0, count);
  }

  segment(a, b) {
    a = Number(a); b = Number(b);
    return this.segIndex.get(a < b ? `${a}:${b}` : `${b}:${a}`) || null;
  }

  describeSegment(s, from) {
    const a = this.nodes.get(s.a), b = this.nodes.get(s.b);
    const [p, q] = from === s.b ? [b, a] : [a, b];
    const h = headingTo(p.x, p.y, q.x, q.y);
    return {
      from: p.id, to: q.id, length: round(s.length, 2), heading: round(h, 1), compass: compass(h),
      grade: round(((q.z - p.z) / Math.max(0.01, dist2(p.x, p.y, q.x, q.y))) * 100, 1),
      bidirectional: s.bidirectional,
      directions: s.bidirectional ? 'both' : (p.id === s.a ? (s.dirAB ? 'from->to only' : 'to->from only') : (s.dirBA ? 'from->to only' : 'to->from only')),
      fromPosition: { x: p.x, y: p.y, z: p.z }, toPosition: { x: q.x, y: q.y, z: q.z },
      midpoint: { x: round((p.x + q.x) / 2), y: round((p.y + q.y) / 2), z: round((p.z + q.z) / 2) },
    };
  }

  /** Nodes within radius (2D). */
  nodesWithin(x, y, radius) {
    const out = [];
    for (const c of this.#cellsAround(x, y, radius)) for (const n of c.nodes) if (dist2(x, y, n.x, n.y) <= radius) out.push(n);
    return out;
  }

  /** Breadth-first neighbourhood up to depth. */
  neighbourhood(id, depth = 1) {
    const start = this.get(id);
    if (!start) return null;
    const seen = new Map([[start.id, 0]]);
    let frontier = [start.id];
    for (let d = 1; d <= depth; d++) {
      const next = [];
      for (const nid of frontier) for (const to of this.nodes.get(nid).adj) if (!seen.has(to)) { seen.set(to, d); next.push(to); }
      frontier = next;
    }
    return seen;
  }

  /** Road stretch: walk from node along degree-2 nodes in both directions until intersections / dead ends. */
  stretch(id) {
    const start = this.get(id);
    if (!start) return null;
    if (start.adj.size !== 2) return { nodes: [start.id], endpoints: [start.id, start.id], length: 0, note: 'node is an ' + this.nodeType(start) };
    const walk = (prev, cur) => {
      const list = [];
      let guard = 0;
      while (guard++ < 5000) {
        list.push(cur);
        const n = this.nodes.get(cur);
        if (n.adj.size !== 2) break;
        const next = [...n.adj].find((x) => x !== prev);
        if (next === undefined || next === start.id) break;
        prev = cur;
        cur = next;
      }
      return list;
    };
    const [l, r] = [...start.adj];
    const left = walk(start.id, l).reverse();
    const right = walk(start.id, r);
    const ids = [...left, start.id, ...right];
    let len = 0;
    for (let i = 1; i < ids.length; i++) {
      const p = this.nodes.get(ids[i - 1]), q = this.nodes.get(ids[i]);
      len += dist3(p.x, p.y, p.z, q.x, q.y, q.z);
    }
    const e0 = this.nodes.get(ids[0]), e1 = this.nodes.get(ids[ids.length - 1]);
    return {
      nodes: ids, nodeCount: ids.length, length: round(len, 1),
      endpoints: [
        { id: e0.id, type: this.nodeType(e0), position: { x: e0.x, y: e0.y, z: e0.z } },
        { id: e1.id, type: this.nodeType(e1), position: { x: e1.x, y: e1.y, z: e1.z } },
      ],
      overallHeading: round(headingTo(e0.x, e0.y, e1.x, e1.y), 1),
    };
  }

  /** A* shortest path between node ids. respectDirection: only follow listed (directed) links. */
  path(fromId, toId, { respectDirection = false, maxNodes = 200000 } = {}) {
    const start = this.get(fromId), goal = this.get(toId);
    if (!start || !goal) return null;
    const g = new Map([[start.id, 0]]);
    const came = new Map();
    const open = new MinHeap();
    open.push(start.id, dist3(start.x, start.y, start.z, goal.x, goal.y, goal.z));
    const closed = new Set();
    let expanded = 0;
    while (open.size) {
      const cur = open.pop();
      if (cur === goal.id) break;
      if (closed.has(cur)) continue;
      closed.add(cur);
      if (++expanded > maxNodes) return null;
      const n = this.nodes.get(cur);
      const nexts = respectDirection ? n.out.keys() : n.adj;
      for (const to of nexts) {
        const o = this.nodes.get(to);
        if (!o || closed.has(to)) continue;
        const cost = g.get(cur) + dist3(n.x, n.y, n.z, o.x, o.y, o.z);
        if (cost < (g.get(to) ?? Infinity)) {
          g.set(to, cost);
          came.set(to, cur);
          open.push(to, cost + dist3(o.x, o.y, o.z, goal.x, goal.y, goal.z));
        }
      }
    }
    if (!g.has(goal.id)) return { found: false, expanded };
    const ids = [goal.id];
    while (ids[0] !== start.id) ids.unshift(came.get(ids[0]));
    return { found: true, nodes: ids, length: g.get(goal.id), expanded };
  }

  /** Turn-by-turn summary of a node path. */
  instructions(ids) {
    const steps = [];
    let segStart = 0, acc = 0;
    for (let i = 1; i < ids.length; i++) {
      const p = this.nodes.get(ids[i - 1]), q = this.nodes.get(ids[i]);
      acc += dist2(p.x, p.y, q.x, q.y);
      if (i < ids.length - 1 && q.adj.size >= 3) {
        const r = this.nodes.get(ids[i + 1]);
        const turn = angleDiff(headingTo(p.x, p.y, q.x, q.y), headingTo(q.x, q.y, r.x, r.y));
        const what = Math.abs(turn) < 25 ? 'straight' : turn > 0 ? (turn > 120 ? 'u-turn left' : 'turn left') : (turn < -120 ? 'u-turn right' : 'turn right');
        steps.push({ atNode: q.id, afterMeters: round(acc, 0), action: what, turnDegrees: round(turn, 0), position: { x: q.x, y: q.y, z: q.z }, newHeading: round(headingTo(q.x, q.y, r.x, r.y), 1) });
        acc = 0;
        segStart = i;
      }
    }
    steps.push({ action: 'arrive', afterMeters: round(acc, 0), atNode: ids[ids.length - 1] });
    void segStart;
    return steps;
  }

  /** Heading of travel towards a neighbour, or the neighbour best matching a heading hint. */
  directionAt(n, { towardNode, heading, fromNode } = {}) {
    const links = [...n.adj].map((id) => this.nodes.get(id));
    if (!links.length) return null;
    if (towardNode !== undefined) {
      const t = this.nodes.get(Number(towardNode));
      if (!t) return null;
      return { heading: norm(headingTo(n.x, n.y, t.x, t.y)), toward: t.id, basis: n.adj.has(t.id) ? 'neighbour' : 'direct line to a non-adjacent node' };
    }
    if (fromNode !== undefined) {
      const f = this.nodes.get(Number(fromNode));
      if (f) return { heading: norm(headingTo(f.x, f.y, n.x, n.y)), from: f.id, basis: 'continuing from fromNode' };
    }
    if (heading !== undefined) {
      let best = null;
      for (const o of links) {
        const h = headingTo(n.x, n.y, o.x, o.y);
        const d = Math.abs(angleDiff(heading, h));
        if (!best || d < best.d) best = { d, h, id: o.id };
      }
      return { heading: best.h, toward: best.id, basis: `neighbour closest to heading ${round(heading, 1)}` };
    }
    const rh = this.roadHeading(n);
    return { heading: rh.heading, toward: rh.to, basis: 'default road direction (lower-id -> higher-id neighbour)' };
  }
}

class MinHeap {
  constructor() { this.a = []; }
  get size() { return this.a.length; }
  push(v, p) {
    const a = this.a;
    a.push({ v, p });
    let i = a.length - 1;
    while (i > 0) {
      const j = (i - 1) >> 1;
      if (a[j].p <= a[i].p) break;
      [a[i], a[j]] = [a[j], a[i]];
      i = j;
    }
  }
  pop() {
    const a = this.a;
    const top = a[0];
    const last = a.pop();
    if (a.length) {
      a[0] = last;
      let i = 0;
      for (;;) {
        const l = 2 * i + 1, r = l + 1;
        let m = i;
        if (l < a.length && a[l].p < a[m].p) m = l;
        if (r < a.length && a[r].p < a[m].p) m = r;
        if (m === i) break;
        [a[i], a[m]] = [a[m], a[i]];
        i = m;
      }
    }
    return top.v;
  }
}
