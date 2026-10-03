import { z } from 'zod';
import { defineTool } from './registry.js';
import { point } from './schemas.js';
import { ToolError } from '../errors.js';
import { round, compass, headingTo, dist2 } from '../geo.js';

const nodeOrThrow = (roads, id) => {
  const n = roads.get(id);
  if (!n) throw new ToolError('ROAD_NODE_NOT_FOUND', `Road node ${id} does not exist.`, { suggestion: 'Use get_nearest_road_node to find node ids.' });
  return n;
};

async function liveGeometry(ctx, nodes) {
  // cross-section at each node, perpendicular to its road heading
  const list = nodes.slice(0, 60).map((n) => ({ id: n.id, x: n.x, y: n.y, z: n.z, heading: ctx.roads.roadHeading(n)?.heading ?? 0 }));
  if (!list.length) return null;
  try {
    const r = await ctx.call('roads', 'probeNodes', { nodes: list }, { timeoutMs: 60000 });
    return r.nodes;
  } catch (e) {
    return { unavailable: e.code, message: e.message };
  }
}

defineTool({
  name: 'get_nearest_road_node',
  module: 'roads', kind: 'read', needsProbe: false,
  title: 'Nearest road node(s)',
  description: 'Nearest vehicle-path nodes (v_radar road graph) to a location: id, position, type (road / intersection / dead_end), links with heading + compass + distance + direction, default road heading, distance and compass direction from the query point. filter "intersection" returns only junctions. Uses 3D distance when z is known (bridges / tunnels). Read-only, no probe needed.',
  input: { position: point.optional(), count: z.number().int().min(1).max(50).optional(), maxDistance: z.number().optional(), filter: z.enum(['any', 'intersection', 'road', 'dead_end']).optional() },
  returns: ['nodes[] {id, position, type, links[], roadHeading, distance, direction}'],
  related: ['get_road_node', 'get_nearest_road_segment', 'place_entity (mode road)'],
  async handler(a, ctx) {
    const p = await ctx.locate(a.position);
    const f = a.filter && a.filter !== 'any' ? (n) => ctx.roads.nodeType(n) === a.filter : undefined;
    const res = ctx.roads.nearestNodes(p.x, p.y, p.z, { count: a.count || 1, maxDistance: a.maxDistance || 500, filter: f });
    return {
      from: { x: round(p.x), y: round(p.y), z: p.z !== undefined ? round(p.z) : undefined, source: p.source },
      nodes: res.map((r) => ({ ...ctx.roads.describe(r.node), distance: round(r.distance, 2), direction: compass(headingTo(p.x, p.y, r.node.x, r.node.y)) })),
    };
  },
});

defineTool({
  name: 'get_road_node',
  module: 'roads', kind: 'read', needsProbe: 'partial',
  title: 'Road node details',
  description: 'One road node: position, type, links (heading/compass/distance/direction), road heading, the road stretch it belongs to (nodes between the surrounding intersections) and zone. live = true adds the measured road cross-section at the node (width, lanes estimate, sidewalks, road models) from the game. Read-only.',
  input: { id: z.number().int(), live: z.boolean().optional() },
  returns: ['node', 'stretch', 'zone', 'live cross-section (optional)'],
  related: ['get_connected_road_nodes', 'get_road_cross_section'],
  async handler(a, ctx) {
    const n = nodeOrThrow(ctx.roads, a.id);
    const out = { node: ctx.roads.describe(n), stretch: ctx.roads.stretch(n.id) };
    try { out.zone = (await ctx.call('world', 'zoneAt', { position: { x: n.x, y: n.y, z: n.z } })).zone; } catch { /* bridge offline */ }
    if (a.live) out.live = (await liveGeometry(ctx, [n]))?.[0] ?? null;
    if (out.stretch && out.stretch.nodes?.length > 40) out.stretch.nodes = [...out.stretch.nodes.slice(0, 20), '...', ...out.stretch.nodes.slice(-20)];
    return out;
  },
});

defineTool({
  name: 'get_connected_road_nodes',
  module: 'roads', kind: 'read', needsProbe: false,
  title: 'Road graph neighbourhood',
  description: 'Local road graph around a node: every node within `depth` link hops with its hop distance, type and links. Use to understand junction layouts and pick towardNode for road placement. Read-only.',
  input: { id: z.number().int(), depth: z.number().int().min(1).max(8).optional() },
  returns: ['nodes[] {id, hops, position, type, links}'],
  related: ['get_road_node', 'find_road_path'],
  async handler(a, ctx) {
    nodeOrThrow(ctx.roads, a.id);
    const hood = ctx.roads.neighbourhood(a.id, a.depth || 1);
    return {
      root: a.id, depth: a.depth || 1,
      nodes: [...hood.entries()].map(([id, hops]) => ({ hops, ...ctx.roads.describe(ctx.roads.get(id)) })).sort((p, q) => p.hops - q.hops),
    };
  },
});

