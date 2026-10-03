import { z } from 'zod';
import { defineTool } from './registry.js';
import { point, placement, properties, entityType, xyz, detail } from './schemas.js';
import { translatePlacement, roadHeadingAt } from '../roads/placement.js';
import { ToolError } from '../errors.js';
import { round, compass } from '../geo.js';

defineTool({
  name: 'spawn_entity',
  module: 'entities', kind: 'mutate', needsProbe: 'partial',
  title: 'Spawn a vehicle / ped / object',
  description: 'Creates a vehicle, ped or object in a workspace (default workspace "default", created on demand) and returns its semantic id (e.g. tmp_vehicle_001) with the real transform read back, ground contact and placement details. Prefer `placement` (semantic: ground, road lane, near another entity, relative offset, node frame) over raw position/rotation: the bridge computes z from live collision, model base offset and terrain pitch/roll. position without z snaps to ground. Entities are frozen by default (workspace setting) and vehicles damage-proof. Never assume spawning means correct: inspect/validate afterwards.',
  input: {
    type: entityType, model: z.number().int(),
    workspace: z.string().optional(), id: z.string().optional().describe('custom semantic id'),
    placement: placement.optional(),
    position: point.optional().describe('raw position (z optional -> ground)'), rotation: xyz.optional(), heading: z.number().optional(),
    frozen: z.boolean().optional(), properties: properties.optional(), meta: z.record(z.any()).optional().describe('free metadata stored with the entity (role, tags...)'),
    plate: z.string().optional(), variant: z.array(z.number()).optional(), verify: z.boolean().optional(),
  },
  returns: ['entity {id, type, model, modelName, position, rotation, heading, compass, live {groundContact, bbox, wheels...}}', 'placement details', 'warnings'],
  sideEffects: 'Creates an MTA element (visible to players in that dimension).',
  prerequisites: ['Model id from search_models / get_*_models / get_model_info'],
  related: ['place_entity', 'inspect_entity', 'validate_workspace', 'delete_entity'],
  async handler(a, ctx) {
    const p = { ...a };
    if (p.placement) p.placement = await translatePlacement(p.placement, ctx);
    if (p.position) p.position = await ctx.bridgePoint(p.position);
    return ctx.call('entities', 'spawn', p);
  },
});

defineTool({
  name: 'delete_entity',
  module: 'entities', kind: 'mutate', needsProbe: false,
  title: 'Delete entities',
  description: 'Destroys workspace entities by id (one id or a list). Adopted elements are only released unless destroyAdopted. Returns deleted / notFound ids.',
  input: { id: z.string().optional(), ids: z.array(z.string()).optional(), destroyAdopted: z.boolean().optional() },
  returns: ['deleted[]', 'notFound[]'],
  sideEffects: 'Destroys MTA elements.',
  related: ['clear_workspace'],
  async handler(a, ctx) { return ctx.call('entities', 'delete', a); },
});

defineTool({
  name: 'set_entity_transform',
  module: 'entities', kind: 'mutate', needsProbe: 'partial',
  title: 'Move / rotate (raw or relative)',
  description: 'Low-level transform: absolute position / rotation / heading, and/or relative move (world {x,y,z} or local {forward,right,up} in the entity frame) and rotate {x,y,z} degrees. snapToGround re-computes z (and vehicle pitch/roll) from live collision after the move. Covers move_entity and rotate_entity. Returns before/after and live ground info.',
  input: {
    id: z.string(), position: point.optional(), rotation: xyz.optional(), heading: z.number().optional(),
    move: z.object({ x: z.number().optional(), y: z.number().optional(), z: z.number().optional(), forward: z.number().optional(), right: z.number().optional(), up: z.number().optional() }).optional(),
    rotate: xyz.partial().optional(), snapToGround: z.boolean().optional(), align: z.enum(['terrain', 'upright']).optional(), verify: z.boolean().optional(),
  },
  returns: ['before', 'entity (after)', 'placement'],
  sideEffects: 'Moves an element.',
  related: ['place_entity', 'orient_entity'],
  async handler(a, ctx) {
    const p = { ...a };
    if (p.position) p.position = await ctx.bridgePoint(p.position);
    return ctx.call('entities', 'transform', p);
  },
});

