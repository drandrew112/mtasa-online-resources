import { z } from 'zod';
import { defineTool } from './registry.js';
import { point, detail } from './schemas.js';
import { round, compass, headingTo, dist2, angleDiff } from '../geo.js';

/** Road context around a point from the road graph (cheap, no bridge call). */
export function roadContext(roads, x, y, z, radius = 60, { heading, detail: d = 'medium' } = {}) {
  const [nn] = roads.nearestNodes(x, y, z, { count: 1, maxDistance: Math.max(radius, 400) });
  const [ns] = roads.nearestSegments(x, y, z, { count: 1, maxDistance: Math.max(radius, 400) });
  const nodes = roads.nodesWithin(x, y, radius);
  const inter = nodes.filter((n) => n.adj.size >= 3)
    .map((n) => ({ id: n.id, position: { x: n.x, y: n.y, z: n.z }, legs: n.adj.size, distance: round(dist2(x, y, n.x, n.y), 1), direction: compass(headingTo(x, y, n.x, n.y)) }))
    .sort((a, b) => a.distance - b.distance);
  const out = {
    source: 'vehiclenodes road graph (positions/links only; widths and lanes come from get_road_cross_section)',
    nodesWithinRadius: nodes.length,
    intersections: d === 'low' ? inter.slice(0, 3) : inter.slice(0, 12),
  };
  if (nn) {
    out.nearestNode = { ...roads.describe(nn.node, { links: d !== 'low' }), distance: round(nn.distance, 2), direction: compass(headingTo(x, y, nn.node.x, nn.node.y)) };
  }
  if (ns) {
    const segHeading = ns.heading;
    const side = ns.lateral > 0.5 ? 'right of the from->to direction' : ns.lateral < -0.5 ? 'left of the from->to direction' : 'on the node line';
    out.nearestRoad = {
      segment: { from: ns.a.id, to: ns.b.id }, distanceToRoadLine: round(ns.distance, 2), lateralOffset: round(ns.lateral, 2), side,
      roadHeading: round(segHeading, 1), roadCompass: compass(segHeading), closestPoint: { x: round(ns.x), y: round(ns.y), z: round(ns.z) },
      note: 'Road line = straight line between nodes (usually the road centre for two-way roads).',
    };
    if (heading !== undefined) {
      const diff = angleDiff(segHeading, heading);
      out.nearestRoad.yourHeadingVsRoad = round(diff, 1);
      out.nearestRoad.alignment = Math.abs(diff) < 20 ? 'along the road (from->to)' : Math.abs(diff) > 160 ? 'along the road (to->from)' : Math.abs(Math.abs(diff) - 90) < 20 ? 'perpendicular to the road' : 'angled';
    }
    if (d !== 'low') {
      const st = roads.stretch(ns.a.adj.size === 2 ? ns.a.id : ns.b.id);
      if (st && st.nodeCount > 1) out.nearestRoad.stretch = { length: st.length, nodeCount: st.nodeCount, endpoints: st.endpoints };
    }
  }
  return out;
}

defineTool({
  name: 'get_current_location_context',
  module: 'world', kind: 'read', needsProbe: 'partial',
  title: 'What is around me?',
  description: 'Answers "what is around me / where am I": position, heading, zone/city, ground (height, surface, slope, water), nearest road node and road line (with your alignment to it), nearby intersections, nearby vehicles/peds/objects/players with distance and compass direction, world-model summary and area type. Centre defaults to the probe player. Read-only. low = fast summary, medium/high = more models, open/blocked directions.',
  input: { center: point.optional(), detail: detail.optional(), radius: z.number().min(5).max(300).optional() },
  returns: ['position/heading/zone', 'ground', 'roads (nearest node, road line, intersections)', 'nearby elements', 'geometry summary + areaType'],
  related: ['inspect_area', 'get_area_summary', 'get_nearest_road_node', 'capture_screenshot'],
  limitations: ['Geometry needs a probe client; without one only elements, zone and roads are returned.'],
  async handler(a, ctx) {
    const center = await ctx.bridgePoint(a.center);
    const r = await ctx.call('world', 'context', { center, detail: a.detail || 'low', radius: a.radius });
    r.roads = roadContext(ctx.roads, r.position.x, r.position.y, r.position.z, a.radius || 80, { heading: r.heading, detail: a.detail || 'low' });
    return r;
  },
});

