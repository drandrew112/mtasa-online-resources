// Starts the MCP server over stdio and calls a few tools (works without MTA running).
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
const client = new Client({ name: 'smoke', version: '1' });
await client.connect(new StdioClientTransport({ command: process.execPath, args: ['src/index.js'], env: { ...process.env, MCP_CALLBACK_PORT: '0' } }));
const { tools } = await client.listTools();
console.log('tools:', tools.length);
const r = await client.callTool({ name: 'find_road_path', arguments: { from: 1442188, to: { x: 2495, y: -1670, z: 13 } } });
const j = JSON.parse(r.content[0].text);
console.log('path found:', j.found, 'length', j.length, 'steps', j.steps?.length);
const cap = await client.callTool({ name: 'get_capability_map', arguments: { tool: 'spawn_entity' } });
console.log('capability tool schema keys:', Object.keys(JSON.parse(cap.content[0].text).tool.inputSchema.properties).join(','));
const st = await client.callTool({ name: 'get_status', arguments: {} });
console.log('status bridge:', JSON.stringify(JSON.parse(st.content[0].text).bridge).slice(0, 200));
const prompts = await client.listPrompts();
console.log('prompts:', prompts.prompts.length);
await client.close();
