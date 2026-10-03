import { z } from 'zod';
import fs from 'node:fs';
import path from 'node:path';
import { defineTool } from './registry.js';
import { point } from './schemas.js';

export function saveShot(ctx, base64, label) {
  const dir = ctx.config.screenshotDir;
  if (!dir) return undefined;
  try {
    fs.mkdirSync(dir, { recursive: true });
    const file = path.join(dir, `${new Date().toISOString().replace(/[:.]/g, '-')}_${label}.jpg`);
    fs.writeFileSync(file, Buffer.from(base64, 'base64'));
    return file;
  } catch {
    return undefined;
  }
}

async function shoot(a, ctx, label) {
  const p = { ...a };
  if (p.target) p.target = await ctx.bridgePoint(p.target);
  if (p.position) p.position = await ctx.bridgePoint(p.position);
  let r;
  try {
    r = await ctx.call('screenshot', 'capture', p, { timeoutMs: 60000 });
  } catch (err) {
    // the bridge now knows that window is minimized and gives the retry to another probe
    if (err?.code !== 'SCREENSHOT_MINIMIZED' || p.view === 'current') throw err;
    r = await ctx.call('screenshot', 'capture', p, { timeoutMs: 60000 });
  }
  const { image, ...meta } = r;
  meta.savedTo = saveShot(ctx, image, label);
  return { meta, image, mimeType: r.mimeType || 'image/jpeg' };
}

async function capture(a, ctx, label) {
  const { meta, image, mimeType } = await shoot(a, ctx, label);
  return { __mcp: true, content: [{ type: 'text', text: JSON.stringify(meta) }, { type: 'image', data: image, mimeType }] };
}

const shotInput = {
  width: z.number().int().min(160).max(1920).optional(), height: z.number().int().min(120).max(1080).optional(),
  quality: z.number().int().min(10).max(100).optional(), hideHud: z.boolean().optional().describe('hide the custom UI (v_radar minimap, ui_core overlays via the hideHUD element data) and the chat during the shot, restored afterwards (default true). The GTA HUD is never touched.'),
  daylight: z.boolean().optional().describe('default true: 12:00 clear weather on the probe client during the shot, the real time / weather is restored right after. false = keep the current time / weather (night shots, weather checks).'),
  overlay: z.boolean().optional().describe('draw entity ids / bounding boxes / heading arrows in the shot'),
};

defineTool({
  name: 'capture_screenshot',
  module: 'visual', kind: 'read', needsProbe: true,
  title: 'Screenshot of the current view',
  description: 'JPEG screenshot of what the probe player\'s game client shows right now (real MTA world). Returns the image + camera info; also saved under claude-mcp/screenshots/. Requires "Allow screen upload" in the client settings and a non-minimized game window.',
  input: shotInput,
  returns: ['image/jpeg', 'camera', 'savedTo'],
  related: ['capture_view', 'set_debug_overlay'],
  async handler(a, ctx) { return capture({ ...a, view: 'current' }, ctx, 'current'); },
});

defineTool({
  name: 'capture_view',
  module: 'visual', kind: 'read', needsProbe: true,
  title: 'Screenshot from a computed camera',
  description: 'Moves the probe camera to a computed viewpoint, waits for streaming, takes a screenshot and restores the camera. view: orbit (yaw degrees around the target relative to its heading, default 35), front, back, left, right (relative to the target heading), top (straight down), free (explicit position -> target). Target: entity id, point, {node}, or workspace (frames all its entities; covers capture_scene_view / capture_area_view). distance / cameraHeight auto-fit to the model size. overlay = true labels entities with ids and boxes. Combine with validate_workspace to judge placements.',
  input: {
    ...shotInput,
    view: z.enum(['orbit', 'top', 'front', 'back', 'left', 'right', 'free', 'current']).optional(),
    target: point.optional(), workspace: z.string().optional(), position: point.optional(),
    distance: z.number().optional().describe('camera distance from the target (auto-fit)'), cameraHeight: z.number().optional().describe('camera height above the target (auto)'), yaw: z.number().optional(), fov: z.number().optional(),
    avoidOcclusion: z.boolean().optional().describe('default true: try other yaws / closer views when a wall blocks the line of sight'),
    targetLift: z.number().optional(), settle: z.number().int().optional().describe('ms to wait for streaming (default 900)'),
  },
  returns: ['image/jpeg', 'camera {position, target}', 'savedTo'],
  sideEffects: 'Temporarily moves the probe player\'s camera (restored after the shot).',
  related: ['capture_screenshot', 'set_debug_overlay', 'inspect_workspace'],
  async handler(a, ctx) { return capture({ view: 'orbit', ...a }, ctx, a.view || 'orbit'); },
});

