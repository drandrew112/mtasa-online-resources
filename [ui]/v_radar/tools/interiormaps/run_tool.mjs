import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
const base = 'C:/Dev/MTASA/server/mods/deathmatch/resources/[devtools]/claude-mcp/mcp-server/src/';
const { createContext } = await import(pathToFileURL(base + 'server.js').href);
const { TOOLS, wrap } = await import(pathToFileURL(base + 'tools/registry.js').href);
const { tool, args } = JSON.parse(readFileSync(process.argv[2], 'utf8'));
const ctx = await createContext();
const def = TOOLS.find((t) => t.name === tool);
const res = await wrap(def, ctx)(args);
const texts = res.content.filter((c) => c.type === 'text').map((c) => c.text);
let out;
try { out = JSON.parse(texts[0]); } catch { out = { raw: texts.join('\n') }; }
process.stdout.write(JSON.stringify(out) + '\n');
await ctx.bridge.close();
setTimeout(() => process.exit(0), 20).unref();
