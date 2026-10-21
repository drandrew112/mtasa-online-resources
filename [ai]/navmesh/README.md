# navmesh

Navigation data of San Andreas for scripts that move vehicles and peds: a lane-level road network, the ped
path graph (sidewalks, paths, crossings, ped lights), an open-terrain walk grid built from the map collision,
and the boat paths. Other resources ask for routes and road / ground facts through server exports; nothing
drives anything here. Users: ai_land_traffic, ai_peds (sidewalk walkers, flee / combat routes). ai_land_traffic (its lane network is a copy of roads.nav with the same ids: rerun its
`tools/build_runtime.py` after `build_roads.py`), v_radar (GPS waypoint + objective routes through `requestRoute("gps")`, rerouted from the current position and heading when the player leaves the route).

## Modules

| file | what |
|---|---|
| `server/roads.lua` | `roads.nav`: nodes, links (carriageways, class), lanes, lane connections (turn, signal, curve speed, Bezier), signal groups. Lane A* with vehicle profiles. |
| `server/peds.lua` | `peds.nav`: GTA ped nodes + edges (sidewalk / path / crossing / crossing with ped light). Graph A*, random walks. |
| `server/walk.lua` | `walk.nav`: 1 m walk grid, up to 4 floor levels per cell, read per 32x32 m tile (zlib, LRU cache). Grid A* with role costs, path smoothing. |
| `server/boats.lua` | `boats.nav`: GTA boat paths. |
| `server/router.lua` | Route assembly per kind (vehicle / ped / boat), async jobs (time-sliced coroutines). |
| `server/main.lua` | Loading + exports. |
| `server/debug.lua`, `client/debug.lua` | `/navmesh` debug view. |
| `shared/config.lua` | Speeds, vehicle profiles, ped roles, limits. |

## Data (tools/, rerun after changes)

```
python tools/build_roads.py   # GTA data/Paths/NODES*.DAT + data/source/surface_scan.json -> roads.nav, boats.nav
python tools/build_peds.py    # GTA ped nodes + roads.nav -> peds.nav
node tools/walkgrid.js        # GTA collision (gta3.img COL, IPL, water.dat) + roads.nav + peds.nav -> walk.nav (~45 s)
node tools/render_walk.js x0 y0 x1 y1 out.png   # top-down check of the walk grid
```

Default GTA folder `C:/Games/GTA San Andreas` (first argument to change). Reports in `data/build/*_report.json`.
`walkgrid.js --area x0,y0,x1,y1` builds only a box into `walk_area.nav` (quick tests).

Sources and what came from where:
- **Roads**: GTA `NODES*.DAT` car nodes with each link's own navi record (lane counts, median, light). The
  lane geometry, junction curves, lane mapping and signal groups are the ai_land_traffic builder, taken over.
  The surface scan (claude-mcp probe, 2026-10-11) marks unpaved links.
- **One-way fixes** (`roads_report.json` `mixedChainsFixed`, `rampsForcedOneway`): GTA has chains between two
  junctions that are one-way for most links but contain a few two-way links. The extra opposite lane starts
  from nowhere and sent ai_land_traffic cars the wrong way up ramps (Angel Pine: ramp from the highway junction
  at -2100,-2680, 15 of 17 links one-way; east of it a 3.4 km chain with 1 two-way link). Such chains become
  one-way in the direction of their one-way links (>= 75 % of the length). A two-way chain joining a dual
  carriageway at a ramp angle is forced one-way too. Forced links are drawn with a magenta line in `/navmesh`.
  To verify: LV north interchange (708, 2580) was forced from 10 one-way of 41 links.
- **Peds**: GTA ped nodes (37650 nodes, 40341 edges, crossing + ped light flags per link). The npchlc ped
  network in `source/` is a resampled subset of the same data, so it is not used.
- **Walk grid**: every placed map model's collision (faces, boxes, spheres; interior 0, no LODs) rasterised
  like Recast: walkable slope 50 deg, 1.75 m clearance, 0.55 m step, water from `water.dat`, islands < 24 cells
  dropped. Cell flags: surface class from the COL material, road lane, ped crossing, GTA ped path, edge
  (wall / drop next to it), steep. Vanilla map only: removed world models / custom objects are not in it.
- `source/` = the old npchlc traffic resources (reference only, not loaded).

### File formats

`*.nav` text formats are described in their header lines. `walk.nav` (binary, v2): header 24 bytes
(`NAVW`, u16 version, u16 tile cells, f32 cell size, i32 origin x, i32 origin y, u16 tiles x, u16 tiles y),
index of `tilesX * tilesY` (u32 offset, u32 length), tile blob = zlib(u8 layers, z low bytes, z high bytes,
flags) with z in decimetres, delta-coded per layer (first / after empty = absolute, empty = -32768). The server
needs `decodeString("zlib")` (MTA 1.6.1 r23219+).