const viewInput = {
  view: z.enum(['orbit', 'top', 'front', 'back', 'left', 'right', 'free']).optional(),
  target: point.optional(), workspace: z.string().optional(), position: point.optional(),
  distance: z.number().optional(), cameraHeight: z.number().optional(), yaw: z.number().optional(), fov: z.number().optional(),
  avoidOcclusion: z.boolean().optional(), targetLift: z.number().optional(), settle: z.number().int().optional(),
};

defineTool({
  name: 'capture_views',
  module: 'visual', kind: 'read', needsProbe: true,
  title: 'Several screenshots in parallel',
  description: 'Takes several capture_view shots at once. Each shot is its own bridge job, so with several probe clients connected they run in parallel on different game clients (one client takes them one after another). Shared settings (size, quality, daylight, overlay, target / workspace...) go at the top level, each entry of views overrides them. Failed shots are reported per view; the others are still returned.',
  input: {
    ...shotInput, ...viewInput,
    views: z.array(z.object({ ...viewInput, label: z.string().optional() })).min(1).max(12),
  },
  returns: ['image/jpeg per view', 'per-view camera / probe / error'],
  sideEffects: 'Temporarily moves probe cameras (restored after each shot).',
  related: ['capture_view', 'get_status'],
  async handler(a, ctx) {
    const { views, ...common } = a;
    const results = await Promise.allSettled(views.map((v, i) => {
      const { label, ...spec } = v;
      const merged = { view: 'orbit', ...common, ...spec };
      return shoot(merged, ctx, label || `${merged.view}${i + 1}`);
    }));
    const content = [];
    results.forEach((r, i) => {
      const label = views[i].label || `${views[i].view || common.view || 'orbit'} #${i + 1}`;
      if (r.status === 'fulfilled') {
        content.push({ type: 'text', text: JSON.stringify({ view: label, ...r.value.meta }) });
        content.push({ type: 'image', data: r.value.image, mimeType: r.value.mimeType });
      } else {
        const e = r.reason || {};
        content.push({ type: 'text', text: JSON.stringify({ view: label, ok: false, error: { code: e.code, message: e.message } }) });
      }
    });
    return { __mcp: true, content };
  },
});

defineTool({
  name: 'set_debug_overlay',
  module: 'visual', kind: 'mutate', needsProbe: true,
  title: 'Debug drawing in the game',
  description: 'Draws helpers on the probe client (visible in screenshots and to the developer): entity labels (id + heading) and bounding boxes with front arrows (filter by workspace / ids), custom lines {from,to,color,label}, marker points {position,label,color}, and road nodes + links around a centre (roadArea {center, radius}) or a node path (pathNodes). clear removes lines/points/nodes; enabled false hides everything.',
  input: {
    enabled: z.boolean().optional(), labels: z.boolean().optional(), boxes: z.boolean().optional(), axes: z.boolean().optional(),
    workspace: z.string().optional(), ids: z.array(z.string()).optional(), clear: z.boolean().optional(), maxDistance: z.number().optional(),
    lines: z.array(z.object({ from: point, to: point, color: z.array(z.number()).optional(), label: z.string().optional(), width: z.number().optional() })).optional(),
    points: z.array(z.object({ position: point, label: z.string().optional(), color: z.array(z.number()).optional() })).optional(),
    roadArea: z.object({ center: point.optional(), radius: z.number().optional() }).optional(),
    pathNodes: z.array(z.number().int()).optional(),
  },
  returns: ['enabled', 'counts'],
  sideEffects: 'Client-side drawing only (probe player).',
  related: ['capture_view', 'find_road_path'],
  async handler(a, ctx) {
    const p = { ...a };
    delete p.roadArea; delete p.pathNodes;
    const toNode = (n) => ({ id: n.id, x: n.x, y: n.y, z: n.z, label: String(n.id), links: [...n.adj].map((id) => { const o = ctx.roads.get(id); return [o.x, o.y, o.z]; }) });
    if (a.roadArea) {
      const c = await ctx.locate(a.roadArea.center);
      p.nodes = ctx.roads.nodesWithin(c.x, c.y, a.roadArea.radius || 80).slice(0, 600).map(toNode);
    }
    if (a.pathNodes) {
      p.nodes = [...(p.nodes || []), ...a.pathNodes.map((id) => ctx.roads.get(id)).filter(Boolean).map(toNode)];
    }
    if (p.lines) p.lines = await Promise.all(p.lines.map(async (l) => ({ ...l, from: await ctx.bridgePoint(l.from), to: await ctx.bridgePoint(l.to) })));
    if (p.points) p.points = await Promise.all(p.points.map(async (x) => ({ ...x, position: await ctx.bridgePoint(x.position) })));
    return ctx.call('screenshot', 'overlay', p);
  },
});

