import { z } from 'zod';
import fs from 'node:fs';
import { defineTool } from './registry.js';
import { point, detail } from './schemas.js';
import { roadHeadingAt } from '../roads/placement.js';
import { round } from '../geo.js';

defineTool({
  name: 'create_workspace',
  module: 'workspace', kind: 'mutate', needsProbe: false,
  title: 'Create a workspace',
  description: 'Creates a named workspace for temporary entities: dimension / interior (default: the probe player\'s), optional centre + radius (used by validation scene_bounds and capture_view), id prefix (entity ids become <prefix>_<type>_<nnn>), frozen default, description, meta. The "default" workspace exists implicitly.',
  input: {
    name: z.string(), center: point.optional(), radius: z.number().optional(), dimension: z.number().int().optional(), interior: z.number().int().optional(),
    prefix: z.string().optional(), frozen: z.boolean().optional(), description: z.string().optional(), kind: z.string().optional(), meta: z.record(z.any()).optional(),
  },
  returns: ['workspace summary'],
  related: ['spawn_entity', 'inspect_workspace', 'clear_workspace'],
  async handler(a, ctx) { return ctx.call('workspace', 'create', { ...a, center: await ctx.bridgePoint(a.center) }); },
});

defineTool({
  name: 'list_workspaces',
  module: 'workspace', kind: 'read', needsProbe: false,
  title: 'List workspaces',
  description: 'All workspaces with kind, dimension, centre, entity counts per type and missing entities. Use after a reconnect to recover state (the bridge holds it). Read-only.',
  input: {},
  returns: ['workspaces[]'],
  related: ['inspect_workspace'],
  async handler(a, ctx) { return ctx.call('workspace', 'list', {}); },
});

defineTool({
  name: 'inspect_workspace',
  module: 'workspace', kind: 'read', needsProbe: 'partial',
  title: 'Inspect a workspace',
  description: 'Workspace summary + every entity (state at detail level, live probe geometry: ground gap, wheel contact, bounds) + bounds/centre/zone of the group. Missing entities are listed with status "missing". Covers list_workspace_entities. Read-only.',
  input: { workspace: z.string().optional(), detail: detail.optional(), live: z.boolean().optional() },
  returns: ['workspace', 'entities[]', 'bounds', 'zone'],
  related: ['validate_workspace', 'capture_view', 'export_workspace'],
  async handler(a, ctx) { return ctx.call('workspace', 'inspect', a); },
});

defineTool({
  name: 'clear_workspace',
  module: 'workspace', kind: 'mutate', needsProbe: false,
  title: 'Clear a workspace',
  description: 'Destroys every entity of a workspace (keep = true keeps the empty workspace, default). all = true clears every workspace. The normal game world is untouched.',
  input: { workspace: z.string().optional(), keep: z.boolean().optional(), all: z.boolean().optional() },
  returns: ['removed[]', 'removedCount'],
  sideEffects: 'Destroys MTA elements.',
  related: ['delete_entity'],
  async handler(a, ctx) {
    if (a.all) return ctx.call('workspace', 'clearAll', {});
    return ctx.call('workspace', 'clear', a);
  },
});

