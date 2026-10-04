# [railways] – Sunline Rail

A realistic railway system for Los Santos, San Fierro and Las Venturas, operated by the fictional company
**Sunline Rail** (SLR). It will also serve the future `work_traindriver` work. The SF tram is
left out of the whole system on purpose.

| Resource | Job |
| --- | --- |
| `rw_customtracks` | The track network (own graph, independent of GTA's tracks), the trains (simulation + puppet vehicles), switches / routes / ATP, see `rw_customtracks/DESIGN.md` |
| `rw_core` | Track geometry, consists (every railway vehicle spawns here), switches, railway role, depots, network web map |
| `rw_signals` | Block signals for both tracks and both directions, direction lock, SPAD detection |
| `rw_timetable` | Stations, lines, services (trips), stop / door / delay monitoring, station displays |
| `rw_loco` | Cab simulation: BR 232 panel, timetable module, vigilance device (Sifa) |
| `rw_auto` | Automatic (NPC) trains for every trip nobody took, automatic switch setting |
| `rw_crossings` | Level crossings: the game's barriers replaced, closed while a train is near |

The load order is `rw_customtracks` → `rw_core` → `rw_signals` → `rw_timetable` → `rw_loco` → `rw_auto`, and
`rw_crossings` after `rw_timetable` (each one `<include>`s what it needs; `v_main` starts
them in dependency order). Travelling is free for now; tickets (bought at an interact
object) and coach interiors are planned.

## The network

`rw_customtracks` owns the network (`data/network/base.json`, built by
`rw_customtracks/tools/build_network.js` from GTA's tracks*.dat plus the physical track found in the
map models): main line loop, a second track loop beside it (LS – SF – LV – LS, two single-track
stretches in LV), crossovers, Cranberry hall tracks 1–4, the LV freight yard at Linden and the
Cranberry spur. The SF tram is left out on purpose.

The other resources keep working with **lines** ("tracks"): 0 = main line loop, 3 = second track
loop. A track position (tp) is the distance along the line in metres; `rw_core` offers
`projectToTrack / getTrackPoint / getTrackLength / getTrackDelta` on top of them. Track position
grows towards San Fierro on both lines ("dir +1" = towards SF). Trains off both lines (yards,
Cranberry tracks 3 / 4, on a crossover) have no track.

## Trains

Every train is a `rw_customtracks` network train: simulated on the server (controller, tractive
force, brakes, gradients), its vehicles are derailed + frozen puppets that every client places each
frame. `rw_core` keeps the consist API (`spawnConsist`, `getConsist`, ...) on top of them; the
GTA train tricks (re-creating trains at switches, virtual automatic trains) are gone.

## Switches

Real switches of the network, **always thrown by the system**: a train with a destination (an
automatic train's next stop, later a player's service) gets its route reserved and thrown switch by
switch ahead of it and released behind it. No point machines. A switch with a train on it cannot be
thrown. Every train has an ATP: its movement authority ends at a red signal, 30 m behind the train
ahead, at the destination or at a switch it could not get, and the train protection brakes in time.
Admins can force a switch with `/rwnetswitch <id> [normal|reverse] [force]`.

## Railway role ("vasutas jog")

Same model as the medsys medic role. Anyone can drive; with `RW.REQUIRE_RAILWAY_ROLE`
(default on) only role holders may assemble / spawn trains, throw switches and take
services. Exports: `setPlayerRailway`, `isPlayerRailway`, `hasRailwayAccess`,
`isRailwayRoleRequired`. Admins: `/rwrole [player] [on|off]`, `/rwdespawn [running number | id]`.

## Depots

Markers at Unity Station and Cranberry (E): spawn a preset train at one of the depot's spawn
points, couple / uncouple coaches, send a train to the shed. Uses the `ui_inac` temp menu.

## Signals

Both lines are signalled all the way round (loops): the main line (0) and the second track
(3). Block boundaries at the stations and junction areas (incl. the Cranberry South
scissors) plus automatic blocks (~800 m). Each boundary has a signal for each direction
(pole object + dx 3D head on the outer side of the double track). Aspects: red (block
occupied / section claimed by an opposing train), yellow (next signal red), green.
Direction lock per section between stations prevents head-on collisions; block occupancy
prevents rear-end ones. Passing a red signal fires `onRailSignalPassedAtDanger` and
`rw_loco` brakes the train.

The two single-track stretches in LV (Yellow Bell East JNb–JNBa and LV NE JNBb–JNCa, both
lines run over the same main line segments there) have their own entry signals on both
approaching tracks at both ends (`SIG.SINGLE`, names `YE…` / `NE…`): one train at a time,
whatever line it is on, and the first train inside or approaching claims the direction, so
two trains never enter from both ends. The double track between them (M22 / NB01) works as
a passing loop.

## Timetable

Stations: Unity, Market (LS), Cranberry (SF), Yellow Bell, Linden (LV). Game time = real
time (`realtime` resource), so trips are real clock times. 30 minute cycle, **directional
double-track running**: SF-bound / clockwise trains (Unity – Market – Cranberry – Yellow
Bell – Linden – Unity) use the main line, LS-bound / anticlockwise trains the second track.

| line | route | every | track |
| --- | --- | --- | --- |
| SL1 RB | Unity – Market – Cranberry | 15 min (:00) | main line, Cranberry track 4 |
| SL2 RB | Cranberry – Market – Unity | 15 min (:10) | Cranberry track 3, W21 / W19 onto the second track |
| SL3 IC | Unity – Market – Cranberry – Yellow Bell – Linden – Unity | 30 min (:06, :36) | main line |
| SL4 IC | Unity – Linden – Yellow Bell – Cranberry – Market – Unity | 30 min (:05, :35) | second track |

- Running times: Unity–Market 2, Market–Cranberry 4, Cranberry–Yellow Bell 4, Yellow
  Bell–Linden 3, Linden–Unity 4 min, 1 min dwell. Automatic trains run at line speed
  (105–120 km/h) and wait at the platform when they are early.
- On the LS – SF tracks the ICs run 6–9 minutes from the regionals.
- Cranberry: the regionals use the hall's dead-end tracks (4 in, 3 out), the main line
  platforms stay free for the ICs. Throat: SL1 enters track 4 at ~:07, SL2 leaves track 3 at
  ~:10, SL3 passes at ~:13 (+15 / +30).
- Single track in LV: SL4 is between Linden and Yellow Bell :10–:13, SL3 :19–:22 (+30) – the
  ICs never meet there; the entry signals protect it anyway.
- Hall tracks 3 / 4 are rw_customtracks lines 5 / 6 (open lines from W21a to the buffers).

Every station has a passenger display on a wall (departures and arrivals in separate
columns, with the track), see `rw_timetable/README.md`.

A service can be taken from 15 minutes up to **60 s before departure** (`TT.TAKE_LEAD`);
after that it belongs to `rw_auto`. The cab list only shows services the train can take now.
A stop counts when the train stands in the platform zone with the doors open for 15 s
(correct side where the platform is known). The departure time is when the train starts
moving. Delays, early departures and skipped stops are recorded; `onRailServiceComplete`
carries a summary for the work.

## Automatic trains (rw_auto)

Every trip nobody took is run by an automatic train:

- 58 s before departure rw_auto checks the trip; if a player took it, nothing happens.
- 55 s before departure the train is created at the origin (doors open): players can board
  the passenger coaches. The cab of an automatic train is locked.
- Each stop is the network train's destination: the network routes it (switches), and its ATP stops
  it at the platform, at red signals and behind other trains. rw_auto runs at line speed
  (`AUTO.VLINE`–`AUTO.VMAX`, faster when late), opens / closes the doors and keeps the dwell.
- At the terminus the passengers get off and the train is removed after 60 s - unless the
  line chains on (IC), then the same train runs the next trip.

## Level crossings (rw_crossings)

The game's 14 crossings (56 barrier objects, read from `models/gta3.img` by
`rw_crossings/tools/gen_crossings.js`) are removed and replaced by script objects. Each
crossing has a detection zone of 260 m of track on both sides of the road (on every track
it crosses), cut short so it never reaches into a station platform zone. The arms come
down while any train is in a zone (red lights flash) and go up 3 s after the last one left.
The zone is a stretch of track rather than a colshape sphere: it follows curves, stops
exactly where a station begins, and works for automatic trains too (they have no synced
vehicle position on the server).