defineTool({
  name: 'get_player_state',
  module: 'player', kind: 'read', needsProbe: false,
  title: 'Probe player state',
  description: 'The probe player (or a named player): position, heading, compass, vehicle, dimension/interior, zone, camera position/target, fps, screen size. all = true lists every player. Read-only.',
  input: { player: z.string().optional(), all: z.boolean().optional() },
  returns: ['player state'],
  related: ['get_current_location_context', 'teleport_probe'],
  async handler(a, ctx) { return a.all ? ctx.call('player', 'list', {}) : ctx.call('player', 'get', a); },
});

defineTool({
  name: 'select_probe',
  module: 'player', kind: 'mutate', needsProbe: false,
  title: 'Choose the probe client',
  description: 'Makes a connected player (name or el_player ref) the PRIMARY probe: the one meant by "player" / "probe" / "camera", the player and camera tools and current-view screenshots. With several game clients connected, the other ready clients in the same dimension still take parallel work (each request goes to the least busy one; get_status lists them under probes). Screenshot work skips minimized windows.',
  input: { player: z.string() },
  returns: ['probe'],
  sideEffects: 'Changes which client answers geometry queries.',
  related: ['get_player_state', 'get_status'],
  async handler(a, ctx) { return ctx.call('player', 'setProbe', a); },
});

defineTool({
  name: 'teleport_probe',
  module: 'player', kind: 'mutate', needsProbe: true,
  title: 'Teleport the probe player',
  description: 'Moves the probe player (with its vehicle when driving, unless keepVehicle false) to a location, optional heading / dimension / interior, then waits for streaming. Needed before working far away: collision and models only exist near the probe. Mutates the developer\'s player.',
  input: { position: point, heading: z.number().optional(), dimension: z.number().int().optional(), interior: z.number().int().optional(), keepVehicle: z.boolean().optional(), exactZ: z.boolean().optional(), wait: z.number().int().optional(), player: z.string().optional() },
  returns: ['state after teleport'],
  sideEffects: 'Moves a real player.',
  related: ['get_current_location_context'],
  async handler(a, ctx) { return ctx.call('player', 'teleport', { ...a, position: await ctx.bridgePoint(a.position) }); },
});

defineTool({
  name: 'set_camera',
  module: 'player', kind: 'mutate', needsProbe: true,
  title: 'Probe camera control',
  description: 'mode get: camera matrix, look heading/pitch and what the screen centre hits. mode set: fixed camera at position looking at target (stays until reset). mode reset: back to the player. capture_view already handles cameras for screenshots.',
  input: { mode: z.enum(['get', 'set', 'reset']), position: point.optional(), target: point.optional(), fov: z.number().optional(), roll: z.number().optional() },
  returns: ['camera'],
  sideEffects: 'set/reset change the developer\'s camera.',
  related: ['capture_view', 'raycast (mode camera)'],
  async handler(a, ctx) {
    if (a.mode === 'get') return ctx.call('camera', 'get', {});
    if (a.mode === 'reset') return ctx.call('camera', 'reset', {});
    return ctx.call('camera', 'set', { ...a, position: await ctx.bridgePoint(a.position), target: await ctx.bridgePoint(a.target) });
  },
});
