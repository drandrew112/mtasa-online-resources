// Live walk-floor scan of a box with the claude-mcp probe client (see README "Probe patches").
//   node tools/probe_walk/scan.mjs X0 Y0 X1 Y1 data/build/probe_<name>_raw.json [rows per call, 4]
// The probe (select_probe) must stand near the box (collision streams ~300 m). Resumable: rows already in the
// output file are skipped. Door models lose their collision on the probe during the scan (doors = passable).
import fs from 'fs';
const MCP = new URL('../../../../[devtools]/claude-mcp/mcp-server/src/', import.meta.url).href;
const { createContext } = await import(MCP + 'server.js');
const { TOOLS, wrap } = await import(MCP + 'tools/registry.js');
const ctx = await createContext();
const SP = new URL('.', import.meta.url);
const code = fs.readFileSync(new URL('scan.lua', SP), 'utf8');
const [X0, Y0, X1, Y1] = process.argv.slice(2, 6).map(Number);
const OUT = process.argv[6];
const ROWS = Number(process.argv[7] || 4);
const exec = TOOLS.find((t) => t.name === 'execute_lua');
async function lua(pre, timeout = 60000) {
  const res = await wrap(exec, ctx)({ side: 'client', code: pre + '\n' + code, timeout });
  const j = JSON.parse(res.content.find((c) => c.type === 'text').text);
  if (res.isError || !j.success) throw new Error(JSON.stringify(j).slice(0, 600));
  return j.results;
}
const result = fs.existsSync(OUT) ? JSON.parse(fs.readFileSync(OUT)) : { box: [X0, Y0, X1, Y1], floors: [], blocks: [], rowsDone: [] };
try {
  console.log('doors off', await lua('DOORS = true'));
  for (let y = Y0; y < Y1; y += ROWS) {
    if (result.rowsDone.includes(y)) continue;
    const ny = Math.min(ROWS, Y1 - y);
    const t = Date.now();
    const r = await lua(`X0, Y0, NX, NY, ZTOP, ZBOT = ${X0}, ${y}, ${X1 - X0}, ${ny}, 80, 0`);
    const blocks = r[0] ? r[0].split(' ') : [];
    for (const b of blocks) { const [i, rr, z, dir, nz, t] = b.split(':').map(Number); result.blocks.push([X0 + i, y + rr, z, dir, nz, t]); }
    let n = 0;
    for (let k = 1; k < r.length; k++) {
      if (!r[k]) continue;
      for (const f of r[k].split(' ')) { const [i, z, mat, nz] = f.split(':').map(Number); result.floors.push([X0 + i, y + k - 1, z, mat, nz]); n++; }
    }
    result.rowsDone.push(y);
    fs.writeFileSync(OUT, JSON.stringify(result));
    console.log(`y ${y} floors ${n} blocks ${blocks.length} ${Date.now() - t} ms`);
  }
} finally {
  console.log('doors on', await lua('DOORS = false'));
  await ctx.bridge.close();
  setTimeout(() => process.exit(), 50).unref();
}
