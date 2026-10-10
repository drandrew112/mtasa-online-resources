# [aviation] - air traffic control

Units everywhere: altitude **feet**, speed **knots**, vertical speed **ft/min**. Positions are GTA world metres.

| resource | what it does |
|---|---|
| `avi_core` | ATC rights (separate `TWR` / `APP` / `RADAR`; everybody has TWR by default; `setPlayerATCRight`, `setPlayerATCRights`, `hasATCRight`, `canStaffPosition`), ATC markers (`AVI.MARKERS`), `/atcright [player] <twr\|app\|radar\|all\|reset> [on\|off]`, `/avipos` (admins). |
| `avi_airspace` | `data/airspaces.json`: CTR (tower) and TMA (approach) per airport, one CTA (radar) = San Andreas + 500 m. Lookup priority CTR > TMA > CTA. |
| `avi_nav` | `data/nav.json`: FIXes (CTA/TMA boundaries, en route, one on every runway final = `LS27L`, `SF04`...), NDBs, VORs + their ground objects. Editor: `/avinav add\|move\|object\|del\|info`. |
| `avi_airports` | `data/airports.json`: SALS / SASF / SALV with runways, taxiways, gates. Runway in use comes from the wind (`/aviwind <dir> [kts]`). Taxi routing over the taxiways. |
| `avi_traffic` | Simulated traffic (no vehicles) from `data/flights.json` (50 fixed flights, started by the real clock). Gate - taxi - take-off - route - approach - landing - gate, go-around when too high at the final fix. `/avitraffic list\|spawn\|random\|remove\|clear\|schedule`. |
| `avi_controller` | Controller software, opened from the ATC marker (E; `/atc` is gone). Positions `SACC_CTR`, `<ICAO>_APP`, `<ICAO>_TWR`. |

## Runway data

The runway centre lines and thresholds were measured from the map models in gta3.img (markings / runway
textures): LS 09L/27R y = -2494 and 09R/27L y = -2593 (x 1440..2065), SF 04/22 on the line y = x + 1492,
LV 18/36 x = 1477 (y 1170..1825). The taxiways and gates follow the pavement of the same models. They are
approximations; adjust them in `airports.json` (`/avipos` prints your position).

## Scope

- wheel: zoom at the cursor; right drag: pan; left drag on a label: move it; click a label / target: menu.
  Distances (scale bar, menu) are in nautical miles.
- Airborne label (no background, grey on hover; blue text = yours, grey = someone else's, the controlling
  position in white): `CALLSIGN CTL TYPE/WAKE`, `ALT SPD DEST`, `CFL`, `WAYPOINT HEADING`, `SQK HDG VS`.
  Without hover: no CFL line without a cleared level, only the filled waypoint / heading, no SQK line.
  On hover the empty ones show as `CFL`, `DCT`, `AHDG`. Altitudes are in hundreds of feet (`045` = 4 500 ft).
- Ground label: green = arrival, blue = departure, grey = unknown; `CALLSIGN`, `SPD SQK`, `TYPE/WAKE`.
  A yellow frame = your aircraft waits for a clearance.
- Flight lists on the right: TWR / APP = Departures + Arrivals of the airport; centre = Departures (ground /
  departure TMA), Arrivals (arrival TMA / landed), Sector (the rest). RFL = requested cruise level of the
  flight plan, also marked green in the level menus.
- Airborne commands: cleared altitude, heading (replaces the waypoint; the aircraft intercepts the final of
  its arrival runway by itself), direct to (replaces the heading), resume own navigation, cleared to land,
  vacate via <taxiway>, go around, transfer, show route.
- Tower / ground: IFR clearance at the stand (initial level, accepts the route), pushback (tail first onto
  the nearest taxiway, nose towards the departure runway), taxi (to a runway / to a stand).
  Nobody enters a runway without a clearance; aircraft hold short at the runway edge and ask for:
  `CROSS` (crossing), `T/O` (line up and wait / take-off), `BKTRK` (backtrack first: enter far from the
  threshold, roll to it, turn round, then `T/O` from lined up). Take-off clearance only at the runway.
  Taxi speed 25 kts, on a runway 50 kts. No landing clearance 400 m before the threshold = go-around.
  After landing: off at the named exit (if still ahead) or the first exit towards the terminal.
- An aircraft stays with its controller while it is in that sector (TWR: CTR + ground + final, APP: TMA,
  centre: CTA) until transferred; leaving the sector hands it to the next staffed position or to the
  automatic mode. Final = the destination tower first. Nobody staffed = the pilots fly on their own.

## Scale

The map is small, so the traffic moves slower than its shown speed (`TR.AIR_SCALE` = 0.2 in
`avi_traffic/shared/config.lua`); climb / descent times stay realistic.

## v_monitors

Wall screens in the SF control tower base (plain 3D dxDraw, `dxDrawMaterialLine3D` of a render target). Monitor 1 =
fixed radar of the whole CTA; the others follow the avi_controller positions (`SACC_CTR`, `<ICAO>_APP`, `<ICAO>_TWR`),
each mirrors the staffed controller's scope (zoom / pan / label offsets, reported by the client every 5 s through
`avi:ctlView` / `getPositionViews`) or shows NOT IN USE. Name plate under every screen. Refresh: 5 s.
Wall geometry and sizes: `v_monitors/shared/config.lua` (`EYE_Z`, `MAX_WIDTH`, `FLIP_UV`).

## ATC markers and rights

- `avi_core` creates the ATC markers from `AVI.MARKERS` (first one: SF tower, in front of the wall screens). Press E in one:
  `avi_controller` opens the position login (or toggles the scope when already logged in).
- The markers are visible only to the players on duty in the work `AVI.MARKER_WORK` (`"atc"`, made by the future
  `work_atc`) through work_core `setElementVisibleToWork`; the server checks the duty too. `MARKER_WORK = false`
  shows them to everybody (testing).
- Rights: `TWR` = `<ICAO>_TWR`, `APP` = `<ICAO>_APP`, `RADAR` = `SACC_CTR`. Default: tower only. work_atc sets them
  from the work level with `setPlayerATCRight(player, "APP", true)`; taking the right of the current position logs
  the controller out. Rights are not persisted. Admins: `/atcright`.