defineTool({
  name: 'modify_entity',
  module: 'entities', kind: 'mutate', needsProbe: false,
  title: 'Change entity properties',
  description: 'Changes properties of an entity: vehicle damage preset / colours / plate / engine / lights / sirens / locks / doors open, ped skin / pose (animation) / seat in a vehicle / exit, object scale, common frozen / alpha / collisions / health / model, plus free meta. Returns applied keys, warnings and the full new state.',
  input: { id: z.string(), properties },
  returns: ['applied[]', 'warnings[]', 'entity (high detail)'],
  sideEffects: 'Changes element state.',
  related: ['inspect_entity'],
  async handler(a, ctx) { return ctx.call('entities', 'modify', a); },
});

defineTool({
  name: 'inspect_entity',
  module: 'entities', kind: 'read', needsProbe: 'partial',
  title: 'Inspect one entity',
  description: 'Full state of a workspace entity or any element ref (el_*, player name): model + name, transform, heading + compass + forward vector, frozen/alpha/health, vehicle damage/colours/occupants, ped pose/seat, live geometry from the probe (bounding box, world bounds, ground z + gap, wheel ground contact, underwater, on screen), nearby elements with relative side/distance, relation to the probe player, and its road context (nearest road, alignment). detail low|medium|high. Read-only. Also serves as get_entity.',
  input: { id: z.string(), detail: detail.optional(), nearbyRadius: z.number().optional() },
  returns: ['entity', 'live', 'nearby[] with relation', 'road'],
  related: ['validate_workspace', 'get_spatial_relation', 'capture_view'],
  async handler(a, ctx) {
    const r = await ctx.call('entities', 'inspect', a);
    if (r.position) {
      const road = roadHeadingAt(ctx.roads, r.position.x, r.position.y, r.position.z, r.heading);
      if (road) {
        r.road = {
          nearestSegment: road.segment, distanceToRoadLine: round(road.distance, 2), lateralOffset: round(road.lateral, 2),
          roadHeadingClosestToEntity: round(road.heading, 1), headingDifference: round(((r.heading - road.heading + 540) % 360) - 180, 1),
        };
      }
    }
    return r;
  },
});

defineTool({
  name: 'get_spatial_relation',
  module: 'entities', kind: 'read', needsProbe: 'partial',
  title: 'Relation between two things',
  description: 'Where B is relative to A (A\'s heading frame): distance 2D/3D, height difference, local right/forward offsets, side (front, back-left...), compass bearing, heading difference + orientation (parallel / opposite / perpendicular), and for two entities box overlap + ground-plane clearance between their bounding boxes. Read-only.',
  input: { from: point, to: point, heading: z.number().optional().describe('heading of A when A is a point') },
  returns: ['distance', 'side', 'localRight/localForward', 'headingDifference', 'orientation', 'overlapping', 'clearance2D'],
  related: ['inspect_entity', 'place_entity (mode near)'],
  async handler(a, ctx) {
    return ctx.call('entities', 'relation', { ...a, from: await ctx.bridgePoint(a.from), to: await ctx.bridgePoint(a.to) });
  },
});

defineTool({
  name: 'adopt_element',
  module: 'entities', kind: 'mutate', needsProbe: false,
  title: 'Adopt an existing element',
  description: 'Gives an existing element (el_* ref from list_world_elements / inspect_area) a semantic id in a workspace so all entity / placement / validation / export tools work on it. Adopted elements are not destroyed by delete/clear unless asked.',
  input: { ref: z.string(), workspace: z.string().optional(), id: z.string().optional() },
  returns: ['entity'],
  related: ['list_world_elements'],
  async handler(a, ctx) { return ctx.call('entities', 'adopt', a); },
});