defineTool({
  name: 'inspect_area',
  module: 'world', kind: 'read', needsProbe: 'partial',
  title: 'Inspect an area',
  description: 'Structured inspection of an area: MTA elements (vehicles, peds, objects, players; workspace entities flagged), world geometry from a raycast grid (world models with ids/dff names/positions/rotations and kind, surface mix, terrain heights/slope, covered %, area type, open directions), and the road network (nodes, intersections, nearest road). detail low|medium|high controls scan density and list sizes; high also measures real bounds of the main world models. Far-away centres move the probe camera temporarily. Read-only.',
  input: {
    center: point.optional().describe('default: probe player'),
    radius: z.number().min(5).max(400).optional().describe('metres, default 50'),
    detail: detail.optional(),
    include: z.object({ elements: z.boolean().optional(), geometry: z.boolean().optional(), roads: z.boolean().optional() }).optional(),
  },
  returns: ['elements', 'geometry.worldModels', 'geometry.surfaces', 'geometry.terrain', 'geometry.areaType', 'roads'],
  related: ['get_area_summary', 'raycast', 'get_ground', 'inspect_road_area', 'capture_view'],
  limitations: ['World models are found by raycasts: small/thin models between grid points can be missed; hitExtent is not the full model bounds (use detail high for measured bounds).'],
  async handler(a, ctx) {
    const center = await ctx.bridgePoint(a.center);
    const inc = a.include || {};
    const r = await ctx.call('world', 'inspect', { center, radius: a.radius, detail: a.detail, include: inc }, { timeoutMs: 90000 });
    if (inc.roads !== false) {
      r.roads = roadContext(ctx.roads, r.center.x, r.center.y, r.center.z, r.radius, { detail: a.detail || 'medium' });
    }
    return r;
  },
});

defineTool({
  name: 'get_area_summary',
  module: 'world', kind: 'read', needsProbe: 'partial',
  title: 'Quick area summary',
  description: 'Cheap one-glance summary of an area: zone/city, area type, surface mix, height range, counts of elements, nearest road + intersections. Use before inspect_area when you only need orientation. Read-only.',
  input: { center: point.optional(), radius: z.number().min(5).max(300).optional() },
  returns: ['zone', 'areaType', 'surfaces', 'terrain', 'elementCounts', 'roads'],
  related: ['inspect_area', 'get_current_location_context'],
  async handler(a, ctx) {
    const center = await ctx.bridgePoint(a.center);
    const r = await ctx.call('world', 'inspect', { center, radius: a.radius || 60, detail: 'low' });
    const g = r.geometry || {};
    return {
      center: r.center, radius: r.radius, zone: r.zone, dimension: r.dimension,
      areaType: g.areaType, surfaces: g.surfaces, terrain: g.terrain, collisionLoaded: g.collisionLoaded,
      topWorldModels: (g.worldModels || []).slice(0, 8).map((m) => ({ id: m.id, name: m.name, kind: m.kind, distance: m.distance, direction: m.direction })),
      elementCounts: r.elements?.counts, workspaceEntities: r.workspaceEntities,
      roads: roadContext(ctx.roads, r.center.x, r.center.y, r.center.z, r.radius, { detail: 'low' }),
      hint: g.hint,
    };
  },
});

defineTool({
  name: 'get_world_map',
  module: 'world', kind: 'read', needsProbe: false,
  title: 'World map overview',
  description: 'Structured overview of San Andreas: world bounds, cities and zones (with approximate centres), road-network statistics, per-area (750 m) road density, the probe player location and all workspaces. No geometry scan (cheap). Use to orient yourself or to pick a location by zone name. Read-only.',
  input: { cellSize: z.number().min(100).max(1500).optional().describe('zone grid resolution, default 250 m'), includeCells: z.boolean().optional() },
  returns: ['bounds', 'cities', 'zones[] with approxCenter', 'roadNetwork stats', 'roadAreas', 'player', 'workspaces'],
  related: ['inspect_world_map_area', 'get_current_location_context', 'find_road_path'],
  async handler(a, ctx) {
    const zones = await ctx.call('world', 'zones', { cellSize: a.cellSize || 250, includeCells: a.includeCells });
    const areas = new Map();
    for (const n of ctx.roads.nodes.values()) {
      const k = n.area;
      const e = areas.get(k) || { area: k, nodes: 0, intersections: 0, sumX: 0, sumY: 0 };
      e.nodes++; e.sumX += n.x; e.sumY += n.y;
      if (n.adj.size >= 3) e.intersections++;
      areas.set(k, e);
    }
    const roadAreas = [...areas.values()].sort((p, q) => p.area - q.area).map((e) => ({
      area: e.area, bounds: { minX: -3000 + (e.area % 8) * 750, minY: -3000 + Math.floor(e.area / 8) * 750, size: 750 },
      nodes: e.nodes, intersections: e.intersections,
    }));
    let player = null, workspaces = null, status = null;
    try {
      status = await ctx.call('status', 'get', {});
      if (status.probe?.connected) player = { name: status.probe.player, position: status.probe.position, dimension: status.probe.dimension };
      workspaces = status.workspaces;
    } catch (e) { status = { error: e.code }; }
    return {
      bounds: { minX: -3000, minY: -3000, maxX: 3000, maxY: 3000, note: 'x = west->east, y = south->north, z = up' },
      cities: zones.cityCells, zones: zones.zones, zoneCells: zones.cells, cellSize: zones.cellSize,
      roadNetwork: ctx.roads.stats(), roadAreas,
      player, workspaces,
      conventions: { heading: 'MTA rotation.z: 0 = north (+Y), 90 = west, 180 = south, 270 = east (counter-clockwise)' },
    };
  },
});

