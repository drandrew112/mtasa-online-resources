# ai_land_traffic

Server-simulated AI road traffic on the lane network in `data/`.

## How it works

- **Server owns the simulation** (`server/sim.lua`, 10 Hz). Each vehicle is a state on the network:
  segment (lane, or curved junction connection), distance `s`, speed, lateral offset, planned route.
  Car following is the Intelligent Driver Model; the most restrictive constraint wins each tick
  (leaders, curve speeds, stop lines, obstacles, emergency vehicles).
- **Only near players**: vehicles exist within `SIM_RADIUS` (400 m) of players in dimension 0 /
  interior 0. They spawn out of sight (170 m, 60 m while the area is nearly empty), are removed
  past 430 m. Density follows the lane length around each player (`LANE_PER_VEHICLE`, `MAX_PER_PLAYER`).
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
- **Emergency vehicles** (v_els): every driver in range rolls a chance to notice it each update.
  Lights only (`mkjState`) are rarely noticed (`ELS_NOTICE_LIGHTS`): the driver slows down and makes
  some room. The siren (`sirenState` / `sirenHorn`) is mostly noticed (`ELS_NOTICE_SIREN`): traffic
  ahead in the same direction pulls over (rescue lane: innermost lane of multi-lane roads goes left,
  others right) and stops when it is close; oncoming traffic slows and keeps right. Cross traffic that
  noticed it does not enter a junction it approaches; a standing one is passed slowly.
- **Lateral moves are steered**: lane offset changes (pulling over, passing a standing obstacle) are a
  function of the distance driven (`Geo.latAfter`, max lateral metres per metre), so cars turn out
  while rolling forward and only stop once they are aside. Clients compute the same curve.
- **Obstacles**: players, their vehicles, other vehicles and peds near players. Traffic stops behind
  them, honks at players, and passes a standing obstacle after 4 s.
- **Release**: crashes (`CRASH_FORCE`), shots, a player entering, explosion or the export turn the
  vehicle into a normal physics vehicle (automatic syncer again). After a crash the driver gets out.
  Released vehicles are removed when nobody is within 300 m.

## Data

`tools/build_network.py` → `data/*.json` (readable network) → `tools/build_runtime.py` →
`data/runtime/geo.dat` (geometry, also downloaded by clients) and `data/runtime/sim.dat` (server
topology: lane flags, successors, curve speeds, signal phases, junction conflicts / right of way,
trap lanes that never lead back to the main network). Rerun `build_runtime.py` after any network change.

`data/source/resource newtraffic` is the old resource, kept for reference only.

## Commands / exports

`/traffic [on|off|clear|debug]` (admin_level >= 4); no argument prints stats.

Server exports: `isTrafficVehicle(veh)` (true / "released" / false), `getTrafficVehicles()`,
`releaseTrafficVehicle(veh)`, `setTrafficEnabled(bool)`, `isTrafficEnabled()`, `getTrafficStats()`,
`getTrafficLight(phase)`.

Element data: `ai_traffic` = true on simulated vehicles and drivers, `"released"` after release.
