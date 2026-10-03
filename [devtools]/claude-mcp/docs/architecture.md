# Architecture

```
Claude / MCP client
   │  MCP (stdio): 67 tools, resources mta://capability-map, mta://road-network, workflow_* prompts
   ▼
Node.js MCP server  (mcp-server/src)
   │  tools/*.js        tool definitions (+ capability metadata) — the single source of truth
   │  capabilities.js   capability map, modules, workflows, conventions
   │  roads/graph.js    road graph from assets/vehiclenodes.lua (id map, adjacency, 64 m grid, A*)
   │  roads/placement.js road-aware placement → bridge placement specs
   │  bridge.js         HTTP client, job wait (push listener + poll fallback), restart detection
   ▼  HTTP/JSON  POST /claude-mcp/call/<category>  [action, params, {callback}]
claude-mcp bridge resource (MTA server side)
   │  router.lua        one exported http function per category, localhost check, envelopes
   │  async.lua         every request is a coroutine "job"; waits yield; results pushed / polled
   │  registry.lua      workspaces + entities (semantic id ↔ element), loss detection
   │  probe.lua         probe client selection, client RPC, camera focus for far queries
   │  api/*.lua         status, player/camera, world, roads, models, entities, placement,
   │                    workspace, validation, screenshot, scene, medical, debug
   ▼  triggerClientEvent / triggerLatentServerEvent
probe client (client/*.lua on one player's game)
      raycasts (processLineOfSight with world-model info), ground, water, model measurement,
      area scans, road cross-sections, placement math, validation geometry, overlay, screenshots
```

## Why a probe client?

The MTA server has no GTA collision or model data. Everything geometric is
computed by a connected game client. The bridge picks one ready player
(`probePlayer` setting > `/mcp probe` / `select_probe` > first ready). Without a
probe, element / road / model-name / registry features keep working and
geometry tools return `NO_PROBE_CLIENT`.

GTA streams collision around the camera, so for points more than ~280 m away
the bridge moves the probe camera above the target for the duration of the job
(`Probe.focus`, ~1.5 s settle) and restores it afterwards. For heavy work far
away, `teleport_probe` is faster.

## Request lifecycle

1. Node posts `[action, params, {callback}]` to `/claude-mcp/call/<category>`.
2. The router validates the caller (localhost unless `allowRemote`) and starts a
   job coroutine.
3. If the handler never waits, the HTTP response carries `{ok, result}`.
4. If it waits (probe reply, timer, screenshot), the response is
   `{ok, pending, job}`; the result is pushed to the Node callback listener with
   `fetchRemote` (needs ACL) and kept 2 minutes for `jobs("poll")`.
5. Structured errors are yielded out of the job (no MTA error spam) and returned
   as `{ok:false, error:{code, message, retryable, suggestion, ...}}`.
6. Every envelope carries the bridge `instanceId`; Node reports a
   `BRIDGE_RESTARTED` notice when it changes (all ids are gone then).

MTA JSON strings are limited to 65 535 characters, so screenshots travel as
`imageChunks` and are joined in Node.

## State and synchronisation

- All world state lives in the bridge (workspaces, entities). The Node server is
  stateless apart from caches (road graph, nothing per-entity), so it can restart
  freely; `list_workspaces` recovers the picture.
- Entities whose element disappears are kept with `status: "missing"` and
  reported by validation / health.
- Elements the bridge did not create get ephemeral `el_<type>_<n>` refs.
- A bridge restart destroys its elements (they belong to the resource) and
  invalidates every id; Node detects it via the instance id.

## Performance notes

- Road graph: parsed once with a regex pass (~150 ms, 30 586 nodes, 31 474
  segments), indexed in a 64 m grid; nearest-node / segment queries are
  sub-millisecond, A* across the city a few ms.
- Area scans run on the client in chunks of ~500 rays per frame; ray budgets
  scale with `detail` and radius (max ~9 000 samples).
- Model measurements and the object-name catalog are cached on the client and
  the server; `get_model_info refresh=true` re-measures.
