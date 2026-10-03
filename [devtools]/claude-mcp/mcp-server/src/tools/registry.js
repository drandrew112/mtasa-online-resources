// Tool definitions with capability metadata. Every tool is described once here
// and that description feeds both MCP registration and the capability map.

import { asErrorObject, ToolError } from '../errors.js';
import { toPoint } from '../geo.js';

export const TOOLS = [];

/**
 * def: {
 *   name, module, kind: 'read' | 'mutate', title, description,
 *   input: zod shape, returns: string[], sideEffects: string, prerequisites: string[],
 *   limitations: string[], related: string[], needsProbe: bool | 'partial', handler(args, ctx)
 * }
 */
export function defineTool(def) {
  TOOLS.push(def);
  return def;
}

// keys removed from tool output (bulky internals)
const DROP = new Set(['obb']);

function strip(v, depth = 0) {
  if (depth > 40) return v;
  if (Array.isArray(v)) return v.map((x) => strip(x, depth + 1));
  if (v && typeof v === 'object') {
    const out = {};
    for (const [k, x] of Object.entries(v)) {
      if (DROP.has(k) || x === null || x === undefined) continue;
      out[k] = strip(x, depth + 1);
    }
    return out;
  }
  if (typeof v === 'number' && !Number.isInteger(v)) return Math.round(v * 10000) / 10000;
  return v;
}

export function textResult(obj, extra = []) {
  return { content: [{ type: 'text', text: JSON.stringify(strip(obj)) }, ...extra] };
}

export function errorResult(err) {
  return { isError: true, content: [{ type: 'text', text: JSON.stringify({ success: false, error: asErrorObject(err) }) }] };
}

/** Wraps a handler: structured errors, bridge-restart notices, image passthrough. */
export function wrap(def, ctx) {
  return async (args) => {
    try {
      const out = await def.handler(args || {}, ctx);
      const notice = ctx.bridge.consumeNotice();
      if (out && out.__mcp) {
        // handler built its own content (images)
        if (notice) out.content.unshift({ type: 'text', text: JSON.stringify({ notice }) });
        return { content: out.content };
      }
      const body = notice && out && typeof out === 'object' && !Array.isArray(out) ? { notice, ...out } : out;
      return textResult(body);
    } catch (err) {
      return errorResult(err);
    }
  };
}

/** Builds the context helpers shared by tools. */
export function makeContext({ bridge, roads, config, cache }) {
  const ctx = {
    bridge, roads, config, cache,
    call: (category, action, params, opts) => bridge.call(category, action, params, opts),

    /**
     * Resolves a location spec to coordinates:
     *   "player" | entity id | { x, y, z } | [x, y, z] | { node: id } | { entity: id }
     * -> { x, y, z, heading?, source, id? }
     */
    async locate(spec, name = 'position') {
      if (spec === undefined || spec === null || spec === 'player' || spec === 'probe') {
        const p = await bridge.call('player', 'get', {});
        return { x: p.position.x, y: p.position.y, z: p.position.z, heading: p.heading, source: 'player', dimension: p.dimension, interior: p.interior };
      }
      if (typeof spec === 'object' && !Array.isArray(spec) && spec.node !== undefined) {
        const n = roads.get(spec.node);
        if (!n) throw new ToolError('ROAD_NODE_NOT_FOUND', `Road node ${spec.node} does not exist.`, { suggestion: 'Use get_nearest_road_node to find node ids.' });
        return { x: n.x, y: n.y, z: n.z, heading: roads.roadHeading(n)?.heading, source: 'road_node', node: n.id };
      }
      if (typeof spec === 'string' || (typeof spec === 'object' && (spec.entity || spec.id))) {
        const id = typeof spec === 'string' ? spec : spec.entity || spec.id;
        const e = await bridge.call('entities', 'get', { id, detail: 'low' });
        return { x: e.position.x, y: e.position.y, z: e.position.z, heading: e.heading, source: 'entity', id: e.id, type: e.type, model: e.model };
      }
      const p = toPoint(spec);
      if (!p || !Number.isFinite(p.x) || !Number.isFinite(p.y)) {
        throw new ToolError('INVALID_PARAMS', `${name} must be "player", an entity id, {x,y,z}, [x,y,z] or {node: id}.`);
      }
      return { ...p, source: 'point' };
    },

    /** Passes a location spec to the bridge (it understands player / entity ids / points; nodes are converted). */
    async bridgePoint(spec, name) {
      if (spec && typeof spec === 'object' && !Array.isArray(spec) && spec.node !== undefined) {
        const p = await ctx.locate(spec, name);
        return { x: p.x, y: p.y, z: p.z };
      }
      return spec;
    },
  };
  return ctx;
}