For `work_traindriver`: `getAllServices()` lists every trip with its required consist and
whether it is taken; spawn a matching consist with `rw_core:spawnConsist`; the driver still
takes the service in the cab timetable module (or call `assignService`).

## Cab (rw_loco)

Entering the driver seat of a locomotive with a module shows its cab panel and, in the
bottom right corner, the small info display / the timetable panel (`F6`, with the server
clock). Nothing overlaps the minimap (layout reads `v_radar:getMinimapRect`) and the
right column keeps the notifications free.

- **Cab access (BR 232)**: the game's own enter / exit is blocked (broken on this model).
  Each side of the front cab has an "Enter the cab" `ui_interactobject` point; leaving
  (F, train standing) puts the driver down beside the cab on the platform side, or on the
  side away from other tracks. The game engine stays off until the simulated engine runs.

- **BR 232**: battery, fuel pump, engine start / stop, lights, doors L / close / R, Sifa,
  DIR (reverser, standing only); analog speedometer + battery / fuel / oil / coolant / rpm / load
  gauges, CONTROL (the controller: W / S, brake side negative), TARGET (distance left of the
  movement authority) and the ATP / REVERSE lamps. No traction without a running engine or with
  open doors (traction locks of the network train).
- **Sifa**: acknowledge (`space`) every 25–40 s while moving and whenever the signal in front
  changes; lamp → alarm → emergency stop. Sound: `rw_loco/sounds/sifa_alarm.wav` (temporarily
  the medsys Lifepak alarm – replace the file to change it).
- `LCTRL` shows the cursor for the panel. The keys are commands (`rw_cursor`, `rw_timetable`,
  `rw_sifa`), so players can rebind them in the MTA settings.

## Web map

`http://<server>:22005/rw_core/` and in game in `ui_browser` → Services →
**sunline-rail.sa**. `web/http.html` serves the HTTP page with css/js inlined;
`web/index.html` is the in-game CEF page (calls go through `mta.triggerEvent`). Trains are
grey without a timetable and green in service; click a train for its data, driver and
timetable; hover / click a station dot for its board and the trains related to it.
