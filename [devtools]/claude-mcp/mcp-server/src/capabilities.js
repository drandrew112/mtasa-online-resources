// Capability map: machine-readable description of every module, tool, workflow,
// entity type, inspection / validation method and data source. Built from the
// tool definitions (single source of truth) plus live bridge status.

import { TOOLS } from './tools/registry.js';
import { zodToJsonSchema } from 'zod-to-json-schema';
import { z } from 'zod';

export const MODULES = {
  system: 'Status, health, this capability map.',
  world: 'Location context, area inspection, world map, raycasts, ground, free spots, line of sight, elements, environment.',
  roads: 'Vehicle-node road graph (30k nodes) + live road cross-sections: nearest node/segment, links, stretches, paths, road areas.',
  models: 'Model discovery: vehicles (veh_manager names), peds (male/female), objects (dff names), measured dimensions.',
  entities: 'Entity lifecycle with semantic ids: spawn, inspect, modify, transform, delete, adopt, spatial relations.',
  placement: 'Semantic placement / rotation computed by the bridge from live collision (ground, road lane, near, relative, node frame).',
  workspace: 'Temporary entity groups: create, inspect, clear, export (generic / .map / Lua), import.',
  validation: 'Structured diagnostics: ground contact, world collision, overlaps, water, clearance, road alignment...',
  visual: 'Real screenshots (current view or computed camera views) and an in-game debug overlay.',
  player: 'Probe player state, teleport, camera.',
  dev: 'Debug log, Lua execution, export calls, resource control, element data.',
  cache: 'Persistent data cache (survives restarts): list / get / put / delete, cached surface maps of whole cities and surface-patch search (parks, plazas, beaches). Check cache_list before generating expensive data.',
  medical: 'Medical scenes on top of the generic modules: patients, injuries, medsys states, templates, EMS-access validation, med_scenemanager export.',
};

export const WORKFLOWS = [
  {
    name: 'find_parks_or_areas_by_surface',
    goal: 'Find grass parks / plazas / beaches across a city without rescanning',
    steps: ['cache_list {kind:"surface_map"}', 'build_surface_map {city} (repeat while complete = false; skipped when cached)', 'find_surface_patches {city, surfaces:["grass"], maxRoadDistance}', 'get_area_summary / capture_view on the spot', 'cache_put verified spots for reuse'],
  },
  {
    name: 'orient_yourself',
    goal: 'Understand where you are and what is around',
    steps: ['get_status', 'get_current_location_context', 'get_area_summary | inspect_area', 'capture_screenshot'],
  },
  {
    name: 'place_vehicle_on_road',
    goal: 'Put a vehicle correctly into a lane',
    steps: ['inspect_area / get_current_location_context', 'get_nearest_road_node', 'get_road_cross_section (optional: width, lanes)', 'spawn_entity {placement: {mode:"road", node, towardNode, lane, facing}}', 'inspect_entity', 'validate_workspace', 'capture_view'],
  },
  {
    name: 'model_to_validated_entity',
    goal: 'Spawn an unknown model correctly',
    steps: ['search_models', 'get_model_info (dimensions)', 'spawn_entity (placement ground/near)', 'inspect_entity', 'modify_entity / place_entity / orient_entity', 'validate_workspace'],
  },
  {
    name: 'iterative_scene',
    goal: 'Build, check and export a multi-entity scene',
    steps: ['create_workspace', 'spawn_entity xN (semantic placements)', 'inspect_workspace', 'capture_view {workspace, overlay:true}', 'validate_workspace', 'fix: place_entity / orient_entity / set_entity_transform', 'validate_workspace (until valid)', 'export_workspace'],
  },
  {
    name: 'medical_scene',
    goal: 'Create a med_scenemanager scene from the live world',
    steps: ['medical_get_catalog', 'medical_build_from_template OR medical_create_scene + medical_add_vehicle + medical_add_patient', 'medical_validate_scene', 'capture_view {workspace: scene, overlay: true}', 'fix + re-validate', 'medical_simulate_patient (optional)', 'medical_export_scene {save:true}', 'medical_live_scene {action:"spawn"} (optional live test)'],
  },
  {
    name: 'work_far_away',
    goal: 'Inspect / build somewhere the probe is not',
    steps: ['get_world_map (zone centres)', 'teleport_probe', 'get_current_location_context', '...'],
  },
  {
    name: 'route_and_road_debug',
    goal: 'Understand a route or junction',
    steps: ['find_road_path', 'set_debug_overlay {pathNodes | roadArea}', 'capture_view {view:"top"}', 'inspect_road_area {live:true}'],
  },
  {
    name: 'test_resource_behaviour',
    goal: 'Test what a resource does to the world',
    steps: ['manage_resources {action:"info"}', 'get_debug_log (note lastSeq)', 'call_export / execute_lua / spawn_entity', 'get_debug_log {since}', 'inspect_area / capture_screenshot'],
  },
];

const CONVENTIONS = {
  coordinates: 'GTA:SA world metres; x = west->east, y = south->north, z = up; map is -3000..3000 on x and y.',
  heading: 'MTA rotation.z in degrees, counter-clockwise: 0 = north (+Y), 90 = west, 180 = south, 270 = east. Every entity reports heading + compass + forward vector.',
  vehicleRotation: 'rotation.x = pitch (+ nose up), rotation.y = roll (+ right side down); placement computes them from the terrain.',
  pedRotation: 'Only heading matters; the bridge sets ped rotation with MTA\'s ped fix.',
  objectRotation: 'heading rotates the model +Y axis; which side is an object\'s "front" depends on the model (check with the overlay arrow / a screenshot).',
  modelSize: 'size.x = width (left-right), size.y = length (back-front, +y = front), size.z = height.',
  lanes: 'lane 1 = curb (rightmost) lane of the travel direction; right-hand traffic; lane counts are estimated from measured width.',
  offsets: 'lateral offsets: + = right of the reference heading.',
  ids: 'Bridge-created entities: <prefix>_<type>_<nnn> (e.g. tmp_vehicle_001). Other elements: el_<type>_<n> refs (valid until destroyed / bridge restart).',
  locations: 'Any location parameter accepts "player", an entity id, {x,y,z}, [x,y,z] or {node: roadNodeId}.',
};