## Exports (server)

Routes (result tables; `false, reason` when there is none):
- `findVehicleRoute(x1,y1,z1, x2,y2,z2, opts)` - opts `profile` (`car` `truck` `bike` `bus` `emergency`
  `offroad` `gps`), `heading` / `destHeading` (start / end facing, rotZ), `radius` (both ends, 40) or `startRadius` /
  `goalRadius`, `startFallback` / `goalFallback` (wider radius without height filter when no lane is in the normal one), `simplify` (metres: Douglas-Peucker on
  `points`, for map drawing), `gpsNodes`, `maxNodes`; `z1` / `z2` may be `false` (no height filter, e.g. a map click);
  `startLane` / `startU`, `goalLane` / `goalU` (exact lane ids and 0..1 positions instead of the nearest lanes; a goal
  behind the start on the start lane is reached round a loop, `loop = true`), `lanesOnly` (only `lanes`,
  `connections`, `startU`, `goalU`, `cost`: no geometry, cheap across resources).
  Result: `points` {{x,y,z}...}, `lanes`, `connections` (false = lane change), `instructions`
  ({type = left|right|uturn|exit|merge|arrive, distance, x, y, z, node, gps}), `length`, `time`.
- `findGpsRoute(...)` - `gps` profile + `gpsNodes` (GTA path node ids, area*65536+index).
- `findPedRoute(x1,y1,z1, x2,y2,z2, opts)` - opts `role` (`civilian` `emergency` `police` `hiker` `free`),
  `gridOnly`, `graphOnly`. Result: `points`, `pointKinds` (walk / sidewalk / path / crossing / crossing_light),
  `crossings` ({index, light, group, phase, x1..z2}: wait for `isCrossingOpen(phase)` before `index`),
  `method` (grid / graph), `length`. Up to 140 m straight: grid only; farther: grid connector -> ped graph ->
  grid connector; a graph detour > 2.5x is retried on the grid; no ped graph nearby: grid up to 700 m.
- `findBoatRoute(x1,y1,z1, x2,y2,z2)`.
- `requestRoute(kind, x1,y1,z1, x2,y2,z2, opts)` - async (`vehicle` `ped` `boat` `gps`), returns an id; the
  answer is `onNavmeshRouteReady(id, result|false, reason)` on the calling resource's root element. Long ped
  routes over open terrain get their full search budget only here.

Queries:
- `getNearestLane(x,y,z, opts)` / `getNearestLanes` (opts radius, heading, headingTolerance, maxZ, skipTrap,
  count), `getLaneInfo(id)` (class, one-way, neighbours, speed, next connections...), `getLanePoint(id, u)`,
  `getConnectionPoints(id)`, `getSignalGroup(id)`.
- `getWalkableGround(x,y,z, maxDz)` -> z, {surface, road, crossing, pedPath, edge, steep, layer};
  `isWalkable(x,y,z)`; `getNearestPedPath(x,y,z, radius)`; `getPedRandomWalk(x,y,z, length, role, opts)` (opts `node`,
  `prev`, `kinds`: start node, node not to step back to, allowed edge kinds; result `points`, `nodes`, `widths`, `crossings`);
  `getPedEdgesNear(x,y,z, radius, kinds, maxDz, max)` (ped edges around a point: spawning walkers, how built-up an area is);
  `isCrossingOpen(phase)` (ai_land_traffic signal cycle when it runs, else GTA's lights);
  `getNavmeshStats()` (`roads.signature` = md5 of roads.nav, for copies of the lane ids).

Measured offline (lupa, Lua 5.1): load ~1.7 s; car route across LS 1.1 km ~30 ms, SF -> LV 5.9 km ~90 ms;
ped grid route 125-225 m 35-170 ms; walk tile decode on demand.

## /navmesh (admin_level >= 5)

`/navmesh` toggles the view around you (refreshes every 60 m): lanes coloured by class with direction
arrows (red highway, orange ramp, white road, brown unpaved, blue emergency-only, purple trap, magenta line =
forced one-way), turn curves (green / cyan = signal phase), signal groups, ped edges (cyan sidewalk, green
path, yellow crossing, orange crossing with light), boat paths, walk cells within 28 m (grey road, pink ped
path, yellow crossing, dark = edge). `/navmesh roads|peds|walk|boats|signals` toggles a layer, `/navmesh info`
tells what is under you, `/navmesh from` + `/navmesh to [car|truck|bike|bus|emergency|offroad|gps|civilian|police|hiker|free|boat]`
draws a test route.