defineTool({
  name: 'place_entity',
  module: 'placement', kind: 'mutate', needsProbe: 'partial',
  title: 'Semantic placement',
  description: 'Moves an existing entity with a semantic placement; the bridge computes the real transform. Modes: ground (snap to terrain at a point, vehicle pitch/roll follows terrain), road (node / segment / nearest road to a point; lane counted from the right curb, lanePosition lane|curb|shoulder|center|sidewalk, facing forward|backward, along/lateral offsets; lane widths measured from live geometry), node (offset in a road node\'s travel frame), near (next to a target on a side with a clearance gap computed from both bounding boxes; facing same|opposite|perpendicular|towards|away), relative (local offset {right,forward,up} from a target), raw. Covers place_on_ground, place_on_road, place_on_lane, place_near_entity, offset_from_entity, place_relative_to_node.',
  input: { id: z.string(), placement, verify: z.boolean().optional() },
  returns: ['entity (after, with live ground contact)', 'placement details (cross-section, lane, ground)', 'warnings'],
  sideEffects: 'Moves an element.',
  related: ['spawn_entity', 'orient_entity', 'validate_workspace', 'compute_placement'],
  async handler(a, ctx) {
    return ctx.call('placement', 'place', { id: a.id, placement: await translatePlacement(a.placement, ctx), verify: a.verify });
  },
});

defineTool({
  name: 'compute_placement',
  module: 'placement', kind: 'read', needsProbe: 'partial',
  title: 'Dry-run a placement',
  description: 'Computes the transform a placement would produce for a model without creating or moving anything (same modes as place_entity). Use to preview positions or feed raw coordinates elsewhere. Read-only.',
  input: { type: entityType, model: z.number().int(), placement },
  returns: ['position', 'rotation', 'heading', 'details', 'warnings'],
  related: ['place_entity', 'spawn_entity'],
  async handler(a, ctx) {
    return ctx.call('placement', 'compute', { ...a, placement: await translatePlacement(a.placement, ctx) });
  },
});

defineTool({
  name: 'orient_entity',
  module: 'placement', kind: 'mutate', needsProbe: 'partial',
  title: 'Semantic rotation',
  description: 'Rotates an entity semantically: face_towards / face_away (target), parallel_to / opposite_to / perpendicular_to (another entity\'s heading; side left|right), align_to_road (nearest road, keeping the closest direction unless direction forward|backward), heading (absolute MTA heading), relative (offset degrees). offset adds degrees (e.g. a 25° crash skew). Vehicles keep terrain alignment. Covers face_towards, face_forward, face_backward, align_to_road.',
  input: {
    id: z.string(),
    mode: z.enum(['face_towards', 'face_away', 'parallel_to', 'opposite_to', 'perpendicular_to', 'align_to_road', 'heading', 'relative']),
    target: point.optional(), heading: z.number().optional(), offset: z.number().optional(),
    side: z.enum(['left', 'right']).optional(), direction: z.enum(['forward', 'backward', 'closest']).optional(), verify: z.boolean().optional(),
  },
  returns: ['previousHeading', 'heading', 'compass', 'entity'],
  sideEffects: 'Rotates an element.',
  related: ['place_entity', 'get_spatial_relation'],
  async handler(a, ctx) {
    const p = { ...a };
    if (a.mode === 'align_to_road') {
      const e = await ctx.call('entities', 'get', { id: a.id, detail: 'low' });
      const road = roadHeadingAt(ctx.roads, e.position.x, e.position.y, e.position.z, e.heading, a.direction);
      if (!road) throw new ToolError('NO_ROAD_NEARBY', 'No road segment within 120 m of the entity.');
      p.mode = 'align_heading';
      p.heading = road.heading;
      const r = await ctx.call('placement', 'orient', p);
      r.road = { segment: road.segment, roadHeading: round(road.heading, 1), compass: compass(road.heading), distanceToRoadLine: round(road.distance, 2) };
      return r;
    }
    if (p.target) p.target = await ctx.bridgePoint(p.target);
    return ctx.call('placement', 'orient', p);
  },
});