defineTool({
  name: 'get_road_segment',
  module: 'roads', kind: 'read', needsProbe: 'partial',
  title: 'Road segment between two nodes',
  description: 'The link between two adjacent nodes oriented from -> to: length, heading, compass, grade %, directions, endpoints, midpoint, plus the whole stretch. live = true adds a measured cross-section at the midpoint. Read-only.',
  input: { from: z.number().int(), to: z.number().int(), live: z.boolean().optional() },
  returns: ['segment', 'stretch', 'live cross-section'],
  related: ['get_nearest_road_segment', 'place_entity (mode road with segment)'],
  async handler(a, ctx) {
    const s = ctx.roads.segment(a.from, a.to);
    if (!s) throw new ToolError('NOT_A_SEGMENT', `Nodes ${a.from} and ${a.to} are not directly linked.`, { suggestion: 'Use get_connected_road_nodes or find_road_path.' });
    const out = { segment: ctx.roads.describeSegment(s, Number(a.from)), stretch: ctx.roads.stretch(a.from) };
    if (out.stretch?.nodes?.length > 40) out.stretch.nodes = [...out.stretch.nodes.slice(0, 20), '...', ...out.stretch.nodes.slice(-20)];
    if (a.live) {
      const m = out.segment.midpoint;
      out.live = await ctx.call('roads', 'crossSection', { position: m, heading: out.segment.heading });
    }
    return out;
  },
});

defineTool({
  name: 'get_nearest_road_segment',
  module: 'roads', kind: 'read', needsProbe: false,
  title: 'Nearest road segment',
  description: 'Projects a location onto the nearest road segments: closest point, distance to the road line, signed lateral offset (+ = right of from->to), position along the segment (t), segment heading. For an entity also reports its heading relative to the road. Read-only.',
  input: { position: point.optional(), count: z.number().int().min(1).max(10).optional(), maxDistance: z.number().optional() },
  returns: ['segments[] {from, to, closestPoint, distance, lateralOffset, t, heading}'],
  related: ['get_nearest_road_node', 'orient_entity (align_to_road)'],
  async handler(a, ctx) {
    const p = await ctx.locate(a.position);
    const res = ctx.roads.nearestSegments(p.x, p.y, p.z, { count: a.count || 1, maxDistance: a.maxDistance || 300 });
    return {
      from: { x: round(p.x), y: round(p.y), z: p.z !== undefined ? round(p.z) : undefined, heading: p.heading, source: p.source },
      segments: res.map((s) => ({
        from: s.a.id, to: s.b.id, closestPoint: { x: round(s.x), y: round(s.y), z: round(s.z) },
        distance: round(s.distance, 2), lateralOffset: round(s.lateral, 2), t: round(s.t, 3),
        heading: round(s.heading, 1), compass: compass(s.heading), length: round(s.seg.length, 2),
        headingVsYours: p.heading !== undefined ? round(((s.heading - p.heading + 540) % 360) - 180, 1) : undefined,
      })),
    };
  },
});

defineTool({
  name: 'find_road_path',
  module: 'roads', kind: 'read', needsProbe: false,
  title: 'Route on the road network',
  description: 'A* route over the road graph between two locations (node ids, points, entities or "player"; points snap to the nearest node). Returns length, node count, turn-by-turn steps at intersections and (optionally) the node list / waypoints. respectDirection follows only the listed link directions. Read-only.',
  input: {
    from: z.union([z.number().int(), point]), to: z.union([z.number().int(), point]),
    respectDirection: z.boolean().optional(), includeNodes: z.boolean().optional(), waypointSpacing: z.number().optional().describe('metres between returned waypoints (default 50)'),
  },
  returns: ['found', 'length', 'steps[]', 'waypoints[]', 'nodes[] (optional)'],
  related: ['get_nearest_road_node', 'set_debug_overlay (road nodes)'],
  async handler(a, ctx) {
    const resolve = async (v) => {
      if (typeof v === 'number') return nodeOrThrow(ctx.roads, v);
      const p = await ctx.locate(v);
      const [r] = ctx.roads.nearestNodes(p.x, p.y, p.z, { count: 1, maxDistance: 1000 });
      if (!r) throw new ToolError('NO_ROAD_NEARBY', 'No road node within 1 km.');
      return r.node;
    };
    const A = await resolve(a.from), B = await resolve(a.to);
    const r = ctx.roads.path(A.id, B.id, { respectDirection: a.respectDirection });
    if (!r || !r.found) return { found: false, from: A.id, to: B.id, expanded: r?.expanded, suggestion: 'The nodes may be on disconnected networks; try without respectDirection.' };
    const spacing = a.waypointSpacing || 50;
    const wps = [];
    let acc = spacing;
    for (let i = 0; i < r.nodes.length; i++) {
      const n = ctx.roads.get(r.nodes[i]);
      if (i > 0) { const p = ctx.roads.get(r.nodes[i - 1]); acc += dist2(p.x, p.y, n.x, n.y); }
      if (acc >= spacing || i === r.nodes.length - 1) { wps.push({ node: n.id, x: round(n.x, 1), y: round(n.y, 1), z: round(n.z, 1) }); acc = 0; }
    }
    return {
      found: true, from: A.id, to: B.id, length: round(r.length, 1), nodeCount: r.nodes.length,
      steps: ctx.roads.instructions(r.nodes), waypoints: wps, nodes: a.includeNodes ? r.nodes : undefined,
    };
  },
});

