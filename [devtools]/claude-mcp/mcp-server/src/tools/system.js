import { z } from 'zod';
import { defineTool, TOOLS } from './registry.js';
import { buildCapabilityMap } from '../capabilities.js';

const started = Date.now();

defineTool({
  name: 'get_capability_map',
  module: 'system', kind: 'read', needsProbe: false,
  title: 'What can this system do?',
  description: 'START HERE. Machine-readable map of the MTA World MCP system: modules, every tool (purpose, read vs mutating, parameters, returns, side effects, probe requirement, limitations, related tools), workflows (tool chains such as inspect -> road node -> place on road -> validate), tool relationships, coordinate / heading / lane conventions, entity types, poses, inspection + validation methods, world data sources, visual feedback and live connection status. Filter with module or tool; schemas = true adds full JSON input schemas. Read-only.',
  input: { module: z.string().optional(), tool: z.string().optional(), schemas: z.boolean().optional() },
  returns: ['system', 'modules[]', 'tools[]', 'workflows[]', 'relationships[]', 'conventions', 'validationMethods', 'worldData'],
  related: ['get_status'],
  async handler(a, ctx) { return buildCapabilityMap(ctx, a); },
});

defineTool({
  name: 'get_status',
  module: 'system', kind: 'read', needsProbe: false,
  title: 'System status',
  description: 'Connection and state overview: MCP server (version, uptime, tools), bridge reachability + instance id + restarts detected, MTA server info, probe client (player, position, dimension), players, workspaces + entity count, pending jobs, integrations (veh_manager, medsys, med_scenemanager, med_erm...), road-network index stats, caches, last success / last error. Never fails: an unreachable bridge is reported inside. Read-only.',
  input: {},
  returns: ['mcp', 'bridge', 'mta', 'probe', 'workspaces', 'roadNetwork', 'integrations'],
  related: ['get_health', 'get_capability_map'],
  async handler(a, ctx) {
    const out = {
      mcp: { version: ctx.config.version, uptimeSec: Math.round((Date.now() - started) / 1000), tools: TOOLS.length, node: process.version, memoryMB: Math.round(process.memoryUsage().rss / 1048576) },
      connection: ctx.bridge.stats(),
      roadNetwork: ctx.roads.stats(),
    };
    try {
      const s = await ctx.call('status', 'get', {});
      Object.assign(out, { bridge: s.bridge, mta: s.server, probe: s.probe, probes: s.probes, players: s.players, workspaces: s.workspaces, entityCount: s.entityCount, jobs: s.jobs, bridgeRequests: s.requests, integrations: s.integrations, settings: s.settings });
    } catch (e) {
      out.bridge = { reachable: false, error: { code: e.code, message: e.message, suggestion: e.extra?.suggestion } };
    }
    return out;
  },
});

defineTool({
  name: 'get_health',
  module: 'system', kind: 'read', needsProbe: false,
  title: 'Health checks',
  description: 'Health checks with structured problems: MTA reachable, bridge running, probe client present, missing entities, integrations, road index loaded, callback listener, recent errors. healthy = true when everything needed for full functionality works. Read-only.',
  input: {},
  returns: ['healthy', 'problems[] {code, severity, message, suggestion}'],
  related: ['get_status'],
  async handler(a, ctx) {
    const problems = [];
    const roads = ctx.roads.stats();
    if (!roads.nodes) problems.push({ code: 'ROAD_INDEX_EMPTY', severity: 'degraded', message: 'Road graph not loaded.', suggestion: 'Check VEHICLE_NODES path.' });
    const conn = ctx.bridge.stats();
    if (!ctx.bridge.callbackUrl) problems.push({ code: 'CALLBACK_DISABLED', severity: 'info', message: String(conn.callback), suggestion: 'Results are polled instead (slightly slower).' });
    let bridge = null;
    try {
      bridge = await ctx.call('status', 'health', {});
      for (const p of bridge.problems || []) problems.push(p);
    } catch (e) {
      problems.push({ code: e.code, severity: 'down', message: e.message, suggestion: e.extra?.suggestion });
    }
    return {
      healthy: !problems.some((p) => p.severity === 'down' || p.severity === 'degraded'),
      problems, bridge, connection: conn, roadIndex: { nodes: roads.nodes, loadMs: roads.loadMs },
    };
  },
});
