// Medical scene module: built on the generic workspace / entity / placement /
// validation / visual tools. Scenes are workspaces of kind "medical"; export
// goes to the med_scenemanager JSON format.

import { z } from 'zod';
import { defineTool } from './registry.js';
import { point, placement } from './schemas.js';
import { translatePlacement } from '../roads/placement.js';
import { ToolError } from '../errors.js';
import { round, dist2, headingTo, angleDiff } from '../geo.js';
import { saveShot } from './visual.js';

const injury = z.object({ type: z.string().describe('see medical_get_catalog().injuries (gunshot, fracture, burn, suffocation)'), severity: z.number().int().min(1).max(3).describe('1 minor, 2 serious, 3 critical') });
const state = z.record(z.any()).describe('medsys preset keys: consciousness (stable|dazed|unconscious|clinical_death), bloodVolume, pain, bleeding (0-3), ivAccess, spo2, systolic, diastolic, heartRate, rhythm (SINUS, VF, PEA, ASYSTOLE ...)');
const erm = z.object({ title: z.string().optional(), description: z.string().optional(), caller: z.string().optional(), priority: z.number().int().min(1).max(4).optional() });

const ctx0 = (s) => s.ctx;
const CARS = [405, 410, 426, 445, 492, 516, 529, 540, 546, 547, 550, 551, 566];
const pick = (list) => list[Math.floor(Math.random() * list.length)];

// --------------------------------------------------------------- templates

const TEMPLATES = {
  t_bone_intersection: {
    description: 'Two cars collided at an intersection (side impact). Driver of car A thrown out next to it, driver of car B dazed in the seat.',
    erm: { title: 'Car accident at an intersection', description: 'Two cars collided at an intersection. One person is lying on the road, another is trapped in a car.', priority: 2 },
    async build(s) {
      const junction = s.intersection();
      const legs = [...junction.adj].map((id) => ctx0(s).roads.get(id));
      // A drives from legs[0] into the junction; B comes from the leg closest to perpendicular
      const a0 = legs[0];
      const aHeading = headingTo(a0.x, a0.y, junction.x, junction.y);
      let best = null;
      for (const l of legs.slice(1)) {
        const d = angleDiff(aHeading, headingTo(junction.x, junction.y, l.x, l.y));
        if (!best || Math.abs(Math.abs(d) - 90) < Math.abs(Math.abs(best.d) - 90)) best = { l, d };
      }
      const side = best && best.d > 0 ? 'left' : 'right';
      const a = await s.vehicle({ mode: 'road', node: a0.id, towardNode: junction.id, lane: 1, alongOffset: Math.max(0, s.legLength(a0.id, junction) - 3) }, { damage: 'heavy', role: 'crash' });
      await s.vehicle({ mode: 'near', target: a.id, side, gap: 0.15, facing: 'towards', headingOffset: -10 + Math.random() * 20 }, { damage: 'heavy', role: 'crash' });
      const other = side === 'left' ? 'right' : 'left';
      await s.patient({ mode: 'near', target: a.id, side: other, gap: 1.3, facing: 'perpendicular' }, { anim: 'ko_back', injuries: [{ type: 'fracture', severity: 2 }, { type: 'gunshot', severity: 1 }], state: { consciousness: 'unconscious', bleeding: 1 } });
      const b = s.created.filter((c) => c.type === 'vehicle')[1];
      await s.patient(null, { vehicle: b.id, seat: 0, anim: 'none', injuries: [{ type: 'fracture', severity: 1 }], state: { consciousness: 'dazed', pain: 30 } });
    },
  },
  rear_end: {
    description: 'Rear-end collision on a straight road; one occupant sitting at the curb with neck / back pain.',
    erm: { title: 'Rear-end collision', description: 'A car ran into the back of another car. One person is sitting at the side of the road, complaining of neck pain.', priority: 3 },
    async build(s) {
      const a = await s.vehicle({ mode: 'road', position: s.near, lane: 1 }, { damage: 'light', role: 'crash' });
      const b = await s.vehicle({ mode: 'near', target: a.id, side: 'back', gap: 0.1, facing: 'same', headingOffset: -6 + Math.random() * 12 }, { damage: 'heavy', role: 'crash' });
      await s.patient({ mode: 'road', position: a.id, lanePosition: 'sidewalk' }, { anim: 'sit', injuries: [{ type: 'fracture', severity: 1 }], state: { consciousness: 'stable', pain: 60 } });
      void b;
    },
  },
  pedestrian_struck: {
    description: 'A pedestrian was hit by a car; the patient lies on the road in front of the stopped car.',
    erm: { title: 'Pedestrian hit by a car', description: 'A car hit a pedestrian. The victim is lying on the road and not moving.', priority: 1 },
    async build(s) {
      const car = await s.vehicle({ mode: 'road', position: s.near, lane: 1 }, { damage: 'light', role: 'striking vehicle', lightsOn: true });
      await s.patient({ mode: 'near', target: car.id, side: 'front', gap: 2.5, facing: 'perpendicular' }, { anim: 'ko_front', injuries: [{ type: 'fracture', severity: 3 }, { type: 'gunshot', severity: 2 }], state: { consciousness: 'unconscious', bleeding: 2, bloodVolume: 3750 } });
    },
  },
  motorcycle_crash: {
    description: 'A motorcyclist came off the bike; bike on the road, rider lying several metres ahead.',
    erm: { title: 'Motorcycle accident', description: 'A motorcyclist fell off the bike at speed. The rider is lying on the road.', priority: 1 },
    async build(s) {
      const bike = await s.vehicle({ mode: 'road', position: s.near, lane: 1, headingOffset: 70 }, { model: pick([463, 468, 521, 586]), damage: 'heavy', role: 'crash' });
      await s.patient({ mode: 'near', target: bike.id, side: 'left', gap: 4, facing: 'perpendicular' }, { anim: 'ko_back', injuries: [{ type: 'fracture', severity: 3 }, { type: 'burn', severity: 1 }], state: { consciousness: 'dazed', bleeding: 1, pain: 60 } });
    },
  },
  cardiac_arrest_sidewalk: {
    description: 'A person collapsed on the sidewalk in cardiac arrest (VF); a bystander kneels next to them.',
    erm: { title: 'Person collapsed, not breathing', description: 'A person collapsed on the sidewalk and is not breathing. A bystander is starting CPR.', priority: 1 },
    async build(s) {
      const p = await s.patient({ mode: 'road', position: s.near, lanePosition: 'sidewalk' }, { anim: 'ko_back', injuries: [], state: { rhythm: 'VF' } });
      await s.bystander({ mode: 'near', target: p.id, side: 'right', gap: 0.2, facing: 'towards' }, { pose: 'cpr' });
    },
  },
};