defineTool({
  name: 'validate_workspace',
  module: 'validation', kind: 'read', needsProbe: 'partial',
  title: 'Validate entities',
  description: 'Structured diagnostics for a workspace (or a list of entity ids): validity (missing / blown / dead), dimension/interior, world bounds, health, ground contact (vehicle wheel gaps, ped/object base gap; lying peds tolerated), world-geometry intersection (with the model hit), non-workspace object intersection, entity overlaps (OBB; lying ped under a vehicle is an error), foreign element overlaps, water, cramped peds, scene radius, and road alignment for vehicles (heading vs. nearest road, distance from the road line). Returns {valid, errors[], warnings[], info[], entities[] with live metrics}; act on errors, re-validate after changes. Read-only.',
  input: {
    workspace: z.string().optional(), ids: z.array(z.string()).optional(),
    checks: z.array(z.enum(['validity', 'dimension', 'bounds', 'ground', 'world_collision', 'overlap', 'water', 'clearance', 'scene_bounds', 'health', 'road_alignment'])).optional(),
    tolerance: z.object({ groundGap: z.number().optional() }).optional(),
  },
  returns: ['valid', 'errors[] {entity, type, message, suggestion}', 'warnings[]', 'info[]', 'entities[] {position, heading, live}'],
  related: ['inspect_workspace', 'place_entity', 'capture_view'],
  async handler(a, ctx) {
    const checks = a.checks?.filter((c) => c !== 'road_alignment');
    const r = await ctx.call('validation', 'run', { workspace: a.workspace, ids: a.ids, checks: checks?.length ? checks : undefined, tolerance: a.tolerance }, { timeoutMs: 90000 });
    if (!a.checks || a.checks.includes('road_alignment')) {
      r.checks = [...(r.checks || []), 'road_alignment'];
      for (const e of r.entities || []) {
        if (e.type !== 'vehicle' || !e.position) continue;
        const road = roadHeadingAt(ctx.roads, e.position.x, e.position.y, e.position.z, e.heading);
        if (!road) continue;
        const diff = round(Math.abs(((e.heading - road.heading + 540) % 360) - 180), 1);
        e.road = { segment: road.segment, distanceToRoadLine: round(road.distance, 2), lateralOffset: round(road.lateral, 2), headingDifference: diff };
        const onRoad = e.placement?.mode === 'road';
        const entry = { entity: e.id, type: 'road_alignment' };
        if (onRoad && diff > 20) r.warnings.push({ ...entry, message: `Vehicle was placed on a road but is ${diff}° off the road direction.`, value: diff, suggestion: 'orient_entity mode align_to_road' });
        else if (onRoad && road.distance > 14) r.warnings.push({ ...entry, message: `Vehicle was placed on a road but is ${round(road.distance, 1)} m from the road line.`, value: road.distance });
        else r.info.push({ ...entry, message: `${round(road.distance, 1)} m from road line, ${diff}° from road direction.` });
      }
      r.warningCount = r.warnings.length;
    }
    return r;
  },
});

defineTool({
  name: 'export_workspace',
  module: 'workspace', kind: 'read', needsProbe: false,
  title: 'Export a workspace',
  description: 'Exports the verified state of a workspace, read back from the live MTA elements (never recomputed): format generic (re-importable JSON with transforms + properties + meta), map (MTA .map XML for the map editor) or lua (createVehicle/createPed/createObject code). save = file name writes it to claude-mcp/exports/. For med_scenemanager use medical_export_scene. Covers export_scene.',
  input: { workspace: z.string().optional(), format: z.enum(['generic', 'map', 'lua']).optional(), save: z.string().optional(), localFile: z.string().optional().describe('also write the export to this path on the MCP server machine') },
  returns: ['data (generic)', 'text (map / lua)', 'savedTo'],
  related: ['import_workspace', 'validate_workspace', 'medical_export_scene'],
  async handler(a, ctx) {
    const r = await ctx.call('scene', 'export', { workspace: a.workspace, format: a.format, save: a.save });
    if (a.localFile) {
      fs.writeFileSync(a.localFile, r.text ?? JSON.stringify(r.data, null, 2));
      r.localFile = a.localFile;
    }
    return r;
  },
});

defineTool({
  name: 'import_workspace',
  module: 'workspace', kind: 'mutate', needsProbe: false,
  title: 'Import a generic export',
  description: 'Spawns a generic export (from export_workspace, or a JSON file on the MCP server machine) into a workspace, optionally shifted by offset; vehicles first so peds can be re-seated. keepIds = false generates new ids.',
  input: { data: z.record(z.any()).optional(), file: z.string().optional(), workspace: z.string().optional(), offset: z.object({ x: z.number().optional(), y: z.number().optional(), z: z.number().optional() }).optional(), keepIds: z.boolean().optional(), dimension: z.number().int().optional() },
  returns: ['created[]', 'failed[]'],
  sideEffects: 'Creates MTA elements.',
  related: ['export_workspace'],
  async handler(a, ctx) {
    const data = a.data ?? (a.file ? JSON.parse(fs.readFileSync(a.file, 'utf8')) : undefined);
    return ctx.call('scene', 'import', { data, workspace: a.workspace, offset: a.offset, keepIds: a.keepIds, dimension: a.dimension });
  },
});
