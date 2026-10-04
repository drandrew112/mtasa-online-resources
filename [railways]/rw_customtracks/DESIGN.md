# rw_customtracks – design

A custom railway network for Sunline Rail that no longer depends on GTA:SA's built-in train
tracks (`tracks*.dat`, `getTrainPosition`, node-nearest track selection).

Why:

1. switches today work by destroying and re-creating the whole consist on the other track
   (`rw_core` `transferConsist`) – primitive and fragile;
2. we want full control over where railway vehicles are (positions, speed, physics);
3. tracks that physically exist in the map but are not registered as GTA tracks (yards,
   industrial spurs, docks) become usable.

`source/` is Lime's old "custom train tracks" script, kept as an example only. What we keep from
it: tracks are our own point lists, the train is not bound to GTA, sounds follow the speed. What we
do not keep: linear `moveObject` per point (rotation snaps at every point), element data written on
every step, one global `progress` for all trains, the broken timer, loops only, no switches, no
speed control, nobody can ride it.

## 1. Principles

1. **The network is a graph**, not four GTA tracks: segments + nodes. A switch is a node with a
   state – no more re-creating trains.
2. **The server is the single source of truth** for every train (the model `rw_auto` already uses
   for its "virtual" trains): the server simulates, clients place the vehicles every frame from
   that simulation. GTA's own train physics is not used at all.
3. **Bogie kinematics**: every car has two bogie points on the path; the car is placed at their
   midpoint and rotated along the vector between them → correct in curves and on gradients, and
   car lengths can differ per type.
4. **Data is JSON**, edited by both the in-game editor and the MCP (same format).

## 2. Data model

```
data/network/<region>.json      (ls.json, sf.json, lv.json - split for editing)

segment = {
  id = "LS_MAIN_014",
  pts = { {x,y,z}, ... },              -- sparse control points
  smooth = "catmull" | "linear",
  a = "N_UNITY_E1", b = "N_UNITY_E2",  -- node at each end
  vmax = 90,                           -- optional; otherwise derived from curvature
  tags = { "tunnel", "platform:unity:1", "bridge" },
}

node = {
  id = "N_W1",
  type = "link" | "switch" | "crossing" | "buffer",
  legs = { trunk = "seg@b", normal = "seg@a", reverse = "seg@a" },   -- switch
}
```

- **Runtime geometry**: on load every segment is resampled at ~1 m: cumulative **3D** length,
  tangent, curve radius, gradient, optional cant (roll). Server and clients compute it themselves;
  only the sparse control points travel over the network / in files.
