# ai_land_traffic

Server-simulated AI road traffic on the navmesh lane network (`[core]/navmesh`, a required resource: `<include>`).

## How it works

- **Server owns the simulation** (`server/sim.lua`, 10 Hz). Each vehicle is a state on the network:
  segment (lane, or curved junction connection), distance `s`, speed, lateral offset, planned route.
  Car following is the Intelligent Driver Model; the most restrictive constraint wins each tick
  (leaders, curve speeds, stop lines, obstacles, emergency vehicles).
- **Only on the players' routes** (`server/route.lua`): vehicles exist within `SIM_RADIUS` (300 m)
  of players in dimension 0 / interior 0. New ones only spawn on the player's expected route: the
  lanes reachable forward along the road graph within `ROUTE_LENGTH` (300 m, every branch) from the
  carriageway under the player (heading from the velocity, else the vehicle facing / camera; off-road:
  the nearest road both ways), plus their oncoming lanes and the lanes feeding into them at junctions.
  With a v_radar GPS destination on the player's vehicle (`gpsDestination`) the navmesh route to it is the
  expected route instead of every branch (requested async, again when the player leaves it, `GPS_RETRY`).
  Density follows that lane length (`LANE_PER_VEHICLE`, `MAX_PER_PLAYER`) and drops to `STILL_FACTOR`
  while the player stands. Spawns stay 120 m from players (60 m while nearly empty) and 200 m from
  any camera that looks at the spot. Players share one budget: a spawn point must be under the cap of
  every player within 300 m (their own target, `MAX_PER_PLAYER` for the others), so two players in
  one place do not get twice the traffic. A regional limit (`AREA_MAX` vehicles within `AREA_RADIUS`,
  released vehicles included) keeps any one spot from filling up.
- **Camera culling** (`server/views.lua`, `client/views.lua`): clients report their camera every
  300 ms. A vehicle that no player's camera sees (`VIEW_HALF_ANGLE` from the look direction) for
  `CULL_AFTER` and is farther than `CULL_MIN_DIST` from every player is removed; a player without a
  fresh report counts as seeing everything. Everything past `DESPAWN_RADIUS` (330 m) is removed.
- **Clients are puppets** (`client/puppets.lua`): the server sends `(segment, s, v, a, lateral, next)`
  records only when the client prediction would drift (dead reckoning); every client places the
  vehicles each frame with the same geometry code (`shared/geometry.lua`). The vehicles and driver
  peds are real server elements with syncing turned off. Measured: ~1 record / vehicle / s,
  client-server position error mean 4 cm. Drivers get a tiny analog throttle on the client
  (`DRIVER_THROTTLE`): without input GTA brakes ped-driven cars, locking the wheels (skid marks).
- **Junctions**: one global traffic light cycle that also drives GTA's light objects
  (`setTrafficLightState`, phase 1 = north-south, 2 = east-west). Unsignalled: major road first,
  otherwise right-hand priority, left turns yield to oncoming. Conflicting paths are precomputed;
  waiting-for cycles are detected, and a vehicle that waited 4 s claims the junction.
- **Emergency vehicles** (v_els, `server/els.lua`): every driver in range rolls a chance to notice it each
  update. Lights only (`mkjState`) are rarely noticed (`ELS_NOTICE_LIGHTS`): the driver slows down and makes
  some room. The siren (`sirenState` / `sirenHorn`) is mostly noticed (`ELS_NOTICE_SIREN`).
  - *Where it goes* (navmesh): with a destination (`gpsDestination` of the vehicle, or the export
    `setEmergencyDestination`) its navmesh route (emergency profile) for the next `ELS_PATH_LENGTH` m; without one
    its lane is snapped (`getNearestLane`) and the road ahead predicted (straight on where possible). Only traffic
    on that path gives way, measured along the road (curves, parallel roads, overpasses and side streets sort
    themselves out); oncoming traffic on the same road slows and keeps right. Without a lane (off-road, navmesh
    off) the old straight-line test is used.
  - *Pulling over*: always to the right. A car in the inner lane of a multi-lane road first changes into the
    outer lane; in the outer lane / on a single lane road it moves aside as far as the ground allows: the
    navmesh walk grid is probed a few metres ahead for the car's centre and right side (`ELS_PULL_STEPS` 3.2 /
    2.4 / 1.6 / 1.0 m; no wall or drop, water or steep slope, height within `ELS_GROUND_DZ` of the ground at the
    lane centre; cached per 4 m). It stops once the emergency vehicle is close (`ELS_STOP_DIST`).
  - *No room* (bridges, walls, mountain roads): a random-traffic car turns off into a right side road within
    `ELS_TURNOFF_DIST` that is not on the emergency path; otherwise it drives on at `ELS_SEEK_SPEED` until there
    is room, instead of stopping in the way.
  - *Junctions*: cross traffic that noticed it does not enter a junction it approaches. With a known route only
    where the route's path through that junction conflicts with the car's (precomputed conflicts); with a
    predicted path every approach waits. A standing emergency vehicle is passed slowly.
