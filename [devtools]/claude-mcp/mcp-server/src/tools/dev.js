import { z } from 'zod';
import { defineTool } from './registry.js';

defineTool({
  name: 'get_debug_log',
  module: 'dev', kind: 'read', needsProbe: false,
  title: 'Debug / script log',
  description: 'Captured debug messages (server outputDebugString / script errors, probe-client debug messages, bridge events and failed API calls) from a ring buffer. Filter by level (error|warning|info|custom), source (server|client|bridge|api|registry), search text; pass since = lastSeq from the previous call to get only new entries. Use after spawning / calling resources to catch script errors. Read-only.',
  input: { since: z.number().int().optional(), level: z.string().optional(), source: z.string().optional(), search: z.string().optional(), limit: z.number().int().optional() },
  returns: ['entries[] {seq, time, level, source, message, file, line}', 'lastSeq'],
  related: ['execute_lua', 'manage_resources'],
  async handler(a, ctx) { return ctx.call('debug', 'log', a); },
});

defineTool({
  name: 'execute_lua',
  module: 'dev', kind: 'mutate', needsProbe: 'partial',
  title: 'Run Lua (server / probe client)',
  description: 'Runs a Lua chunk on the MTA server (side server) or the probe client (side client) inside the bridge resource and returns the values (elements become refs) and print() output. Expressions are returned directly ("getPlayerCount()"). Server helpers: ref("tmp_vehicle_001") -> element, refOf(element) -> id. Dev-only power tool (disable with the allowExec setting); prefer dedicated tools when one exists.',
  input: { code: z.string(), side: z.enum(['server', 'client']).optional(), timeout: z.number().int().optional() },
  returns: ['success', 'results[]', 'printed[]', 'error'],
  sideEffects: 'Arbitrary: whatever the code does.',
  related: ['call_export', 'get_debug_log'],
  async handler(a, ctx) { return ctx.call('debug', 'exec', a); },
});

defineTool({
  name: 'call_export',
  module: 'dev', kind: 'mutate', needsProbe: false,
  title: 'Call another resource\'s export',
  description: 'Calls an exported server function of any running resource (e.g. medsys getMedicalState, med_erm functions) with JSON args; {"$ref": "<entity id>"} in args becomes the element. Returns the values (elements as refs). May mutate depending on the function.',
  input: { resource: z.string(), fn: z.string(), args: z.array(z.any()).optional() },
  returns: ['results[]'],
  sideEffects: 'Depends on the called function.',
  related: ['manage_resources', 'execute_lua'],
  async handler(a, ctx) { return ctx.call('debug', 'callExport', a); },
});

defineTool({
  name: 'manage_resources',
  module: 'dev', kind: 'mutate', needsProbe: false,
  title: 'Resources: list / info / start / stop / restart',
  description: 'list (with filter) and info (state, failure reason, exports, version) are read-only; start / stop / restart change the server and need ACL rights for claude-mcp (see docs/troubleshooting.md). The bridge cannot restart itself through this tool.',
  input: { action: z.enum(['list', 'info', 'start', 'stop', 'restart']), name: z.string().optional(), filter: z.string().optional() },
  returns: ['resources[] | info | new state'],
  sideEffects: 'start/stop/restart affect the running server.',
  related: ['get_debug_log'],
  async handler(a, ctx) { return ctx.call('debug', 'resources', a); },
});

defineTool({
  name: 'element_data',
  module: 'dev', kind: 'mutate', needsProbe: false,
  title: 'Element data get / set',
  description: 'Reads all element data of an entity / element ref, one key, or sets key = value (synced unless sync false). Useful to test scripts that react to element data.',
  input: { id: z.string(), key: z.string().optional(), value: z.any().optional(), sync: z.boolean().optional() },
  returns: ['data | value'],
  sideEffects: 'set changes element data.',
  related: ['inspect_entity'],
  async handler(a, ctx) { return ctx.call('debug', 'elementData', a); },
});