function inputSchema(def) {
  try {
    const s = zodToJsonSchema(z.object(def.input || {}), { target: 'jsonSchema7', $refStrategy: 'none' });
    delete s.$schema;
    return s;
  } catch {
    return undefined;
  }
}

function relationships() {
  // directed "next step" edges from the workflows
  const edges = new Map();
  for (const w of WORKFLOWS) {
    for (let i = 1; i < w.steps.length; i++) {
      const from = w.steps[i - 1].split(/[ |(]/)[0], to = w.steps[i].split(/[ |(]/)[0];
      const k = `${from}->${to}`;
      if (!edges.has(k)) edges.set(k, { from, to, workflows: [] });
      edges.get(k).workflows.push(w.name);
    }
  }
  return [...edges.values()];
}

export async function buildCapabilityMap(ctx, { module, tool, schemas = false } = {}) {
  let live = null;
  try {
    const s = await ctx.call('status', 'get', {});
    live = {
      connected: true, bridgeInstance: s.bridge.instanceId, probe: s.probe, workspaces: s.workspaces,
      entityCount: s.entityCount, integrations: s.integrations, settings: s.settings,
    };
  } catch (e) {
    live = { connected: false, error: { code: e.code, message: e.message, suggestion: e.extra?.suggestion } };
  }
  const tools = TOOLS.filter((t) => (!module || t.module === module) && (!tool || t.name === tool)).map((t) => ({
    name: t.name, module: t.module, type: t.kind === 'read' ? 'read' : 'mutating', title: t.title,
    description: t.description,
    parameters: Object.keys(t.input || {}),
    inputSchema: schemas || tool ? inputSchema(t) : undefined,
    returns: t.returns, sideEffects: t.sideEffects || (t.kind === 'read' ? 'none' : undefined),
    needsProbeClient: t.needsProbe, prerequisites: t.prerequisites, limitations: t.limitations, related: t.related,
  }));
  if (tool) return { tool: tools[0] || null, conventions: CONVENTIONS };
  const probeTools = TOOLS.filter((t) => t.needsProbe === true).map((t) => t.name);
  return {
    system: { name: 'MTA World MCP', version: ctx.config.version, connected: live.connected, live },
    modules: Object.entries(MODULES).map(([name, description]) => ({ name, description, tools: TOOLS.filter((t) => t.module === name).map((t) => t.name) })),
    conventions: CONVENTIONS,
    entityTypes: {
      vehicle: 'models 400-611; damage, colours, plate, engine, lights, sirens, doors, occupants',
      ped: 'valid skins (male / female); poses (animations), seat in vehicle, medical data',
      object: 'any object model id (search by dff name); scale, double-sided',
    },
    poses: ['none', 'lie_back', 'lie_front', 'injured', 'sit_ground', 'crouch', 'hold_side', 'lean', 'hands_up', 'phone', 'idle_chat', 'wave', 'look', 'cpr', 'sit_chair'],
    inspectionMethods: ['get_current_location_context', 'get_area_summary', 'inspect_area', 'inspect_entity', 'inspect_workspace', 'inspect_road_area', 'get_road_cross_section', 'raycast', 'get_ground', 'check_line_of_sight', 'get_spatial_relation', 'list_world_elements', 'capture_screenshot', 'capture_view'],
    validationMethods: {
      tools: ['validate_workspace', 'medical_validate_scene'],
      checks: ['validity', 'dimension', 'bounds', 'ground', 'world_collision', 'overlap', 'water', 'clearance', 'scene_bounds', 'health', 'road_alignment'],
      medicalChecks: ['no_patients', 'no_injuries', 'erm_title', 'erm_description', 'far_from_center', 'stretcher_space', 'patient_on_road', 'no_ambulance_access', 'no_direct_path'],
    },
    worldData: {
      live: 'MTA elements, collision raycasts (world models with ids/dff names/positions/rotations, surfaces, normals), ground, water, zones, camera, screenshots, measured model bounds',
      roadGraph: ctx.roads.stats(),
      models: 'vehicles via veh_manager:getModelName; peds via getValidPedModels + project female list; objects via engineGetModelNameFromID',
      notAvailable: ['lane counts / widths in the node data (measured live instead)', 'traffic-light state', 'building interiors layout', 'collision far from the probe camera'],
    },
    visualFeedback: {
      tools: ['capture_screenshot', 'capture_view', 'set_debug_overlay', 'medical_build_from_template {capture:true}'],
      requirements: 'probe client connected, "Allow screen upload" enabled, game window not minimized',
    },
    feedbackAfterActions: 'Mutations return the entity state read back from MTA (+ live ground contact / bounds when a probe is connected), applied keys and warnings. Errors are { code, message, retryable, suggestion }.',
    tools,
    workflows: WORKFLOWS,
    relationships: relationships(),
    discovery: [
      '1. get_status (connection, probe, workspaces)',
      '2. get_capability_map (this) — module / tool filters, schemas:true for full input schemas',
      '3. get_current_location_context (where am I)',
      '4. get_world_map (zones, road network)',
      '5. search_models / get_model_info (what can I create)',
    ],
  };
}