// scene-building helper bound to one scene
function sceneBuilder(ctx, sceneName, near, opts) {
  const created = [];
  const warnings = [];
  const s = {
    ctx, near,
    created, warnings,
    intersection() {
      const [r] = ctx.roads.nearestNodes(near.x, near.y, near.z, { count: 1, maxDistance: opts.searchRadius || 250, filter: (n) => n.adj.size >= 3 });
      if (!r) throw new ToolError('NO_INTERSECTION', `No intersection within ${opts.searchRadius || 250} m of the location.`, { suggestion: 'Pick another location or template.' });
      return r.node;
    },
    legLength(legId, junction) {
      const n = ctx.roads.get(legId);
      return dist2(n.x, n.y, junction.x, junction.y);
    },
    async vehicle(pl, o = {}) {
      const r = await ctx.call('medical', 'addVehicle', {
        scene: sceneName, model: o.model || pick(CARS), placement: await translatePlacement(pl, ctx),
        damage: o.damage, role: o.role, lightsOn: o.lightsOn, sirens: o.sirens, engine: o.engine,
      });
      created.push({ id: r.vehicle.id, type: 'vehicle', model: r.vehicle.model, modelName: r.vehicle.modelName, role: o.role, position: r.vehicle.position, heading: r.vehicle.heading });
      for (const w of r.warnings || []) warnings.push({ entity: r.vehicle.id, ...w });
      return r.vehicle;
    },
    async patient(pl, o = {}) {
      const r = await ctx.call('medical', 'addPatient', {
        scene: sceneName, placement: pl ? await translatePlacement(pl, ctx) : undefined, position: pl ? undefined : near,
        sex: o.sex || (Math.random() < 0.5 ? 'male' : 'female'), anim: o.anim, injuries: o.injuries, state: o.state, vehicle: o.vehicle, seat: o.seat,
      });
      created.push({ id: r.patient.id, type: 'patient', skin: r.patient.model, sex: r.sex, position: r.patient.position, inVehicle: o.vehicle });
      for (const w of r.warnings || []) warnings.push({ entity: r.patient.id, ...w });
      return r.patient;
    },
    async bystander(pl, o = {}) {
      const skins = await ctx.call('models', 'peds', { withNames: false });
      const pool = [...(skins.male || []), ...(skins.female || [])].map((p) => p.model).filter((m) => m > 0);
      const r = await ctx.call('entities', 'spawn', {
        type: 'ped', model: pick(pool), workspace: sceneName, placement: await translatePlacement(pl, ctx),
        properties: { pose: o.pose }, meta: { role: 'bystander' },
      });
      created.push({ id: r.entity.id, type: 'bystander', position: r.entity.position });
      return r.entity;
    },
  };
  return s;
}