defineTool({
  name: 'inspect_world_map_area',
  module: 'world', kind: 'read', needsProbe: false,
  title: 'Coarse map of a region',
  description: 'Coarse grid over a rectangular region (default 1 km around a centre): per cell the zone/city name, number of road nodes, intersections and average road height. Good for choosing where to work without scanning geometry. Read-only.',
  input: { center: point.optional(), size: z.number().min(100).max(6000).optional().describe('region edge in metres, default 1000'), cellSize: z.number().min(25).max(500).optional().describe('default 100') },
  returns: ['cells[] {x,y,zone,city,roadNodes,intersections,avgRoadZ}'],
  related: ['get_world_map', 'inspect_area'],
  async handler(a, ctx) {
    const c = await ctx.locate(a.center);
    const size = a.size || 1000, cell = a.cellSize || 100;
    const bounds = { minX: c.x - size / 2, minY: c.y - size / 2, maxX: c.x + size / 2, maxY: c.y + size / 2 };
    const zones = await ctx.call('world', 'zones', { bounds, cellSize: cell, includeCells: true });
    const cells = (zones.cells || []).map((z0) => {
      const nodes = ctx.roads.nodesWithin(z0.x, z0.y, cell / Math.SQRT2).filter((n) => Math.abs(n.x - z0.x) <= cell / 2 && Math.abs(n.y - z0.y) <= cell / 2);
      const avg = nodes.length ? round(nodes.reduce((s, n) => s + n.z, 0) / nodes.length, 1) : null;
      return { x: round(z0.x, 1), y: round(z0.y, 1), zone: z0.zone, city: z0.city, roadNodes: nodes.length, intersections: nodes.filter((n) => n.adj.size >= 3).length, avgRoadZ: avg };
    });
    return { center: { x: round(c.x), y: round(c.y) }, bounds, cellSize: cell, zones: zones.zones, cells };
  },
});

defineTool({
  name: 'raycast',
  module: 'world', kind: 'read', needsProbe: true,
  title: 'Raycast / line of sight',
  description: 'Casts rays against the live collision world. Modes: segment (from -> to), down (vertical ray at a position: what is below / at this spot), direction (from a point along heading+pitch or a direction vector, e.g. "what is 20 m in front of this vehicle"), camera (what the probe camera looks at), batch (up to 500 {from,to}). Each hit returns position, surface normal, slope, distance, surface material/class, hit element (entity id) or world model (id, dff name, kind, position, rotation, LOD). Read-only.',
  input: {
    mode: z.enum(['segment', 'down', 'direction', 'camera', 'batch']).optional(),
    from: point.optional(), to: point.optional(), position: point.optional(),
    heading: z.number().optional(), pitch: z.number().optional(), direction: z.object({ x: z.number(), y: z.number(), z: z.number().optional() }).optional(),
    length: z.number().optional(), lift: z.number().optional().describe('metres added to start/end z (e.g. 1 for eye height)'),
    batch: z.array(z.object({ from: z.any(), to: z.any() })).optional(),
    options: z.object({ buildings: z.boolean().optional(), vehicles: z.boolean().optional(), peds: z.boolean().optional(), objects: z.boolean().optional(), seeThrough: z.boolean().optional(), ignoreProbe: z.boolean().optional() }).optional(),
  },
  returns: ['results[] {hit, position, normal, slope, distance, materialName, surfaceClass, element, worldModel}'],
  related: ['get_ground', 'check_line_of_sight', 'inspect_area'],
  limitations: ['Collision exists only near the probe camera (~300 m); far rays may hit nothing.'],
  async handler(a, ctx) {
    const p = { ...a };
    for (const k of ['from', 'to', 'position']) if (p[k]) p[k] = await ctx.bridgePoint(p[k], k);
    return ctx.call('world', 'raycast', p);
  },
});

