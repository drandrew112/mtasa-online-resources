# pt_web - San Andreas Transit

The public transport website: one journey planner over every operator. Today that is the
railway (Sunline Rail, `[railways]`); the bus system plugs in through the provider protocol below.
It replaced the web map of `rw_core` (rw_core has no web files any more).

| where | address |
| --- | --- |
| HTTP | `http://<server>:<httpport>/pt_web/` (home), `/pt_web/map.html` (live railway map) |
| in game | `ui_browser` -> Services -> **sa-transit.sa** (registered in `server/api.lua`) |

Built on [web_api](../web_api/README.md): root `index.html` / `map.html` are the HTTP entries,
`web/*.html` the pages (in game through web_api's loader, links via `web/js/common.js` `PT.pageUrl`).

## Pages

- **Home** (`web/index.html`, `js/home.js`): journey planner (from / to, now or "depart at",
  results with changes, delays, intermediate stops, drawn on the map; `?from=rail:unity&to=rail:linden`
  deep links), live departure / arrival boards of every stop, the operators with their lines,
  **Become a railway worker** (steps, pay, ranks, drivers on duty - from `work_traindriver:getTrainDriverInfo`).
- **Live map** (`web/map.html`, `js/map.js`): the old rw_core map - trains, signals, switches,
  train panel, station boards. `map.html?station=<id>` opens a station.

## Server

```
server/config.lua         PT: providers, planner settings, site address
server/util.lua           export calls, v_locals message -> text (PT.LANG), time helpers
server/providers.lua      provider registry, global stop ids "<provider>:<stop>", trip cache
server/provider_rail.lua  Sunline Rail adapter (rw_timetable) + live map data (rw_core / rw_signals)
server/planner.lua        Connection Scan journey planner
server/api.lua            http="true" exports, ui_browser site
```

Web API (`http="true"`): `ptGetSite`, `ptPlan(from, to, when)` (`when` = nil / "HH:MM" / timestamp),
`ptGetBoard(stopId)`, `ptGetCareers`, `ptRailNetwork`, `ptRailState`, `ptRailBoards`.

### Planner

Earliest-arrival Connection Scan over the trips of all providers in `[now - 40 min, now + 3 h]`.
Changes: `TRANSFER_MIN` (60 s) at the same stop; footpaths between stops closer than `WALK_MAX`
(300 m, 1.3 m/s + 30 s) - that is how a bus stop in front of a station connects. A running trip
counts with its live delay. Up to `RESULTS` alternatives (next search starts 1 s after the first
departure); journeys that leave no earlier and arrive no later than another one are dropped.

### Adding an operator (buses)

Add an entry to `PT.PROVIDERS` with `resource = "<bus resource>"` and export these from it
(server, no `http` needed). Stop ids are local; pt_web prefixes them with the provider id.

| export | returns |
| --- | --- |
| `ptGetStops()` | `{ { id, name, city, x, y } }` |
| `ptGetTrips(t0, t1)` | trips departing in `[t0, t1]` (timestamps): `{ id, line, number, name, headsign, status = "scheduled"\|"active"\|"done"\|"cancelled", delay (s), stops = { { stop, arr, dep, state = "pending"\|"stopped"\|"done"\|"skipped" } } }`, `arr` / `dep` timestamps |
| `ptGetBoard(stopId, rows)` | `{ departures = { { time (sec of day), train, line, name, to, via = {names}, track, state, delay } }, arrivals = { ... from ... } }` |
| `ptGetLines()` | `{ { id, code, name, from, to, stops = {names}, headway (min) } }` |

Names may be v_locals message objects. Remove the bus entry from `PT.COMING_SOON` then.

Offline-tested only (Lua syntax + planner unit test with lupa on the real rw_timetable lines, JS
`node --check`). Live: `refresh`, `start pt_web`, `restart rw_core` (removes its web files), `restart work_traindriver`.