// --------------------------------------------------------------- tools

defineTool({
  name: 'medical_get_catalog',
  module: 'medical', kind: 'read', needsProbe: false,
  title: 'Medical catalog',
  description: 'Everything valid for medical scenes, from med_scenemanager: patient poses (anim ids such as ko_back, ko_front, injured, sit, crouch, hold_side, lean), injury types + severities, medsys state keys with ranges / presets / apply order, heart rhythms, vehicle damage presets, colour presets, preferred ped skins, default ERM data, plus the scene templates of this module and dependency status (medsys, med_erm). Read-only.',
  input: {},
  returns: ['anims[]', 'injuries[]', 'state{}', 'stateOrder[]', 'damage{}', 'templates{}', 'medsys / med_erm status'],
  related: ['medical_create_scene', 'medical_build_from_template'],
  async handler(a, ctx) {
    const c = await ctx.call('medical', 'catalog', {});
    c.templates = Object.fromEntries(Object.entries(TEMPLATES).map(([k, t]) => [k, { description: t.description, erm: t.erm }]));
    return c;
  },
});

defineTool({
  name: 'medical_create_scene',
  module: 'medical', kind: 'mutate', needsProbe: false,
  title: 'Create a medical scene',
  description: 'Creates a medical scene workspace (kind "medical") centred on a location with ERM task data (title, description, caller, priority 1-4) and random-generator settings (enabled, weight). Add content with medical_add_vehicle / medical_add_patient or any generic entity tool using workspace = the scene name.',
  input: { name: z.string(), center: point.optional(), radius: z.number().optional(), erm: erm.optional(), dimension: z.number().int().optional(), enabled: z.boolean().optional(), weight: z.number().optional() },
  returns: ['scene summary', 'zone'],
  related: ['medical_add_patient', 'medical_add_vehicle', 'medical_build_from_template'],
  async handler(a, ctx) { return ctx.call('medical', 'createScene', { ...a, center: await ctx.bridgePoint(a.center) }); },
});

defineTool({
  name: 'medical_add_patient',
  module: 'medical', kind: 'mutate', needsProbe: 'partial',
  title: 'Add a patient',
  description: 'Adds an injured ped to a medical scene: skin (or sex male|female for a random fitting skin), placement (any generic placement mode, e.g. near a crashed car or on the sidewalk) or position + heading, pose (anim id), injuries [{type, severity}], medsys state preset, or seated in a scene vehicle (vehicle + seat). Validated against the catalog. medsys is NOT started (use medical_simulate_patient to test vitals).',
  input: {
    scene: z.string(), id: z.string().optional(), skin: z.number().int().optional(), sex: z.enum(['male', 'female']).optional(),
    placement: placement.optional(), position: point.optional(), heading: z.number().optional(),
    anim: z.string().optional().describe('patient pose id (default ko_back)'), injuries: z.array(injury).optional(), state: state.optional(),
    vehicle: z.string().optional(), seat: z.number().int().optional(), frozen: z.boolean().optional(),
  },
  returns: ['patient (entity + live ground info)', 'sex', 'warnings'],
  sideEffects: 'Creates a ped.',
  related: ['medical_set_patient', 'medical_validate_scene'],
  async handler(a, ctx) {
    const p = { ...a };
    if (p.placement) p.placement = await translatePlacement(p.placement, ctx);
    if (p.position) p.position = await ctx.bridgePoint(p.position);
    return ctx.call('medical', 'addPatient', p);
  },
});

