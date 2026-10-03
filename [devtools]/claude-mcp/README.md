# MTA World MCP (claude-mcp)

A general-purpose development and world-interaction framework that lets Claude
(or any MCP client) **observe, query, create, place, validate, screenshot and
export** things in a live Multi Theft Auto: San Andreas world.

```
Claude ──MCP (stdio)──> Node.js MCP server (mcp-server/) ──HTTP/JSON──> claude-mcp bridge resource ──> live GTA:SA world
                              │  road graph (assets/vehiclenodes.lua)        │  server: elements, workspaces, jobs
                              │  capability map, templates                    └─ probe client: raycasts, ground, bounds, screenshots
```

The live world is the source of truth: instead of remembering coordinates, model
ids or rotation conventions, Claude inspects the world through tools, creates
entities with **semantic placement** (on the ground, in a road lane, next to
another entity...), checks the result with **structured validation** and **real
screenshots**, iterates, and exports verified values.

The **medical module** (patients, injuries, medsys states, EMS access checks,
med_scenemanager export, scene templates) is one application built on top of the
generic modules; the core does not assume medical scenes.

## Contents of this folder

| path | what |
|---|---|
| `meta.xml`, `shared/`, `server/`, `client/` | the MTA bridge resource **claude-mcp** |
| `mcp-server/` | the Node.js MCP server (`npm start`), CLI (`node src/cli.js`) and tests |
| `assets/vehiclenodes.lua` | road node network (same data as v_radar's GPS) |
| `docs/` | documentation — start with [docs/installation.md](docs/installation.md) |
| `exports/`, `screenshots/` | export files / saved screenshots (git-ignored) |

## Quick start

1. MTA server console: `refresh`, `start claude-mcp` (v_main's loader starts it automatically on the next server start).
2. Join the server with a game client (the **probe**; enable *Settings → Advanced → Allow screen upload* for screenshots).
3. `cd mcp-server && npm install`
4. Register the MCP server, e.g. Claude Code:
   ```bash
   claude mcp add mta-world -- node "C:/Dev/MTASA/server/mods/deathmatch/resources/[devtools]/claude-mcp/mcp-server/src/index.js"
   ```
5. Ask Claude to call `get_capability_map` and `get_current_location_context`.

Check without an MCP client: `node src/cli.js status` (in `mcp-server/`).

## Documentation

- [Installation & MCP setup](docs/installation.md)
- [Architecture](docs/architecture.md)
- [Concepts: capability map, world map, roads, models, entities, workspaces, validation, screenshots](docs/concepts.md)
- [MCP tool reference](docs/tools.md) (generated)
- [HTTP API of the bridge](docs/http-api.md)
- [Medical module](docs/medical.md)
- [Troubleshooting](docs/troubleshooting.md)

## Security note

There is no authentication by design (development tool). The bridge only accepts
HTTP calls from `127.0.0.1` / `::1` unless the `allowRemote` setting is enabled,
and `execute_lua` can be switched off with `allowExec = false`. Do not run it on a
public production server with `allowRemote` on.