- **Network position**: `{seg, s, dir}` replaces today's `(track, tp)`. The `Track.pointAt /
  project / nearest / polyline` API stays, backed by the graph, so the other resources change
  little.
- **Path**: a directed list of segments. Every train keeps a "trail" – the segments it currently
  occupies from front to rear (needed for the rear cars' bogies).

## 3. Motion engine

- **Server (10–20 Hz)**: `v += (tractive − resistance − m·g·gradient − brake) / m · dt`; the
  tractive effort comes from the driver's notch. The front advances `v·dt`; at a segment end the
  node decides: link → next segment, switch → leg by state, buffer → stop / accident event.
  Trailing through a switch set the wrong way is an event, never a teleport.
- **Client**: snapshot `{lead, path, s, v, a}` on change + every ~500 ms, extrapolated in between,
  every streamed-in car placed each frame (bogie model) – a generalised
  `rw_auto/client/motion.lua`.
- **Driving**: the driver's client only sends input (notch, brake, Sifa, doors); simulation stays
  on the server. Throttle / brakes become a real simulation (good for the `rw_loco` cab).
- **Physical representation** (decided by phase 0):
  - **A**: the current train models (538, 570) as **derailed + frozen puppets**; the server
    updates the element position ~1/s for streaming, clients override every frame, syncer off.
    Native seats, entering, camera and passengers keep working.
  - **B (fallback)**: object based like `source/` (own DFF), driver / passengers attached with
    `attachElements`, boarding through ui_interactobject (fits the planned coach interiors).
- **Collisions**: a frozen vehicle is a static obstacle (cars hit it). Peds / vehicles on the track
  are handled by a client-side "sweeper" box in front of the loco (applied by the element's
  syncer). Train vs train is computed on the graph (occupied span overlap).
- **Sounds**: run sound by speed (the `source/` wav files as a start), rail-joint clacks every
  ~25 m, curve squeal at small radius, brakes. GTA engine sound off.

## 4. Switches and routes

- A switch is a `switch` node with `normal` / `reverse`. Running through it is continuous: no
  `transferConsist`, no warp, element data kept.
- Locking per node: a switch on a reserved route or under a train cannot be thrown.
- Switches are **always thrown by the system** (user decision 2026-10-04): no point machines, no
  interaction objects. A train's destination (later: its service) gives the route; switches are
  reserved and thrown ahead of it and released behind it (see phase 3).
- Blades and diverging rails drawn with dx like today, but along the real graph geometry; own rail
  models later.

## 5. Recording the tracks (MCP)

1. **Import**: `tools/import_gta.js` turns `tracks.dat` / `tracks4.dat` into starting segments,
   split at the current switch locations (W1–W20) and ends; crossovers become real diagonal
   segments.
2. **Discovery**: `tools/scan_rails.js` (like `rw_crossings/tools/gen_crossings.js`) lists every
   rail model placement from the `gta3.img` IPLs → map of where rails physically exist but no
   track does (docks, yards, LV freight, SF yards...).
3. **Tracing** (MCP, probe client): new `rail_trace` tool – from a start point + heading follow the
   rail pair centre with cross-section raycasts (model name / surface material), returns control
   points, z = rail top.
4. **Editing**: rw_customtracks exports (`createSegment`, `updateSegment`, `connect`,
   `setNodeType`, `saveRegion`) through the existing `call_export`.
5. **Validation**: `rail_validate` – tangent continuity at nodes, min radius, max gradient,
   parallel track spacing, ground / building clipping by raycast, dangling ends.
6. **Visual check**: dx drawing (`/rwtrackeditor`, coloured segments) + `capture_views`
   screenshots → user approves → live.

`/rwtrackeditor` edits the same JSON in game (move / insert points, node type).

## 6. Resources and migration

`rw_customtracks` (maybe renamed `rw_network` later): graph, geometry, editor, motion engine.

| Resource | Change |
| --- | --- |
| `rw_core` | `track.lua` → graph API; `consist.lua` uses puppets + simulation; `switches.lua` node based; `transferConsist` removed; depot spawns `{seg,s,dir}` |
| `rw_loco` | notch / brake input instead of `setTrainSpeed`; displays from simulation data |
| `rw_signals` | blocks = segment ranges; direction lock stays |
| `rw_timetable` / `rw_crossings` | platform / crossing zones = segment ranges (`platform:*` tags) |
| `rw_auto` | path finding on the graph (directed Dijkstra, reversal only at marked places); `motion.lua` merges into the common engine |
| web map | polylines from the graph, switch states shown |

Phases:

0. **Prototype**: derailed + frozen train moved per frame, entering, passengers, camera,
   streaming, collisions → decides A or B.
1. Graph, geometry, API, import from GTA data, debug drawing.
2. Motion engine, bogies, driving, train-train collisions, sounds.
3. Switches + route reservation.
4. Port the `rw_*` resources – existing lines run on the same geometry, timetable unchanged.
5. New tracks per region through MCP; use the new possibilities (passing loops, freight in LV
   that the current single-track limit made impossible).

## 7. Risks

- Puppet vs driver sync: the driver's puresync may write the position back and fight the
  simulation – measured in phase 0.
- Streaming: far trains' server positions are updated rarely; a short correction on stream-in.
- Restarting `rw_core` still kills trains → switch over in one step on an empty server.
- Surface material: many LS models use DEFAULT material; if rails do too, `rail_trace` works from
  model names.

## Phase 0 results (2026-10-04)

Prototype: `proto/` (`/ctp ...`, MCP entry point export `proto(cmd, a1, a2, playerName)`), a
1240 m test oval on the LS airport apron (flat, z 12.55, no rails), BR 232 (538) + 2 coaches (570),
server sim at 10 Hz, clients place every car each frame with `setElementMatrix` from the bogie pose.
Measured with two clients (local + a laptop over the network).

| question | result |
| --- | --- |
| Does GTA snap a created train onto its track? | **No** when derailed right after `createVehicle`: it stays exactly where created, far from any GTA track. |
| Does GTA move a derailed + frozen puppet? | **No.** Per-frame drift is 0 apart from the server's own 1 Hz position refresh, which the client overrides before rendering. |
| Not frozen ("loose", velocity set)? | Rejected: physics moves the car ~0.2 m every frame (gravity, collisions) and fights the placement. |
| Snapshot error (extrapolation vs new state) | Local client avg 0.13 m / max 0.28 m at 60 km/h; laptop (network) avg 0.3–0.6 m / max ~1.2 m. Blended out over 300 ms, not visible. Needs real elapsed time in the sim + server timestamps (done). |
| Driver | `warpPedIntoVehicle` into the frozen loco works, camera follows, `removePedFromVehicle` works. The driver's puresync keeps the server position of the lead current (0.4 m behind = latency); the driver's own client sees no fight (drift 0), remote clients a small one that is overridden each frame. Input (W/S → server) feels instant enough. |
| Passengers in coaches | 570 has **only 1 passenger seat** (+ seat 0) → native seats cannot carry passengers. Riding in seat 0 / 1 works (camera follows). |
| Object puppets + `attachElements` (plan B) | Works: attached player rides smoothly (drift ~0), object streaming fine. |
| Collision with a car / ped in the way | The puppet passes through them (teleported every frame, no push) → the planned client-side sweeper is required. |
| Vehicle height | `getElementDistanceFromCentreOfMassToBaseOfModel`: 538 = 0.20, 570 = 2.60 – inconsistent model origins, so the rail-to-centre offset must be calibrated per model on real rails (phase 1). |

**Decision: hybrid of A and B.**

- Locomotives and cars are **derailed + frozen vehicle puppets** (A), syncer off, placed by every
  client each frame; the server refreshes unoccupied cars' positions ~1/s for streaming.
- The **driver** uses the native driver seat of the locomotive (cab camera, existing `rw_loco`
  cab entry points keep working).
- **Passengers** do not use vehicle seats: they are attached to the car (`attachElements`, plan B
  mechanism) at seat / standing positions, or moved into the planned coach interior.
- The sweeper (peds / vehicles in front of the train) is part of phase 2.

**Confirmed by the user (2026-10-04):** vehicles, not objects. Driving is simulated on the server
(input → server → clients), the small input delay is accepted. Passengers are attached to the car
for now and their camera targets the car.

## Phase 1 – network (graph, geometry, import, debug drawing)

Files: `shared/config.lua`, `shared/geometry.lua`, `shared/network.lua`, `server/network.lua`,
`server/validate.lua`, `client/network.lua`, `client/debugdraw.lua`, `tools/import_gta.js`,
`data/network/*.json`.

- The server reads the JSON files (`NET.FILES`) and sends the raw data to every client (latent
  event); both sides build the same geometry. Edits through the exports are broadcast the same
  way and written back to the file the segment came from.
- Node types: `link` (2 ends), `switch` (`trunk` / `normal` / `reverse`, `group` = the switch that
  throws all its nodes together, `spring` = trailable default position), `buffer` (1 end).
  Diamond crossings are not nodes (a train runs straight through): `crossings` lists segment
  pairs, the intersection is computed at load (interlocking uses it later).
- Geometry: centripetal Catmull-Rom through the control points; at a node the neighbour
  segment's point is used for the end tangent (link: the other end, switch: trunk ↔ normal,
  branches ↔ trunk), so curves stay tangent-continuous across nodes. Resampled uniformly at
  ~1 m of 3D arc length → `pointAt(seg, s)` is O(1).
- A network position is `seg, s, dir` (`dir` +1 = towards the `b` end).

### Phase 1 results (2026-10-04)

- `tools/import_gta.js` → `data/network/gta_import.json`: 38 segments (main line M01–M13,
  second track S01–S11, spur C01, crossovers X_W1–X_W19, junctions J_NE / J_CR / J_SP), 27 nodes,
  13 switch groups, 4 scissors crossings; 28.2 km in all. The GTA files' 4th column (flag 1) marks
  the 6 station stop points.
- `data/network/files.json` is the manifest (`{ "files": [...] }` – MTA's `fromJSON` splits a
  top-level array into separate return values, so no bare arrays at the top).
- Build time: server ~190 ms, clients ~160–190 ms. Edit → save → reload round trip is lossless.
- Validation: 0 errors. The 4 warnings are the guessed junctions (tag `review`: J_NE gradient
  12.8 %, J_SP radius 23 m and a 4.7° kink at JSP, J_CR radius 57 m) – to be fixed against the
  real rails with the MCP. GTA's own geometry has curves down to ~15–17 m radius (Linden, the
  spur) and gradients up to ~24 % (SF): reported as `info` only.
- Screenshots: the centre lines lie on the physical rails (Unity, Market). Unity East has a
  physically existing yard track that is not registered (first candidate for phase 5).
- Height calibration on GTA trains standing on real rails: centre z = rail z +
  `getElementDistanceFromCentreOfMassToBaseOfModel` − 0.04 (`NET.RAIL_Z`); 538 → +0.171,
  570 → +2.55. Horizontal error 0.2 m.

Commands: `/rwnet` (debug drawing, `/rwnet pts` = control points), `/rwnetswitch <group>
[normal|reverse]`, `/rwnetcheck`, `/rwnetreload`. Exports: `netPutSegment / netDeleteSegment /
netPutNode / netDeleteNode / netPutGroup / netDeleteGroup / netPutCrossing / netGetSegment /
netGetNode / netSave / netReload / netSummary / netListSegments / netValidate / netProject /
netPointAt / netAdvance / netGetSwitch / netSetSwitch` (server), `netIsReady / netProject /
netPointAt` (client). Switch states here are only a debug toggle; locking / routes are phase 3.

## Phase 2 – trains on the network (2026-10-04)

Files: `shared/trainpath.lua`, `server/trains.lua`, `client/trains.lua`, `client/sweeper.lua`,
`client/sounds.lua`, `sounds/` (`run.wav` / `brake.wav` from `source/`, `clack.wav` / `squeal.wav`
synthesised by `tools/gen_sounds.js`). The phase 0 prototype (`proto/`, `/ctp`) was removed.

- **Route (`TrainPath`)**: whole segments laid out on one continuous coordinate u; head at `u`,
  car k centre at `u - offset_k`, bogies ± bogie/2. Grows forwards (switch states) 60 m ahead,
  backwards when reversing, trimmed behind. A switch change re-plans only the part ahead of the
  head / behind the rear (the part under the train is kept). A network edit rebuilds every route
  from the head position.
- **Simulation** (server, 10 Hz, real dt): controller −1..+1 (W / S, 0.6 per s; brake side
  recovers twice as fast), X = emergency, R = reverser (standing only). Tractive force
  `min(maxForce, power / v)`, resistance R0 + R1 v + R2 v², brakes 0.9 / 1.4 m/s². GTA gradients
  are scaled ×0.3 and capped at 4 % for the physics. Buffer stops / open ends and other trains
  stop the train; above 1.5 m/s that is an `onNetTrainCrash(id, other | "end", speed)` event.
  Trailing a non-spring switch set the other way fires `onNetTrainTrailedSwitch(id, node)`.
- **Clients**: snapshots every 500 ms + on changes, server-tick offset, extrapolation with v / a,
  errors blended over 300 ms, route extended locally when the head runs past it. Only streamed-in
  cars are placed (`setElementMatrix`); the server refreshes unoccupied cars ~1/s for streaming.
- **Driver** sits in the lead's driver seat (vehicles locked, game exit cancelled, F = leave when
  standing). **Passengers** are attached to a car (`STOCK.*.ride.spots`), camera targets the car,
  F = leave (put down 2.8 m right of the car).
- **Sweeper**: each client pushes what it controls (itself, its vehicle, synced peds / vehicles)
  out of the box in front of the leading end; damage by speed.
- **Sounds** near the camera: run loop (pitch / volume by speed), brake loop, a clack per bogie
  per 25 m joint, flange squeal below 150 m radius.

Commands: `/rwtrain spawn [light|re2|re3|re4] | drive [id] | ride [car] | leave | remove [id|all] |
list | tp <seg> <s>`. Exports: `spawnNetTrain(types, seg, s, dir) / destroyNetTrain /
setNetTrainControl(id, ctrl, rev, emergency) / getNetTrain / getNetTrains / setNetTrainDriver /
addNetTrainRider / removeNetTrainPlayer`.

### Phase 2 results (live, Cranberry spur C01 + the main line next to it)

- Spawned on the real rails at the SF docks: the cars sit on the rails (height calibration holds).
- Powered run up the 17 % spur (physics feels 4 %): accelerated, slowed on the climb, through the
  E_SP link, J_SP and the JSP spring switch onto M13; JSP thrown to reverse → the reversing
  train's route was re-planned into the spur at once.
- Buffer stop at the dock end: stopped exactly at the end, crash event at 81.6 km/h.
- Driver (Laptop112): W / S / X work, HUD shows speed, controller, reverser, gradient; emergency
  brake 47 → 0 km/h in ~6 s. Smoothness on the driver's client at ~79 fps: frame-to-frame jitter
  ~2 cm on average, max ~8 cm (part of it is the 1 ms tick resolution of the measurement).
- Passenger: attached to car 2, camera on the car, moving train fine.
- Sweeper: a car parked on the track was thrown ~30 m and damaged (1000 → 284) at ~40 km/h.
- No errors / warnings in the debug log. Sounds could not be listened to remotely.
- Open: once the controller rose after an emergency brake although the logs show no W input
  from the script (possibly a real key press on the laptop) – `NET.SIM.LOG_INPUT` logs every
  driver input until it is understood.
- Not tested yet: two trains colliding, many trains at once (performance), streaming far away.

## Phase 3 – switches and routes (2026-10-04)

User decisions: the switches are always handled by the system – no point machines / interaction
objects (the `machine` field was dropped from the data). The phase 2 driver HUD is a stand-in:
its functions (controller, reverser, authority / ATP) go into the `rw_loco` cab modules (BR 232
panel etc.) in phase 4 so they look authentic.

Files: `shared/routes.lua` (`Net.findRoute`), `server/switches.lua`, `client/switches.lua`.

- **Route finding**: Dijkstra over (segment, direction), no reversing; returns length, steps, nodes
  and the switch settings (`{ [group] = state }`). Facing switches give both options, trailing a
  non-spring switch requires its state, trailing a spring switch requires nothing.
- **Router** (every 250 ms) for every train with a destination (`setNetTrainDestination`,
  `/rwtrain dest <seg> <s>`): finds the route from the leading end (head, or rear when reversing),
  reserves + throws the switches up to max(250 m, braking distance + 150 m) ahead, one by one, and
  releases what is neither ahead on the route nor under the train. Spring switches fall back to
  normal on release.
- **Authority / ATP**: ends at the first switch it could not reserve (−15 m), 30 m behind another
  train on the route (moving block until signals exist), or at the destination (−1 m). On the
  braking curve the ATP applies just the deceleration needed to stop at the end (slope and
  resistance included); it never runs past it. ATP does not give traction back – the driver (or
  rw_auto) does. `onNetTrainArrived(id)` when the train stands within 3 m of its destination.
- **Locking**: a switch with a train on it or within 30 m cannot be thrown; a switch reserved by an
  owner can only be thrown by that owner.
- **Trailing** a non-spring switch set the other way (only trains without a route can do that):
  detected when the head actually passes the node (not when the route is planned 60 m early); the
  switch is pushed over to the leg the train came from and is damaged – no reservations – until it
  is repaired automatically after 120 s (or forced by an admin).
- **Drawn rails**: segments tagged `drawn` (crossovers, junctions – no physical rails) get dx
  sleepers + rails along the curve; `rwcore`-tagged ones are skipped while rw_core runs (it draws
  the same crossovers).
- Trains have a dimension (`spawnNetTrain(..., { dimension = n })`; `/rwtrain spawn` uses the
  player's) – used for testing next to the live system.

Exports: `getNetSwitches / findNetRoute / reserveNetRoute(owner, settings) / releaseNetRoute(owner
[, group]) / setNetTrainDestination(id, seg, s[, dir])`; `netSetSwitch(group, state, force)` is
the admin override (`/rwnetswitch <group> [normal|reverse] [force]`). Events `onNetSwitchChange`,
`onNetTrainArrived`.

### Phase 3 results (live, dimension 1, Unity W1 / W3)

- Route M03 → S01 over W3 (reverse) + W1 (normal): both reserved and thrown ahead, locked while the
  train ran over them, released behind it; ATP stopped the train 2.7 m before the destination
  (first version braked fully and stopped 18 m short → now graded).
- Conflict: train 1 (needs W1 normal) and train 2 (needs W1 reverse). Train 1 got W1, train 2's
  authority ended before W1 ("reserved by train:1"); once train 1 had passed, W1 was released and
  thrown reverse for train 2, which then stopped 33 m behind train 1 (moving block, 30 m gap).
- Trailing W3 (forced to reverse, train from the normal leg): pushed to normal, damaged,
  reservations refused (`W3: damaged`), repaired automatically after ~120 s.
- Offline route tests: Market crossover, spring switch both ways, Unity West scissors, loops.
- Seen while testing: at Cranberry the second track ends at a **physical buffer stop** inside the
  hall (so `J_CR` is fictional – it should be a buffer), and the spur runs parallel to the main
  line for a while before it physically joins (`J_SP` is too early). To fix when the tracks are
  recorded with the MCP.

## Track recording before phase 4 (2026-10-04, done)

User request: fix Cranberry hall track 3 and join it to the main line where the physical rails
are, add Cranberry track 4, build the second track SF – LV, add the physical LV tracks (with
switches), fix the double track between LV and LS.

**Finding physical track** (`tools/scan_rails.js` + `tools/rwdff.js`): every placed map model
(text IPLs + binary IPLs in gta3.img) whose DFF uses the track-bed textures `ws_traintrax1` /
`ws_traxonconcdirty` contributes the bed's centre line: the u = 0.5 iso-line of every flat bed
triangle that crosses u = 0.5 (the bed spans u 0..1 across the track, sometimes split into strips;
the rails are separate 0.1 m boxes 1.70 m apart, 0.2 m above the bed, u 0.19–0.24 / 0.77–0.79).
Result `tools/survey/rails.json`: 31.4 km of centre lines incl. turnout curves; 29.3 km lie on the
network within 0.25 m, the rail top is exactly 0.20 m above the network level. Not found this way:
the Cranberry hall, some tunnels / bridges (checked with screenshots instead). In the collision the
bed is `material_178` (whole bed width, not the axis).

**Network builder** `tools/build_network.js` (replaces `import_gta.js`) → `data/network/base.json`
(38 km, 82 segments, 62 nodes, 31 switch groups, 0 validation errors):
- **Second track SF – LV – LS** (runs `N`, `NB`, `NC`): the physical track 4.0 m outside the main
  line (scanned centre lines; unscanned tunnel / bridges north of Cranberry checked in game =
  double track). Two single-track stretches where the map has none: Yellow Bell east (fences, a
  level crossing) and the NE curve of LV (a single-track tunnel) – there the main line itself
  swings onto the outer alignment, so each run ends / starts at a switch on the main line where
  it has joined (JNb, JNBa, JNBb, JNCa – placed automatically, checked by screenshots). S + N/NB/NC
  form the second loop; the guessed junctions J_CR / J_NE / J_SP are gone (Cranberry track 2
  continues north, at NE LS the second track continues to LV).
- **Cranberry hall**: track 3 = the spur's station track (C02 / C03, buffer stop `B_C3` at the
  north end); south of the hall it leaves the spur at W21a and joins the main line at W21b along
  the measured physical curve. Track 4 (`P4`) leaves track 3 at W39 (measured curve), runs along
  the east platform, buffer stop at the north end.
- **LV freight yard at Linden** (`Y1`–`Y7`, switches W41–W53): a third track off the second track,
  a ladder and six sidings into the sheds, all ending at buffer stops; turnouts get a tangential
  lead-in so there is no kink at the switch.
- New scissors (drawn): Yellow Bell W23/W25 west, W27/W29 east; Linden W31/W33 north, W35/W37
  south.
- Route finding: 300 m penalty per diverging leg, so trains keep to their track.
- Warnings left (no errors): GTA's own tight turnouts (radius down to ~8 m in the yard ladder,
  3–6° kinks at the single-track joins and Cranberry turnouts).

Seen but not requested (can be added the same way): three sidings west of Cranberry track 2
(x −1952.5 / −1956.5 / −1960.5), the Unity East yard, the LS docks spur (the old `source/`
script's track).

## Phase 4 – integration (2026-10-04)

- **Lines** (`shared/lines.lua`, `NET.LINES`): 0 = main line loop (18.1 km), 3 = second track loop
  (18.2 km, through the single-track stretches on main line segments) with a continuous tp; the
  old (track, tp) API of the other resources runs on them (`lineProject / linePoint / lineLength /
  lineDelta / linePolyline / lineToNet`, client `lineProject`).
- **rw_core** is a facade: a consist = a network train (`onNetTrainStates` every simulation tick:
  lead's line positions, speed, driver, ...), `track` = the line the lead is on (nil off both),
  `Track` = the lines, switches = the network switches (`setSwitchState` with an owner = route
  reservation). Removed: GTA track data, `transferConsist`, virtual trains, point machines and
  rw_core's crossover drawing (rw_customtracks draws every `drawn` segment). Running numbers travel
  with the train (`setNetTrainData`), train ids are never reused (restart-safe).
- **rw_signals** pushes its red signals as ATP stop points (`setNetStopPoints`, on change + every
  5 s). Every train now has an authority: with a destination along its route, without one along
  the way ahead (current switch states, 2 km): red signal (−8 m), train ahead (−30 m), end of
  track, destination.
- **rw_auto**: each stop is the train's destination (`setNetTrainLineDestination`), the network
  routes it and the ATP stops it at the platform; rw_auto only sets a timetable speed (controller),
  the doors and the dwell. Diversions / route locks / default routes / client motion are gone.
- **rw_loco**: traction locks (engine, doors, emergency) and the emergency brake act on the network
  train (`netCab`), speed from the train, the cab door puts the driver into the network train
  (`setNetTrainDriver`). The phase 2 HUD is off in rw_loco cabs: the BR 232 desk got CONTROL and
  TARGET gauges, ATP / REVERSE lamps and a DIR (reverser) switch.
- Tested live (no screenshots): an IC ran Unity → Market on the new network, stopped 1.3 m from its
  stop point, doors opened on the right, the timetable recorded the stop; a driver test showed the
  engine traction lock, acceleration to 90 km/h on the second track, Sifa emergency braking.
  Fixed on the way: stale rw_auto trains after a restart removed a new train with a reused id.
- Not done yet: rw_timetable displays / zones for tracks off the lines (Cranberry 3 / 4, yard),
  player services choosing destinations (the work_traindriver), coupling via depot tested only
  through the API.
