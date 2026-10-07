# rw_core

Network core of Sunline Rail (see `../README.md` for the whole system).

## Server exports

| export | |
| --- | --- |
| `spawnConsist(spec) -> id \| false, reason` | `{ preset = "re2" \| loco = "br232", cars = {...}, spawn = "unity_1" \| track, tp \| x, y, dir = 1/-1, owner, force }` |
| `destroyConsist(id)`, `addCarriage(id, type)`, `removeCarriage(id)` | assembly (standing trains only) |
| `transferConsist(id, track, centreTp, flip)` | re-create on another track (switches use it) |
| `setConsistSpeed(id, speed)` | game units, for automation / tests |
| `getConsist(id)`, `getConsists()` | `{ id, number, label ("BR 232 1112"), lead, vehicles, types, loco, carriages, passengerCars, seats, track, tp, dir, moveDir, speed (km/h), lo, hi, driver, owner }` |
| `getVehicleConsist(vehicle)`, `getConsistByDriver(player)` | |
| `projectToTrack(x, y [, track])`, `getTrackPoint(track, tp)`, `getTrackLength`, `getTrackDelta`, `getTrackPolyline` | geometry (call once, not per frame) |
| `getSwitches()`, `getSwitchState(id)`, `setSwitchState(id, state [, player])` | `"normal"` / `"reverse"` |
| `setPlayerRailway`, `isPlayerRailway`, `hasRailwayAccess`, `isRailwayRoleRequired`, `getRailwayPlayers`, `isRailwayAdmin` | railway role |
| `rwGetNetwork()`, `rwGetState()`, `rwGetBoards()` | web map API (`http="true"`, built on `web_api`: HTTP page at `/rw_core/`, in game the `sunline-rail.sa` ui_browser site, registered in `server/web.lua`); `rwGetBoards` = every station's departure / arrival board (rw_timetable `getStationBoards`, 12 rows) for the right-hand station panel |

Client exports: `isPlayerRailway`, `hasRailwayAccess`, `isRailwayRoleRequired`.

## Events (server)

`onRailConsistSpawn(id)`, `onRailConsistDestroy(id)`, `onRailConsistRebuilt(id, newLead, oldLead)`,
`onRailConsistChange(id)` (source: lead), `onRailSwitchChange(id, state, player)`,
`onPlayerRailwayChange(enabled)` (source: player).

## Element data

Lead: `rw.consist`, `rw.track`, `rw.cars`, `rw.type`, `rw.dir`, `rw.number` (running number, e.g. `"BR 232 1112"`). Coaches: `rw.consist`, `rw.type`.
Players: `rw.role`. `resourceRoot`: `rw.switches` (`{ W1 = "normal", ... }`).

## Running numbers / info boards

Every locomotive gets a free running number from its class range (`RW.VEHICLES[x].numbers`) when
it spawns; it is kept through switch transfers and freed when the train goes. Without a service
the train is called after it (web map, depot menu); with a service the map shows the trip and the
detail shows the number. `client/trainlabel.lua` draws a 3D board above every locomotive
(number, speed, line + trip + destination, next stop + delay, doors, driver, coaches;
`RW.LABEL`), hidden for the driver of that train. `/rwlabels` toggles it.

## Commands

`/rwrole [player] [on|off]`, `/rwdespawn [running number | id]` (admin_level >= `RW.ADMIN_LEVEL`).

## Railway log (server/log.lua)

Every railway event in one log: the newest `RW.LOG.KEEP` entries in memory and a daily file
`rw_core/logs/rail_YYYY-MM-DD.log` (`2026-10-04 12:03:07 WARN  stuck   [BR 232 1112 / SL1 1015] stuck for 2 min 10 s: train ahead (BR 232 1200)`).

| category | what |
|---|---|
| train   | spawn / removal (reason) / composition, driver takes / leaves the cab, crossing between lines (debug) |
| service | service start / completion summary / cancellation, cancelled trips |
| stop    | arrival + departure per station with delay, early departure, stop not served, wrong door side |
| delay   | the delay of a service changes by a minute (warn from `TT.LOG_DELAY_WARN` min) |
| hold    | standing at a red signal / behind a train / without a route for `HOLD_MIN` s, and when it clears |
| stuck   | held for `STUCK_AFTER` s, or an automatic train standing that long outside a station |
| switch  | thrown (route of which train / spring / forced), trailed (damaged), repaired |
| signal  | aspect changes (debug, frequent) |
| spad / safety | signal passed at danger, emergency brake, Sifa brake, ATP overrun, collisions |
| auto / loco   | rw_auto problems (no route, cannot spawn, cancelled), engine, doors (debug) |

- `railLog(category, level, text, consistId?, data?)` - write an entry (level debug / info / warn / error).
- `getRailLog({ category, level, train, match, since, limit })` - entries, oldest first.
- `railTrainTag(consistId)` - "BR 232 1112 / SL1 1015".
- `/rwlog [warn | <category> | all | <text>] [count]` (railway admins) - no filter = everything but debug.
  Text matches the train tag or the message ("1112", "SL3", "W19", "Market").
