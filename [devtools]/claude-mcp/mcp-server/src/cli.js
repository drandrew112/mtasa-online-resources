#!/usr/bin/env node
// Command-line access to the same tools, without an MCP client:
//   node src/cli.js <tool_name> ['{"json":"args"}']
//   node src/cli.js status            (shortcut for get_status)
//   node src/cli.js list              (tool names)
// Images are written to the screenshot directory and replaced by their path.
import { createContext } from './server.js';
import { TOOLS, wrap } from './tools/registry.js';

const [name = 'list', json = '{}'] = process.argv.slice(2);
const ctx = await createContext();
if (name === 'list') {
  for (const t of TOOLS) console.log(`${t.module.padEnd(10)} ${t.kind.padEnd(7)} ${t.name}`);
  process.exit(0);
}
const toolName = name === 'status' ? 'get_status' : name;
const def = TOOLS.find((t) => t.name === toolName);
if (!def) {
  console.error(`Unknown tool ${toolName}; run "node src/cli.js list".`);
  process.exit(2);
}
const res = await wrap(def, ctx)(JSON.parse(json));
for (const c of res.content) {
  if (c.type === 'text') {
    try { console.log(JSON.stringify(JSON.parse(c.text), null, 2)); } catch { console.log(c.text); }
  } else if (c.type === 'image') {
    console.log(`[image ${c.mimeType}, ${Math.round(c.data.length * 0.75 / 1024)} KB]`);
  }
}
await ctx.bridge.close();
process.exitCode = res.isError ? 1 : 0;
setTimeout(() => process.exit(), 20).unref();