defineTool({
  name: 'inspect_road_area',
  module: 'roads', kind: 'read', needsProbe: 'partial',
  title: 'Road network in an area',
  description: 'Local road network around a location: nodes (count), intersections with leg headings, dead ends, segments, road stretches; live = true measures the real road geometry at intersections / sample nodes (width, lanes estimate, sidewalks, curb height, road model names) to correlate the graph with the game world. Read-only.',
  input: { center: point.optional(), radius: z.number().min(10).max(500).optional(), live: z.boolean().optional(), maxLiveNodes: z.number().int().max(60).optional() },
  returns: ['intersections[]', 'deadEnds[]', 'segments[]', 'stretches[]', 'live[] cross-sections'],
  related: ['get_road_cross_section', 'inspect_area', 'set_debug_overlay'],
  async handler(a, ctx) {
    const c = await ctx.locate(a.center);
    const radius = a.radius || 80;
    const nodes = ctx.roads.nodesWithin(c.x, c.y, radius);
    const ids = new Set(nodes.map((n) => n.id));
    const segs = [];
    for (const n of nodes) for (const to of n.adj) if (n.id < to && ids.has(to)) segs.push(ctx.roads.segment(n.id, to));
    const inter = nodes.filter((n) => n.adj.size >= 3);
    const stretches = new Map();
    for (const n of nodes) {
      if (n.adj.size !== 2) continue;
      const st = ctx.roads.stretch(n.id);
      const key = st.nodes[0] < st.nodes.at(-1) ? `${st.nodes[0]}-${st.nodes.at(-1)}` : `${st.nodes.at(-1)}-${st.nodes[0]}`;
      if (!stretches.has(key)) stretches.set(key, { endpoints: st.endpoints.map((e) => ({ id: e.id, type: e.type })), length: st.length, nodeCount: st.nodeCount, overallHeading: st.overallHeading });
    }
    const out = {
      center: { x: round(c.x), y: round(c.y), z: c.z !== undefined ? round(c.z) : undefined }, radius,
      nodeCount: nodes.length, segmentCount: segs.length,
      intersections: inter.map((n) => ({ ...ctx.roads.describe(n), distance: round(dist2(c.x, c.y, n.x, n.y), 1), direction: compass(headingTo(c.x, c.y, n.x, n.y)) })).sort((p, q) => p.distance - q.distance),
      deadEnds: nodes.filter((n) => n.adj.size === 1).map((n) => ({ id: n.id, position: { x: n.x, y: n.y, z: n.z } })),
      segments: segs.slice(0, 150).map((s) => ({ from: s.a, to: s.b, length: round(s.length, 1), heading: round(s.heading, 1), bidirectional: s.bidirectional })),
      stretches: [...stretches.values()],
    };
    if (a.live) {
      const sample = [...inter];
      for (const n of nodes) if (sample.length < (a.maxLiveNodes || 20) && n.adj.size === 2 && !sample.includes(n)) sample.push(n);
      out.live = await liveGeometry(ctx, sample.slice(0, a.maxLiveNodes || 20));
    }
    return out;
  },
});

defineTool({
  name: 'get_road_cross_section',
  module: 'roads', kind: 'read', needsProbe: true,
  title: 'Measured road cross-section',
  description: 'Measures the real road across a heading at a point / node by raycasting the game collision: road surface span (left/right edge offsets, width, centre offset), lane estimate per direction + lane width, layout (two-way vs one-way/separate carriageway), sidewalks with curb height, road world models (dff names), and the surface profile. Offsets: + = right of the heading. With node only, the node road heading is used. Read-only.',
  input: { node: z.number().int().optional(), position: point.optional(), heading: z.number().optional(), halfWidth: z.number().optional(), includeSamples: z.boolean().optional() },
  returns: ['road {leftEdge, rightEdge, width, center, lanesPerDirection, laneWidth, twoWay, models}', 'sidewalkLeft/Right', 'profile[]'],
  related: ['place_entity (mode road)', 'inspect_road_area'],
  limitations: ['Lanes are estimated from width (the node data has no lane info); roads whose collision uses the DEFAULT surface are recognised only by road-like model names.'],
  async handler(a, ctx) {
    let position = a.position, heading = a.heading;
    if (a.node !== undefined) {
      const n = nodeOrThrow(ctx.roads, a.node);
      position = { x: n.x, y: n.y, z: n.z };
      if (heading === undefined) heading = ctx.roads.roadHeading(n)?.heading ?? 0;
    } else {
      const p = await ctx.locate(position);
      position = { x: p.x, y: p.y, z: p.z };
      if (heading === undefined) {
        const [s] = ctx.roads.nearestSegments(p.x, p.y, p.z, { count: 1, maxDistance: 200 });
        heading = s ? s.heading : p.heading ?? 0;
      }
    }
    return ctx.call('roads', 'crossSection', { position, heading, halfWidth: a.halfWidth, includeSamples: a.includeSamples });
  },
});
