// Translates road-aware placement specs (which need the road graph) into the
// bridge's placement modes. Other modes pass through unchanged.

import { ToolError } from '../errors.js';
import { angleDiff, headingTo, norm, round, compass } from '../geo.js';

/**
 * Road spec: { mode: "road", node | segment {from,to} | position, towardNode, heading (hint),
 *              t (0..1 on a segment), lane, lanePosition, lateralOffset, alongOffset, facing }
 * Node-relative: { mode: "node", node, towardNode, along, lateral, up, facing, relativeHeading }
 */
export async function translatePlacement(spec, ctx) {
  if (!spec || typeof spec !== 'object') return spec;
  const roads = ctx.roads;
  const out = { ...spec };

  for (const k of ['position', 'target']) {
    if (out[k] && typeof out[k] === 'object' && out[k].node !== undefined) out[k] = await ctx.bridgePoint(out[k], k);
  }

  if (spec.mode === 'road') {
    let base, travel, road;
    if (spec.segment) {
      const a = roads.get(spec.segment.from), b = roads.get(spec.segment.to);
      if (!a || !b) throw new ToolError('ROAD_NODE_NOT_FOUND', 'segment.from / segment.to must be existing road node ids.');
      if (!a.adj.has(b.id)) throw new ToolError('NOT_A_SEGMENT', `Nodes ${a.id} and ${b.id} are not directly linked.`, { suggestion: 'Use get_road_segment or find_road_path.' });
      const t = Math.max(0, Math.min(1, spec.t ?? 0.5));
      base = { x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t, z: a.z + (b.z - a.z) * t };
      travel = headingTo(a.x, a.y, b.x, b.y);
      road = { segment: { from: a.id, to: b.id }, t, basis: 'segment from->to' };
    } else if (spec.node !== undefined) {
      const n = roads.get(spec.node);
      if (!n) throw new ToolError('ROAD_NODE_NOT_FOUND', `Road node ${spec.node} does not exist.`, { suggestion: 'get_nearest_road_node' });
      const dir = roads.directionAt(n, { towardNode: spec.towardNode, heading: spec.heading });
      if (!dir) throw new ToolError('ROAD_NODE_ISOLATED', `Road node ${n.id} has no links, so no direction can be derived.`);
      base = { x: n.x, y: n.y, z: n.z };
      travel = dir.heading;
      road = { node: n.id, towardNode: dir.toward, basis: dir.basis, nodeType: roads.nodeType(n) };
    } else {
      const p = await ctx.locate(spec.position ?? 'player', 'placement.position');
      const [s] = roads.nearestSegments(p.x, p.y, p.z, { count: 1, maxDistance: spec.maxDistance ?? 150 });
      if (!s) throw new ToolError('NO_ROAD_NEARBY', `No road segment within ${spec.maxDistance ?? 150} m of the position.`, { suggestion: 'Use get_world_map / get_nearest_road_node to find a road.' });
      base = { x: s.x, y: s.y, z: s.z };
      let from = s.a, to = s.b;
      const hint = spec.heading ?? (p.heading !== undefined && p.source !== 'point' ? p.heading : undefined);
      if (hint !== undefined && Math.abs(angleDiff(hint, s.heading)) > 90) [from, to] = [to, from];
      travel = headingTo(from.x, from.y, to.x, to.y);
      road = { segment: { from: from.id, to: to.id }, t: round(from === s.a ? s.t : 1 - s.t, 3), projectedFrom: { x: round(p.x), y: round(p.y) }, distanceToRoadLine: round(s.distance, 2),
        basis: hint !== undefined ? 'nearest segment, direction closest to the heading hint' : 'nearest segment, default direction' };
    }
    road.travelHeading = round(travel, 1);
    road.travelCompass = compass(travel);
    return {
      mode: 'road', base, heading: travel,
      lane: spec.lane, lanePosition: spec.lanePosition, lateralOffset: spec.lateralOffset, alongOffset: spec.alongOffset,
      facing: spec.facing ?? spec.direction ?? 'forward', align: spec.align, zOffset: spec.zOffset, scanWidth: spec.scanWidth,
      road,
    };
  }

  if (spec.mode === 'node') {
    const n = roads.get(spec.node);
    if (!n) throw new ToolError('ROAD_NODE_NOT_FOUND', `Road node ${spec.node} does not exist.`);
    const dir = roads.directionAt(n, { towardNode: spec.towardNode, heading: spec.heading });
    let rel = spec.relativeHeading ?? 0;
    if (spec.facing === 'backward') rel += 180;
    return {
      mode: 'relative', target: { x: n.x, y: n.y, z: n.z }, heading: dir ? dir.heading : 0,
      offset: { right: spec.lateral ?? 0, forward: spec.along ?? 0, up: spec.up ?? 0 },
      relativeHeading: rel, align: spec.align, zOffset: spec.zOffset, snapToGround: spec.snapToGround,
    };
  }

  return out;
}

/** Heading of the nearest road at a point, oriented as close as possible to a reference heading. */
export function roadHeadingAt(roads, x, y, z, refHeading, direction) {
  const [s] = roads.nearestSegments(x, y, z, { count: 1, maxDistance: 120 });
  if (!s) return null;
  let h = s.heading;
  if (direction === 'backward') h = norm(h + 180);
  else if (direction !== 'forward' && refHeading !== undefined && Math.abs(angleDiff(refHeading, h)) > 90) h = norm(h + 180);
  return { heading: h, segment: { from: s.a.id, to: s.b.id }, distance: s.distance, lateral: s.lateral };
}