defineTool({
  name: 'medical_add_vehicle',
  module: 'medical', kind: 'mutate', needsProbe: 'partial',
  title: 'Add a scene vehicle',
  description: 'Adds a vehicle to a medical scene with semantic placement and a damage preset (repair, light, heavy, wreck), lights / sirens / engine / lock, colours, plate, role (e.g. "crash", "striking vehicle") and liveFrozen (frozen in the live scene).',
  input: {
    scene: z.string(), model: z.number().int(), id: z.string().optional(), placement: placement.optional(), position: point.optional(), heading: z.number().optional(),
    damage: z.union([z.enum(['repair', 'light', 'heavy', 'wreck']), z.record(z.any())]).optional(), engine: z.boolean().optional(), lightsOn: z.boolean().optional(),
    sirens: z.boolean().optional(), locked: z.boolean().optional(), colors: z.array(z.number()).optional(), color: z.array(z.number()).optional(),
    plate: z.string().optional(), role: z.string().optional(), liveFrozen: z.boolean().optional(),
  },
  returns: ['vehicle (entity, damage state, live)', 'warnings'],
  sideEffects: 'Creates a vehicle.',
  related: ['medical_add_patient', 'place_entity'],
  async handler(a, ctx) {
    const p = { ...a };
    if (p.placement) p.placement = await translatePlacement(p.placement, ctx);
    if (p.position) p.position = await ctx.bridgePoint(p.position);
    return ctx.call('medical', 'addVehicle', p);
  },
});

defineTool({
  name: 'medical_set_patient',
  module: 'medical', kind: 'mutate', needsProbe: false,
  title: 'Edit a patient',
  description: 'Changes a patient\'s pose (anim), replaces injuries or appends addInjuries, merges state (clearState first to reset). Also turns any workspace ped into a patient.',
  input: { id: z.string(), anim: z.string().optional(), injuries: z.array(injury).optional(), addInjuries: z.array(injury).optional(), state: state.optional(), clearState: z.boolean().optional() },
  returns: ['medical data'],
  sideEffects: 'Changes the ped animation / scene data.',
  related: ['medical_add_patient'],
  async handler(a, ctx) { return ctx.call('medical', 'setPatient', a); },
});

defineTool({
  name: 'medical_build_from_template',
  module: 'medical', kind: 'mutate', needsProbe: 'partial',
  title: 'Build a scene from a template',
  description: `Builds a complete medical scene at a real location using the road graph + live placement: ${Object.entries(TEMPLATES).map(([k, t]) => `${k} (${t.description})`).join('; ')}. Creates the scene workspace (name), vehicles, patients, ERM data (overridable), then validates (generic + EMS access) and optionally captures an overview screenshot. Treat the result as a draft: read the diagnostics, adjust with place_entity / medical_set_patient, re-validate, then medical_export_scene.`,
  input: {
    template: z.enum(Object.keys(TEMPLATES)), name: z.string(), near: point.optional().describe('default: the probe player'),
    erm: erm.optional(), searchRadius: z.number().optional(), validate: z.boolean().optional(), capture: z.boolean().optional(), dimension: z.number().int().optional(),
  },
  returns: ['scene', 'created[]', 'validation', 'image (capture)'],
  sideEffects: 'Creates a workspace and its elements.',
  related: ['medical_validate_scene', 'medical_export_scene', 'capture_view'],
  async handler(a, ctx) {
    const t = TEMPLATES[a.template];
    const near = await ctx.locate(a.near);
    const scene = await ctx.call('medical', 'createScene', {
      name: a.name, center: { x: near.x, y: near.y, z: near.z }, erm: { ...t.erm, ...(a.erm || {}) }, dimension: a.dimension,
    });
    const s = sceneBuilder(ctx, a.name, near, a);
    let buildError = null;
    try {
      await t.build(s);
    } catch (e) {
      buildError = { code: e.code, message: e.message, suggestion: 'Partial scene kept; fix or clear_workspace and retry elsewhere.' };
    }
    // centre the ERM task on the patients
    const pts = s.created.filter((c) => c.type === 'patient' && c.position && !c.inVehicle);
    if (pts.length) {
      const c = pts.reduce((acc, p) => ({ x: acc.x + p.position.x / pts.length, y: acc.y + p.position.y / pts.length, z: acc.z + p.position.z / pts.length }), { x: 0, y: 0, z: 0 });
      await ctx.call('workspace', 'update', { workspace: a.name, center: { x: round(c.x), y: round(c.y), z: round(c.z) } });
    }
    const out = { template: a.template, scene: scene.scene, zone: scene.zone, created: s.created, warnings: s.warnings, buildError };
    if (a.validate !== false) {
      try { out.validation = await ctx.call('medical', 'validate', { scene: a.name }, { timeoutMs: 90000 }); } catch (e) { out.validation = { error: e.code, message: e.message }; }
    }
    if (a.capture) {
      try {
        const shot = await ctx.call('screenshot', 'capture', { workspace: a.name, view: 'orbit', overlay: true, daylight: true }, { timeoutMs: 60000 });
        const { image, ...meta } = shot;
        out.capture = meta;
        meta.savedTo = saveShot(ctx, image, a.name);
        return { __mcp: true, content: [{ type: 'text', text: JSON.stringify(out) }, { type: 'image', data: image, mimeType: 'image/jpeg' }] };
      } catch (e) { out.capture = { error: e.code, message: e.message }; }
    }
    return out;
  },
});

