import { z } from 'zod';
import { defineTool } from './registry.js';

defineTool({
  name: 'get_vehicle_models',
  module: 'models', kind: 'read', needsProbe: false,
  title: 'Vehicle model list',
  description: 'Every vehicle model (400-611) with its display name from veh_manager:getModelName (authoritative; modded names such as "Mission Row Ambulance"), the GTA name, category (Automobile, Bike, Helicopter, Boat, Plane, Train, Trailer, Monster Truck, Quad, BMX) and seat count; measured dimensions when already measured. Filter by search text or category. Read-only.',
  input: { search: z.string().optional(), category: z.string().optional() },
  returns: ['vehicles[] {model, name, gtaName, category, maxPassengers, dimensions?}', 'categories'],
  related: ['get_model_info', 'search_models', 'spawn_entity'],
  async handler(a, ctx) { return ctx.call('models', 'vehicles', a); },
});

defineTool({
  name: 'get_ped_models',
  module: 'models', kind: 'read', needsProbe: 'partial',
  title: 'Ped (skin) model list by sex',
  description: 'Valid ped models split explicitly into male and female lists (sex from the project list in med_scenemanager; every record has sex + sexSource) with dff names from the game when a probe is connected. sex = "male" | "female" returns one list. Read-only.',
  input: { sex: z.enum(['male', 'female']).optional() },
  returns: ['male[] / female[] {model, sex, dffName}'],
  related: ['get_model_info', 'medical_add_patient'],
  async handler(a, ctx) { return ctx.call('models', 'peds', a); },
});

defineTool({
  name: 'get_object_models',
  module: 'models', kind: 'read', needsProbe: true,
  title: 'Object model catalog',
  description: 'Object models by dff-name substring and/or id range from the game\'s model table (e.g. search "cone", "barrier", "bench", "stretcher"). Each record: model id, dffName, kind (name heuristic). Read-only; first call loads the catalog from the probe.',
  input: { search: z.string().optional(), from: z.number().int().optional(), to: z.number().int().optional(), limit: z.number().int().max(2000).optional() },
  returns: ['objects[] {model, dffName, kind}', 'total'],
  related: ['search_models', 'get_model_info', 'spawn_entity'],
  async handler(a, ctx) { return ctx.call('models', 'objects', a, { timeoutMs: 60000 }); },
});

defineTool({
  name: 'search_models',
  module: 'models', kind: 'read', needsProbe: 'partial',
  title: 'Search all models',
  description: 'Searches vehicle names (veh_manager + GTA), vehicle categories, ped dff names / sex and object dff names in one go. type narrows to vehicle | ped | object. Use instead of guessing model ids. Read-only.',
  input: { query: z.string(), type: z.enum(['vehicle', 'ped', 'object', 'any']).optional(), limit: z.number().int().max(500).optional() },
  returns: ['results[] (vehicle / ped / object records)'],
  related: ['get_model_info'],
  async handler(a, ctx) { return ctx.call('models', 'search', a, { timeoutMs: 60000 }); },
});

defineTool({
  name: 'get_model_info',
  module: 'models', kind: 'read', needsProbe: 'partial',
  title: 'Model details + measured dimensions',
  description: 'Everything known about one model id (type auto-detected): vehicle name (veh_manager), category, seats, handling summary (mass, max velocity, drive type...), ped sex + dff name, object dff name; plus MEASURED geometry from the game: bounding box, size (x = width, y = length, z = height), radius, base offset (centre to bottom), and for vehicles wheel positions, dummies (seats, lights, exhaust...) and components. Cached. Read-only. Replaces get_vehicle_model / get_ped_model / get_object_model.',
  input: { model: z.number().int(), type: z.enum(['vehicle', 'ped', 'object']).optional(), measure: z.boolean().optional(), refresh: z.boolean().optional() },
  returns: ['record', 'measured {bbox, size, baseOffset, wheels, dummies}'],
  related: ['spawn_entity', 'place_entity'],
  async handler(a, ctx) { return ctx.call('models', 'info', a); },
});
