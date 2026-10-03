# Installation & MCP setup

## 1. MTA bridge resource

The folder `[devtools]/claude-mcp` **is** the resource (its `meta.xml` sits at the
top; MTA ignores the Node.js files because they are not listed in it).

1. In the server console: `refresh`, then `start claude-mcp`.
   With this repository's `v_main` loader the resource starts automatically on the
   next server start like every other resource.
2. HTTP must be enabled in `mtaserver.conf` (`<httpserver>1</httpserver>`, `<httpport>22005</httpport>`).
3. Guests need HTTP access: the `Default` ACL must contain
   `<right name="general.http" access="true"></right>` (this server already has it).
4. Recommended: exclude localhost from the HTTP flood protection in `mtaserver.conf`:
   ```xml
   <http_dos_exclude>127.0.0.1</http_dos_exclude>
   ```
   (the MCP server polls jobs; with the default threshold of 20 a burst of tool
   calls can get 127.0.0.1 temporarily blocked).
5. Optional ACL rights (`acl.xml`, then `reloadacl`):
   - `<object name="resource.claude-mcp"></object>` in the **Admin** group:
     `manage_resources start/stop/restart` (also the bridge restarting itself)
     and `fetchRemote` (job results are pushed instead of polled).
   - the same object in the **runcode** group (or any ACL with
     `function.loadstring`): server-side `execute_lua`.
   Everything else works with the default rights.
6. Restart `med_scenemanager` once so its new exports (`getCatalog`,
   `saveSceneData`) are available to the medical module.

### Settings (`meta.xml` / `set claude-mcp.<name>`)

| setting | default | meaning |
|---|---|---|
| `allowRemote` | `false` | accept HTTP calls from other hosts than localhost |
| `allowExec` | `true` | enable `execute_lua` |
| `probePlayer` | `""` | player name to use as the probe ("" = automatic) |

### The probe client

The MTA server has no GTA collision data, so every geometry feature (raycasts,
ground, model bounds, area scans, validation geometry, screenshots) runs on one
connected game client — the **probe**. Join the server with your game client.
With several players the first ready client is used; `/mcp probe` makes you the
probe. In-game commands: `/mcp` (status), `/mcp probe`, `/mcp overlay`, `/mcp clear`.

Collision is only streamed in near the probe camera (~300 m). For far queries the
bridge moves the probe camera temporarily; when that is not enough use
`teleport_probe`.

## 2. Node.js MCP server

Requires Node.js 18.17+ (developed on 24).

```bash
cd mcp-server
npm install
npm test          # road graph unit tests (no MTA needed)
npm run smoke     # starts the MCP server over stdio and calls a few tools
node src/cli.js status
```

### Environment variables

| variable | default | |
|---|---|---|
| `MTA_HOST` | `127.0.0.1` | MTA server host |
| `MTA_HTTP_PORT` | `22005` | `<httpport>` |
| `MTA_RESOURCE` | `claude-mcp` | bridge resource name |
| `MTA_HTTP_USER` / `MTA_HTTP_PASS` | — | only if your ACL requires an MTA account for HTTP |
| `MCP_CALLBACK_PORT` | `22095` | local port where the bridge pushes job results (`0` = poll only) |
| `MCP_REQUEST_TIMEOUT` | `60000` | ms per tool call |
| `MCP_POLL_INTERVAL` | `400` | ms between job polls (fallback) |
| `VEHICLE_NODES` | `../assets/vehiclenodes.lua` | road network file |
| `MCP_SCREENSHOT_DIR` | `../screenshots` | where screenshots are also saved (`""` = off) |

## 3. Register with an MCP client

**Claude Code**

```bash
claude mcp add mta-world -- node "C:/Dev/MTASA/server/mods/deathmatch/resources/[devtools]/claude-mcp/mcp-server/src/index.js"
```

or a project `.mcp.json`:

```json
{
  "mcpServers": {
    "mta-world": {
      "command": "node",
      "args": ["C:/Dev/MTASA/server/mods/deathmatch/resources/[devtools]/claude-mcp/mcp-server/src/index.js"],
      "env": { "MTA_HTTP_PORT": "22005" }
    }
  }
}
```

**Claude Desktop**: the same `mcpServers` entry in `claude_desktop_config.json`.

The server also exposes MCP resources (`mta://capability-map`,
`mta://road-network`) and prompts (`workflow_*`) for the standard workflows.

## 4. First steps for Claude

1. `get_status` — is MTA reachable, is there a probe?
2. `get_capability_map` — every tool, workflow and convention.
3. `get_current_location_context` — where am I, what is around.
