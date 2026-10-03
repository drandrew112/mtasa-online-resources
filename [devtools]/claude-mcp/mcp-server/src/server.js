// Builds the context (bridge client + road graph) and the MCP server.

import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { z } from 'zod';
import { config } from './config.js';
import { Bridge } from './bridge.js';
import { RoadGraph } from './roads/graph.js';
import { DataCache } from './cache.js';
import { TOOLS, makeContext, wrap } from './tools/registry.js';
import { buildCapabilityMap, WORKFLOWS } from './capabilities.js';
import './tools/system.js';
import './tools/world.js';
import './tools/roads.js';
import './tools/models.js';
import './tools/entities.js';
import './tools/workspace.js';
import './tools/visual.js';
import './tools/dev.js';
import './tools/medical.js';
import './tools/cache.js';

export async function createContext() {
  const bridge = new Bridge();
  await bridge.start();
  const roads = new RoadGraph();
  try {
    roads.load(config.vehicleNodesPath);
  } catch (err) {
    process.stderr.write(`[mta-world-mcp] road graph not loaded (${config.vehicleNodesPath}): ${err.message}\n`);
  }
  return makeContext({ bridge, roads, config, cache: new DataCache(config.cacheDir) });
}

export function createServer(ctx) {
  const server = new McpServer(
    { name: 'mta-world-mcp', version: config.version },
    {
      instructions: [
        'MTA World MCP: inspect and edit a live Multi Theft Auto: San Andreas world.',
        'Start with get_capability_map (tools, workflows, conventions) and get_status.',
        'Never guess coordinates, model ids or rotations: inspect (get_current_location_context, inspect_area, roads, get_model_info),',
        'create with semantic placements, then verify with inspect_entity / validate_workspace / capture_view and iterate.',
        'Headings: MTA rotation.z, 0 = north, 90 = west (counter-clockwise). Medical scenes: medical_* tools on top of the generic ones.',
      ].join(' '),
    },
  );

  for (const def of TOOLS) {
    server.registerTool(def.name, {
      title: def.title,
      description: def.description,
      inputSchema: def.input || {},
      annotations: {
        title: def.title,
        readOnlyHint: def.kind === 'read',
        destructiveHint: def.kind !== 'read' && /delete|clear|destroy/i.test(def.name + (def.sideEffects || '')),
        idempotentHint: def.kind === 'read',
        openWorldHint: false,
      },
    }, wrap(def, ctx));
  }

  server.registerResource('capability-map', 'mta://capability-map', {
    title: 'MTA World MCP capability map', description: 'Same content as get_capability_map', mimeType: 'application/json',
  }, async (uri) => ({ contents: [{ uri: uri.href, mimeType: 'application/json', text: JSON.stringify(await buildCapabilityMap(ctx, {})) }] }));

  server.registerResource('road-network', 'mta://road-network', {
    title: 'Road network statistics', mimeType: 'application/json',
  }, async (uri) => ({ contents: [{ uri: uri.href, mimeType: 'application/json', text: JSON.stringify(ctx.roads.stats()) }] }));

  for (const w of WORKFLOWS) {
    server.registerPrompt(`workflow_${w.name}`, {
      title: w.goal, description: `Tool chain: ${w.steps.join(' -> ')}`,
      argsSchema: { task: z.string().optional() },
    }, ({ task }) => ({
      messages: [{
        role: 'user',
        content: { type: 'text', text: `${task ? `Task: ${task}\n` : ''}Goal: ${w.goal}. Follow this MTA World MCP workflow, inspecting results and validating before you finish:\n${w.steps.map((s, i) => `${i + 1}. ${s}`).join('\n')}` },
      }],
    }));
  }
  return server;
}