- **Lanes** (`server/lanes.lua`): on multi-lane carriageways traffic keeps to the outer (rightmost) lane,
  and only spawns there. The inner lane is for passing: a car held up by a clearly slower leader changes
  into it when the gaps allow, and returns to the outer lane as soon as there is room (not while a left /
  u-turn is planned or a junction is near). A lane change re-places the agent on the neighbouring lane at
  once (`Agents.changeLane`, old position kept as lateral offset), then the offset eases out. `sim.dat`
  lists each lane's left / right neighbour.
- **Lateral moves are steered**: lane offset changes (pulling over, passing a standing obstacle) are a
  function of the distance driven (`Geo.latAfter`, max lateral metres per metre), so cars turn out
  while rolling forward and only stop once they are aside. Clients compute the same curve; the car heading comes from the lateral rate reached so far, so a
  standing car never yaws on the spot when its target changes.
- **Obstacles**: players, their vehicles, other vehicles and peds near players. Traffic stops behind
  them, honks at players, and passes a standing obstacle after 4 s.
- **Release**: crashes (`CRASH_FORCE`), shots, a player entering, explosion or the export turn the
  vehicle into a normal physics vehicle (automatic syncer again). After a crash the driver gets out.
  Released vehicles are removed when nobody is within 300 m.

## Data (navmesh)

The road network is navmesh's `roads.nav` (GTA NODES*.DAT with the one-way ramp fixes). `tools/build_runtime.py`
copies it with the same lane / connection ids into `data/runtime/geo.dat` (geometry, also downloaded by clients)
and `data/runtime/sim.dat` (server topology: lane flags, successors, curve speeds, signal phases, junction
conflicts / right of way, trap lanes that never lead back to the main network), so navmesh route results are
driven directly. **Rerun `python tools/build_runtime.py` after navmesh's `tools/build_roads.py`.** sim.dat carries
the md5 of roads.nav; `server/navmesh.lua` compares it with `getNavmeshStats().roads.signature` on start (and on
`onNavmeshReady`) and turns the navmesh routes off when they differ (debug warning; traffic keeps driving).

`server/navmesh.lua` wraps the exports (all through pcall): `findVehicleRoute` with `startLane` / `goalLane` /
`lanesOnly` (scripted vehicles), `requestRoute` (GPS destinations, async), `getNearestLane` (emergency vehicles),
`getWalkableGround` (pulling over).

## Commands / exports

`/traffic [on|off|clear|debug]` (admin_level >= 4); no argument prints stats.

Server exports: `isTrafficVehicle(veh)` (true / "released" / false), `getTrafficVehicles()`,
`releaseTrafficVehicle(veh)`, `setTrafficEnabled(bool)`, `isTrafficEnabled()`, `getTrafficStats()`,
`getTrafficLight(phase)`, `setEmergencyDestination(veh, x, y, z | false)` (where an emergency vehicle is going, e.g.
an ERM dispatch target; wins over its `gpsDestination`, false clears it).

### Scripted vehicles (`server/scripted.lua`)

Other resources (the bus system) create vehicles that drive to targets inside the traffic: same lanes,
lights, right of way and car following; they react to emergency vehicles like any other traffic. The random
traffic never spawns buses (431 / 437); a scripted vehicle can be any model.

- `createScriptedVehicle(model, x, y, z, {heading, skin, speedFactor, profile})` -> `veh, driverPed` | `false, reason`;
  placed on the nearest road (outer lane, `heading` picks the direction), standing. `profile` = navmesh vehicle
  profile of its routes (`car` default, `bus`, `truck`, `emergency`...).
- `addScriptedStop(veh, x, y, z, {wait = ms, hold = bool, tag, heading, radius})` -> target id: the front stops
  at the nearest road point (outer lane), waits `wait` ms (`hold = true`: until `continueScriptedVehicle`).
- `addScriptedTurnPoint(veh, x, y, z, {tag, ...})`: the route passes that road point, no stop. Place it on the
  lane behind a turn to force the turn.
- `removeScriptedTarget(veh, id)`, `clearScriptedTargets(veh)`, `continueScriptedVehicle(veh)`,
  `destroyScriptedVehicle(veh)`, `isScriptedVehicle`, `getScriptedVehicles`, `getScriptedTargets(veh)`,
  `getScriptedVehicleState(veh)`.
- Targets are done in order; the route between them is a navmesh lane route (`findVehicleRoute` from the lane to
  the target lane; lane changes where the route needs them, a missed stop is driven round again: the search starts
  at the lane end and comes back to it, an unreachable target is dropped with an event).
- Scripted vehicles are never culled (no camera / distance / standing-time removal), are not cleared by
  `/traffic clear|off`, and keep driving while nobody is online. They go when: `destroyScriptedVehicle`,
  `SCRIPTED_END_LIFE` (3 min) after the last target is done or removed (a new target cancels it; without any
  target they drive on as random traffic), or when they leave the simulation (crash, shot, driver seat taken,
  explosion: then an ordinary released vehicle). A player entering a passenger seat does not release it.
- Events (server, on `root`, first argument the vehicle): `onTrafficVehicleTargetReached(veh, id, kind, tag, x, y, z)`,
  `onTrafficVehicleTargetDeparted(...)`, `onTrafficVehicleTargetFailed(veh, id, kind, tag, reason)`,
  `onTrafficVehicleRouteFinished(veh, removeInMs)`, `onTrafficVehicleRemoved(veh, reason)`.

Element data: `ai_traffic` = true on simulated vehicles and drivers, `"released"` after release.
