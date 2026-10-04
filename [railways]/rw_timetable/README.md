# rw_timetable

Stations, lines and services of Sunline Rail (see `../README.md`). Configuration:
`shared/config.lua` (stations with platform zones, lines with stop times in minutes,
headway, consist requirements).

Server exports:

| export | |
| --- | --- |
| `getStations()` | `{ id, name, city, x, y }` |
| `getAllServices([t0, t1])` | every trip in the window (timestamps) with `requires`, `status`, `consist`, `depTimestamp` - for work_traindriver |
| `getServicesForConsist(consistId)` | trips this consist could take now, with `ok` / `reason` |
| `assignService(consistId, tripId [, player])` | `player` = role check |
| `cancelService(consistId, reason)` | |
| `getConsistService(consistId)` | running service view (times in seconds of the day) |
| `getTripsOverview()` | trips -30 / +60 min for station boards |
| `isConsistAtStation(consistId)`, `canOpenDoors(consistId)` | |
| `getStationBoard(stationId[, rows])` | the passenger board of a station: `departures` / `arrivals` (time, train, destination / origin, via, track, state, delay); `rows` per column, default `TT.BOARD.ROWS` |
| `getStationBoards([rows])` | every station's board, `{ [stationId] = board }` (rw_core web map) |

Events (source: lead): `onRailServiceStart(consistId, tripId, player)`,
`onRailServiceStop(consistId, tripId, stopIndex, record)`,
`onRailServiceComplete(consistId, tripId, player, summary)`,
`onRailServiceCancel(consistId, tripId, reason)`.

The lead carries `rw.service` element data (the running service view) for the cab module.

## Station displays

Every station has a departure / arrival board drawn with dx on a wall (`TT.DISPLAYS`,
`client/displays.lua`, data from `server/displays.lua`). Departures on the left, arrivals
on the right, each with time (expected time below when late), train, destination / origin
with the stops in between, **track** and a remark (on time, +N min, Boarding, At platform,
Departed, Arrived, Cancelled).

- Track: the line's `track` (a stop's own `track` overrides it), shown as the station's
  `tracks` label (track 0 = "1", track 3 = "2"). A train standing in the station shows the
  track it really stands on (e.g. after an rw_auto diversion).
- A station near the camera (`BOARD.KEEP_DIST`) gets a 1280x640 render target; its data
  comes every `BOARD.REFRESH` s, the picture (clock, blinking "Boarding") is redrawn a few
  times a second. Boards are drawn within `BOARD.DRAW_DIST`.
- Placing a new board: look at the wall and type `/rwboardpos [w] [h]` - it prints a ready
  `TT.DISPLAYS` line (wall point + normal). Note: collision and the visible wall can differ,
  and some walls carry posters without collision (check in game).

| station | wall |
| --- | --- |
| Unity | west end wall of the station building (brick strip beside track 1) |
| Market | tiled wall behind the main platform (underground hall) |
| Cranberry | inside the station building, on the pillar between the two platform doors |
| Yellow Bell | south platform wall, east of the passage |
| Linden | platform wall, north of the passage |
