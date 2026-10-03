// Reusable zod schemas for tool inputs.
import { z } from 'zod';

export const xyz = z.object({ x: z.number(), y: z.number(), z: z.number().optional() });

export const point = z.union([
  z.string().describe('"player" (the probe player) or an entity id / element ref'),
  z.array(z.number()).min(2).max(3).describe('[x, y, z?]'),
  xyz,
  z.object({ node: z.number().int().describe('road node id') }),
  z.object({ entity: z.string() }),
]).describe('A location: "player", an entity id, {x,y,z}, [x,y,z] or {node: roadNodeId}');

export const detail = z.enum(['low', 'medium', 'high']);

export const entityType = z.enum(['vehicle', 'ped', 'object']);

export const placement = z.object({
  mode: z.enum(['ground', 'road', 'node', 'near', 'relative', 'raw']).describe(
    'ground: snap to terrain at position | road: on a road lane (node / segment / position) | node: offset from a road node in its travel frame | near: next to a target entity (side + gap) | relative: local offset from a target | raw: exact transform'),
  position: point.optional().describe('ground/road/raw: the point (road: projected onto the nearest road)'),
  heading: z.number().optional().describe('MTA heading in degrees (0 = north, 90 = west). road: direction hint'),
  node: z.number().int().optional().describe('road/node: road node id'),
  segment: z.object({ from: z.number().int(), to: z.number().int() }).optional().describe('road: segment; travel direction from -> to'),
  t: z.number().min(0).max(1).optional().describe('road+segment: position along the segment (0..1, default 0.5)'),
  towardNode: z.number().int().optional().describe('road/node: travel towards this neighbour node'),
  lane: z.number().int().min(1).optional().describe('road: lane counted from the right curb of the travel direction (1 = curb lane)'),
  lanePosition: z.enum(['lane', 'curb', 'shoulder', 'center', 'sidewalk', 'offset']).optional().describe('road: where across the road (default lane)'),
  lateralOffset: z.number().optional().describe('road: extra metres to the right (+) / left (-)'),
  alongOffset: z.number().optional().describe('road: metres forward (+) / back (-) along the travel direction'),
  facing: z.string().optional().describe('road: forward|backward; near/relative/ground: same|opposite|perpendicular|left|right|towards|away|<heading>'),
  target: point.optional().describe('near/relative: reference entity or point'),
  side: z.enum(['front', 'back', 'left', 'right', 'front-left', 'front-right', 'back-left', 'back-right']).optional().describe('near: side of the target'),
  gap: z.number().optional().describe('near: clearance between the two bounding boxes in metres (default 1)'),
  offset: z.object({ right: z.number().optional(), forward: z.number().optional(), up: z.number().optional() }).optional().describe('relative: local offset in the target frame'),
  along: z.number().optional().describe('node: metres along the travel direction; near: shift along target'),
  lateral: z.number().optional().describe('node: metres to the right of the node; near: shift sideways'),
  relativeHeading: z.number().optional().describe('relative/node: heading added to the reference heading'),
  headingOffset: z.number().optional().describe('degrees added to the final heading (e.g. a crash angle)'),
  align: z.enum(['terrain', 'upright']).optional().describe('vehicles: follow terrain pitch/roll (default) or stay level'),
  zOffset: z.number().optional().describe('metres added to the computed z'),
  snapToGround: z.boolean().optional().describe('default true'),
  rotation: xyz.optional().describe('raw: rotation {x,y,z}'),
}).describe('Semantic placement; the bridge computes the real transform from live collision.');

export const properties = z.record(z.any()).describe(
  'Element properties. common: frozen, alpha, collisions, health, model, meta{}, elementData{} | vehicle: damage (repair|light|heavy|wreck|{...}), color [r,g,b,r2,g2,b2], colors [12], plate, engine, lightsOn, sirens, locked, damageProof, paintjob, upgrades[], doors[6], panels[7], lights[4], wheels[4], doorsOpen{index: ratio} | ped: skin, pose (see get_capability_map poses), seat{vehicle, seat}, exitVehicle, armor, weapon | object: scale, doubleSided');