defineTool({
  name: 'get_ground',
  module: 'world', kind: 'read', needsProbe: true,
  title: 'Ground height / surface',
  description: 'Ground under one or more points (up to 400): ground z, surface material + class (road, sidewalk, grass...), normal, slope, area slope + downhill heading, water level/depth, height of the given z above ground, hit world model / element. Use for height, slope and "is this walkable/dry" questions. topmost = true takes the highest surface (roofs). Read-only.',
  input: {
    position: point.optional(), points: z.array(point).max(400).optional(),
    includeObjects: z.boolean().optional(), includeVehicles: z.boolean().optional(),
    slopeRadius: z.number().optional(), topmost: z.boolean().optional(),
  },
  returns: ['points[] {groundZ, materialName, surfaceClass, slope, areaSlope, waterLevel, underwater, heightAboveGround, worldModel}'],
  related: ['raycast', 'find_safe_position', 'place_entity'],
  async handler(a, ctx) {
    const p = { ...a };
    if (p.position) p.position = await ctx.bridgePoint(p.position);
    if (p.points) p.points = await Promise.all(p.points.map((x) => ctx.bridgePoint(x)));
    return ctx.call('world', 'ground', p);
  },
});

defineTool({
  name: 'find_safe_position',
  module: 'world', kind: 'read', needsProbe: true,
  title: 'Find a free spot',
  description: 'Searches outward from a point for the nearest spot where a ped / vehicle / object of a given model fits: solid ground, not under water, slope limit, optional surface filter (e.g. ["sidewalk","grass"]), avoid or prefer road, footprint free of world geometry and elements (+clearance). Returns spots with ground info and a usable heading. Read-only; use the result with spawn_entity / place_entity.',
  input: {
    near: point.optional(), for: z.enum(['ped', 'vehicle', 'object']).optional(), model: z.number().int().optional(),
    radius: z.number().optional(), heading: z.number().optional(), clearance: z.number().optional(),
    surfaces: z.array(z.string()).optional(), avoidRoad: z.boolean().optional(), preferRoad: z.boolean().optional(),
    maxSlope: z.number().optional(), count: z.number().int().min(1).max(10).optional(), ignore: z.array(z.string()).optional(),
  },
  returns: ['spots[] {position, heading, distance, ground}', 'rejected reasons'],
  related: ['place_entity', 'spawn_entity', 'get_ground'],
  async handler(a, ctx) {
    const p = { ...a, near: await ctx.bridgePoint(a.near) };
    return ctx.call('world', 'safeSpot', p);
  },
});

defineTool({
  name: 'check_line_of_sight',
  module: 'world', kind: 'read', needsProbe: true,
  title: 'Line of sight between two points',
  description: 'Is the straight line between two points/entities clear (buildings, objects, vehicles)? Entities used as endpoints are ignored. lift raises both ends (default 1 m). Returns clear, distance and the blocker. Read-only.',
  input: { from: point, to: point, lift: z.number().optional(), options: z.object({ vehicles: z.boolean().optional(), peds: z.boolean().optional(), objects: z.boolean().optional() }).optional() },
  returns: ['clear', 'distance', 'blockedAt', 'blocker'],
  related: ['raycast', 'medical_validate_scene'],
  async handler(a, ctx) {
    return ctx.call('world', 'lineOfSight', { ...a, from: await ctx.bridgePoint(a.from), to: await ctx.bridgePoint(a.to) });
  },
});

defineTool({
  name: 'list_world_elements',
  module: 'world', kind: 'read', needsProbe: false,
  title: 'List MTA elements near a point',
  description: 'MTA elements (default vehicles, peds, players, objects; also marker, pickup, colshape) within a radius, nearest first, with ids (workspace ids or el_* refs usable by other tools), model, names, position, heading, distance and direction. Filters by the probe dimension unless anyDimension. Read-only.',
  input: { center: point.optional(), radius: z.number().optional(), types: z.array(z.string()).optional(), detail: detail.optional(), limit: z.number().int().optional(), anyDimension: z.boolean().optional(), dimension: z.number().int().optional() },
  returns: ['elements[]', 'counts'],
  related: ['inspect_entity', 'adopt_element'],
  async handler(a, ctx) {
    return ctx.call('world', 'elements', { ...a, center: await ctx.bridgePoint(a.center) });
  },
});

defineTool({
  name: 'environment',
  module: 'world', kind: 'mutate', needsProbe: false,
  title: 'Time / weather',
  description: 'Reads time, weather, gravity, game speed. With set = {hour, minute, weather} it changes them SERVER-WIDE (mutating, affects all players; realtime resources may override). For screenshots prefer capture_view daylight=true (probe client only).',
  input: { set: z.object({ hour: z.number().int().min(0).max(23).optional(), minute: z.number().int().min(0).max(59).optional(), weather: z.number().int().optional(), minuteDuration: z.number().int().optional() }).optional() },
  returns: ['time', 'weather', 'gravity', 'gameSpeed'],
  sideEffects: 'set changes server time/weather for everyone',
  related: ['capture_view'],
  async handler(a, ctx) { return ctx.call('world', 'environment', a); },
});
