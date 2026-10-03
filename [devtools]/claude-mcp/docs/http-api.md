# Bridge HTTP API

All calls: `POST http://<host>:<httpport>/claude-mcp/call/<category>` with a JSON
array body `[action, params, meta]`. The response is a JSON array with one
envelope:

```json
[{ "ok": true, "result": { ... }, "job": "j12", "ms": 3, "instanceId": "6ac0693ed4b3" }]
[{ "ok": true, "pending": true, "job": "j13", "instanceId": "..." }]
[{ "ok": false, "error": { "code": "ENTITY_NOT_FOUND", "message": "...", "retryable": false, "suggestion": "..." } }]
```

- `meta.callback`: URL the bridge POSTs `{ job, envelope }` to when a pending
  job finishes (needs `function.fetchRemote` for the resource).
- `jobs`: `["poll", { "ids": ["j13"] }]` → `{ result: { j13: envelope } }`.
- Only localhost may call unless `allowRemote = true`.
- Other resources can use `exports["claude-mcp"]:callBridge(category, action, params)`.
- MTA JSON strings are limited to 65 535 chars; screenshots come as `imageChunks`.

The HTTP function for the `debug` category is called `dev` (a Lua global named
`debug` would shadow the debug library). `status` → `actions` lists everything
the running bridge implements.

| category | actions |
|---|---|
| status | `get`, `health`, `actions`, `ping` |
| player | `get`, `list`, `teleport`, `setProbe` |
| camera | `get`, `set`, `reset` |
| world | `elements`, `raycast`, `ground`, `scan`, `inspect`, `context`, `zones`, `zoneAt`, `lineOfSight`, `safeSpot`, `environment` |
| roads | `crossSection`, `probeNodes` |
| models | `vehicles`, `peds`, `objects`, `search`, `info`, `measure` |
| entities | `spawn`, `delete`, `transform`, `modify`, `get`, `inspect`, `adopt`, `relation` |
| placement | `place`, `compute`, `orient` |
| workspace | `create`, `list`, `entities`, `inspect`, `clear`, `clearAll`, `update` |
| scene | `export`, `import` |
| validation | `run`, `checks` |
| screenshot | `capture`, `overlay` |
| medical | `catalog`, `createScene`, `addPatient`, `setPatient`, `addVehicle`, `simulate`, `patientState`, `export`, `load`, `live`, `validate` |
| dev (debug) | `log`, `exec`, `resources`, `callExport`, `elementData` |
| jobs | `poll` |

Road-graph features (nodes, segments, paths) live in the MCP server, not in the
bridge; the bridge's `roads` category only measures live road geometry. The
bridge understands placement modes `ground`, `road` (with an explicit `base` +
`heading`), `near`, `relative`, `raw`; the MCP server converts node / segment
based specs into these.

## Example

```bash
curl -s -X POST http://127.0.0.1:22005/claude-mcp/call/world -d '["context", {"detail": "low"}, {}]'
```

## Error codes (selection)

| code | meaning |
|---|---|
| `NO_PROBE_CLIENT` / `PROBE_TIMEOUT` / `PROBE_DISCONNECTED` | geometry needs a connected, responsive game client |
| `ENTITY_NOT_FOUND` / `ENTITY_MISSING` / `ENTITY_EXISTS` | registry problems |
| `WORKSPACE_NOT_FOUND` / `WORKSPACE_EXISTS` / `NOT_A_MEDICAL_SCENE` | workspace problems |
| `MODEL_NOT_FOUND` / `MODEL_NOT_LOADED` | invalid model / model did not stream in |
| `NO_GROUND` | no collision under a placement point (not streamed in / void) |
| `SCREENSHOT_DISABLED` / `SCREENSHOT_MINIMIZED` / `SCREENSHOT_TIMEOUT` | client screenshot problems |
| `DEPENDENCY_NOT_RUNNING` / `DEPENDENCY_OUTDATED` | med_scenemanager / medsys missing or old |
| `ACL_DENIED` | the resource lacks an ACL right (see installation) |
| `INVALID_PARAMS` / `UNKNOWN_ACTION` | malformed request |
| `JOB_TIMEOUT` / `JOB_NOT_FOUND` | job ran too long / expired or bridge restarted |
| `REMOTE_NOT_ALLOWED` | non-localhost caller |
| `INTERNAL_ERROR` | a bridge bug (check `get_debug_log`) |

The MCP server adds `MTA_UNREACHABLE`, `BRIDGE_NOT_RUNNING`,
`HTTP_AUTH_REQUIRED`, `BRIDGE_TIMEOUT`, `BRIDGE_RESTARTED` (notice),
`ROAD_NODE_NOT_FOUND`, `NOT_A_SEGMENT`, `NO_ROAD_NEARBY`, `NO_INTERSECTION`.
