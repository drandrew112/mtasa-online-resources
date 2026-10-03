# Troubleshooting

Start with `get_health` (or `node src/cli.js get_health`) and `get_debug_log`.

| symptom | cause / fix |
|---|---|
| `MTA_UNREACHABLE` | MTA server not running, or wrong `MTA_HOST` / `MTA_HTTP_PORT` |
| `BRIDGE_NOT_RUNNING` (HTTP 404) | `refresh` + `start claude-mcp` in the server console |
| `HTTP_AUTH_REQUIRED` (401) | the Default ACL lacks `general.http`; add it or set `MTA_HTTP_USER` / `MTA_HTTP_PASS` |
| HTTP 429 / sudden connection refusals | HTTP flood protection: add `127.0.0.1` to `<http_dos_exclude>` |
| `NO_PROBE_CLIENT` | join the server with a game client; wait for `probe client ready` in the server log |
| `PROBE_TIMEOUT` | client loading, frozen or alt-tabbed for long; retry; `select_probe` another client |
| `NO_GROUND`, `noCollision`, `collisionLoaded: false` | the area is not streamed in; the bridge focuses the camera for far points, otherwise `teleport_probe` there |
| `MODEL_NOT_LOADED` | the model did not stream in within 8 s (first use of a model on a slow client); retry |
| `SCREENSHOT_DISABLED` | MTA client: Settings → Advanced → Allow screen upload |
| `SCREENSHOT_MINIMIZED` | restore the game window; with several clients pick a visible one with `select_probe` (`get_player_state all=true` shows `windowActive`) |
| `ACL_DENIED` on `execute_lua` | server-side `loadstring` needs an ACL granting `function.loadstring` (e.g. add `resource.claude-mcp` to the `runcode` group), then `reloadacl` |
| `ACL_DENIED` on `manage_resources` | add `resource.claude-mcp` to the Admin group (restart / start / stop resources), `reloadacl` |
| job results slow (~0.4 s extra) | `fetchRemote` is denied for the resource (Default ACL), so results are polled; the Admin group (which includes the RPC ACL) allows the push |
| `BRIDGE_RESTARTED` notice | the resource restarted: workspaces and ids are gone; rebuild or `import_workspace` an export |
| `DEPENDENCY_OUTDATED` (medical) | restart `med_scenemanager` so `getCatalog` / `saveSceneData` exist |
| many "Bad usage @ engineGetModelNameFromID" lines in the client debug view | the one-time object-name catalog load probes every model id; harmless |

## Useful in-game commands

`/mcp` status · `/mcp probe` become the probe · `/mcp overlay` toggle the
overlay · `/mcp clear` destroy all workspace entities.

## Tests

```bash
cd mcp-server
npm test                    # road graph (offline)
npm run smoke               # MCP protocol round trip over stdio (offline parts)
node test/live.smoke.mjs    # every tool against the live server (needs bridge + probe)
```