defineTool({
  name: 'medical_validate_scene',
  module: 'medical', kind: 'read', needsProbe: 'partial',
  title: 'Validate a medical scene',
  description: 'Generic validation (ground, collisions, overlaps, water...) plus medical checks: at least one patient, patients with injuries/state, ERM title/description, patients near the ERM centre, stretcher / medic room around each lying patient, patient lying on the road, a free road spot for an ambulance (default model 416) within 35 m with a direct line to the patient. Returns structured errors / warnings / per-patient access info. Read-only.',
  input: { scene: z.string(), ambulanceModel: z.number().int().optional() },
  returns: ['valid', 'errors[]', 'warnings[]', 'medical {patients, access[] {ambulanceSpot, sidesWithStretcherRoom}}'],
  related: ['validate_workspace', 'capture_view', 'medical_export_scene'],
  async handler(a, ctx) { return ctx.call('medical', 'validate', a, { timeoutMs: 90000 }); },
});

defineTool({
  name: 'medical_export_scene',
  module: 'medical', kind: 'mutate', needsProbe: false,
  title: 'Export to med_scenemanager',
  description: 'Converts a medical scene into the med_scenemanager JSON format (format 1: centre, ERM, vehicles with real transform + damage/colours/plate state read from MTA, peds with skin/pos/rot/anim/vehicle seat/injuries/state). save = true writes scenes/<name>.json and the index through med_scenemanager (overwrite to replace); without save it only returns the JSON (read-only).',
  input: { scene: z.string(), name: z.string().optional(), save: z.boolean().optional(), overwrite: z.boolean().optional() },
  returns: ['scene JSON', 'saved', 'file'],
  sideEffects: 'save writes a scene file used by the live auto generator.',
  related: ['medical_validate_scene', 'medical_live_scene'],
  async handler(a, ctx) { return ctx.call('medical', 'export', a); },
});

defineTool({
  name: 'medical_load_scene',
  module: 'medical', kind: 'mutate', needsProbe: false,
  title: 'Load a med_scenemanager scene',
  description: 'Loads an existing med_scenemanager scene file into a medical workspace (default name msm_<scene>) so it can be inspected, validated, fixed and exported again.',
  input: { name: z.string(), workspace: z.string().optional(), dimension: z.number().int().optional() },
  returns: ['scene', 'created[]'],
  sideEffects: 'Creates elements.',
  related: ['medical_validate_scene', 'medical_export_scene'],
  async handler(a, ctx) { return ctx.call('medical', 'load', a); },
});

defineTool({
  name: 'medical_live_scene',
  module: 'medical', kind: 'mutate', needsProbe: false,
  title: 'med_scenemanager live scenes',
  description: 'files: saved scene summaries; list: live scenes; spawn: spawns a saved scene for real (creates an ERM dispatch task!); remove: removes a live scene by instance id (closes its task).',
  input: { action: z.enum(['files', 'list', 'spawn', 'remove']), name: z.string().optional(), id: z.number().int().optional() },
  returns: ['scenes / active / instanceId'],
  sideEffects: 'spawn creates elements and a real ERM task; remove destroys them.',
  related: ['medical_export_scene'],
  async handler(a, ctx) { return ctx.call('medical', 'live', a); },
});

defineTool({
  name: 'medical_simulate_patient',
  module: 'medical', kind: 'mutate', needsProbe: false,
  title: 'Run medsys on a patient',
  description: 'Applies the patient\'s injuries + state to medsys (starts the live vitals simulation) and returns the medsys state after a moment; enable = false heals and stops it. state_only = true just reads the current medsys state. For testing presets before export.',
  input: { id: z.string(), enable: z.boolean().optional(), stateOnly: z.boolean().optional() },
  returns: ['medsys state'],
  sideEffects: 'Starts / stops medsys simulation on the ped.',
  related: ['medical_set_patient'],
  async handler(a, ctx) {
    if (a.stateOnly) return ctx.call('medical', 'patientState', { id: a.id });
    return ctx.call('medical', 'simulate', a);
  },
});

export { TEMPLATES };
