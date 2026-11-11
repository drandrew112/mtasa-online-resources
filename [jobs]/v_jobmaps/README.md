# v_jobmaps

Maps for jobs (races, DM...) with their own models. The files (dff / col / txd) are downloaded by every
player (meta.xml) but a map is only put into the game for the players a job loads it for, so its
models never replace anything in the normal world.

## Map folder

```
maps/<name>/<name>.map      objects, MTA map editor format. model="hr01" = custom model of map.json,
                            model="1234" = GTA model; removeWorldObject works too
maps/<name>/map.json        title, "txds" (archives, shared by many dffs), "models" (dff, col, txd key,
                            distance, doublesided, alpha)
maps/<name>/models|col|textures/
maps/index.json             maps loaded by the server
```

New pack (JStreamer zip with gta3.JSD / gta3.JSP, e.g. `1580665324_HG.zip`):

```
python -I tools/build.py import <zip> <name> --title "Title"   # converts + rewrites meta.xml / index.json
python -I tools/build.py check                                   # files, model names, textures vs txd
```

`import` checks that every texture of every dff exists in the txd it is given (Hungaroring: one txd
`hr01.txd` for all 21 dffs). `meta` alone regenerates meta.xml + index.json. The original zip
in `maps/hungaroring/` is not used by the resource and can be deleted.

## Exports (server)

```lua
exports.v_jobmaps:loadJobMap("hungaroring", players, { dimension = 5, interior = 0, offset = {0,0,0} })
exports.v_jobmaps:unloadJobMap("hungaroring", players)
exports.v_jobmaps:unloadAllJobMaps(players)
exports.v_jobmaps:getJobMaps()            -- { name = { title, center, size, models, objects } }
exports.v_jobmaps:getJobMapInfo(name)
exports.v_jobmaps:isJobMapLoaded(name, player) / isJobMapReady(name, player)
exports.v_jobmaps:getPlayerJobMaps(player) / getJobMapLoadedPlayers(name)
```

`players` is one player or a table. Events (source = player): `onJobMapReady(name)` (the client built
the models + objects), `onJobMapFailed(name, reason)`, `onJobMapUnloaded(name)`. Client: events
`onClientJobMapProgress(name, step, steps)`, `onClientJobMapReady(name)`, exports `getLoadedJobMaps()`,
`isJobMapReady(name)`.

Objects are client side (custom model ids exist only on clients), created in `options.dimension`.
Models take new object ids via `engineRequestModel`, so no existing GTA model is replaced.
Players quitting are cleaned up on the server; the client frees everything on unload / resource stop.

## Test command

`/jobmap` lists the maps, `/jobmap <name> [tp]` toggles one for yourself (`tp` = teleport above its
centre when built), `/jobmap off` unloads all. Admin level `JOBMAPS.ADMIN_LEVEL` (5), output in the F8 console.

## Minimap image (v_radar)

A job map can have a track-line image on the v_radar minimap. `python -I tools/radar_image.py <name>` draws the
road triangles of the map (`ROAD_TEXTURES` in the script) top-down into `v_radar/interiors/jobmap_<name>.png`
and writes its entry (position, size, zone = the map's volume incl. height) into `v_radar/interiors/jobmaps.json`
(`zoom` there is hand-editable and kept). The client shows it only while the map is built for the local player
(`exports.v_radar:setJobMapImage(name, true, loadOptions)` after the objects exist, `false` on unload / failure;
re-applied when v_radar restarts) and v_radar draws it only inside the zone (with the load `offset` /
`dimension` applied), so a stale image can not show anywhere else. Maps without an entry are skipped silently.
