# [aviation] - air traffic control

Units everywhere: altitude **feet**, speed **knots**, vertical speed **ft/min**. Positions are GTA world metres.

| resource | what it does |
|---|---|
| `avi_core` | ATC rights (separate `TWR` / `APP` / `RADAR`; everybody has TWR by default; `setPlayerATCRight`, `setPlayerATCRights`, `hasATCRight`, `canStaffPosition`), ATC markers (`AVI.MARKERS`), `/atcright [player] <twr\|app\|radar\|all\|reset> [on\|off]`, `/avipos` (admins). |
| `avi_airspace` | `data/airspaces.json`: CTR (tower) and TMA (approach) per airport, one CTA (radar) = +-6000 m (San Andreas + 3000 m). The TMAs reach well out along the finals and do not overlap. Lookup priority CTR > TMA > CTA. |
| `avi_nav` | `data/nav.json`: FIXes (CTA/TMA boundaries, en route, one on every runway final = `LS27L`, `SF04`..., procedure points), NDBs, VORs + their ground objects, SID / STAR procedures. Editor: `/avinav add\|move\|object\|del\|info`. |
| `avi_airports` | `data/airports.json`: SALS / SASF / SALV with runways, taxiways, gates. Runway in use comes from the wind (`/aviwind <dir> [kts]`). Taxi routing over the taxiways (rounded corners), `taxiDraw` = the rounded taxiways for the scopes. |
| `avi_traffic` | Simulated traffic (no vehicles) from `data/flights.json` (120 fixed flights, 40 of them overflights, started by the real clock, period 120 min). Gate - taxi - take-off - SID - route - STAR - landing - gate, go-around when too high at the final fix. `/avitraffic list\|spawn\|random\|remove\|clear\|schedule`. |
| `avi_controller` | Controller software, opened from the ATC marker (E; `/atc` is gone). Positions `SACC_CTR`, `<ICAO>_APP`, `<ICAO>_TWR`. |

## Taxiing

- Taxi routes avoid runways: taxiing on a runway or crossing one costs `AP.RUNWAY_TAXI_COST` (6) times the distance,
  so departures taxi to the runway end on the taxiways (LS: `K` / `L` run behind both runway ends outside the runway
  zones) and backtrack only where no taxiway reaches the threshold (SF 22).
- After landing the aircraft vacates towards the nearest stands.
- Taxi spacing (`TR.TAXI_SEP` 60 m, `TR.TAXI_SEP_LAT` 18 m): a taxiing aircraft stops behind anything on its path
  ahead (taxiing, holding short, pushed back), so departures queue up at the holding point. Head-on / at an
  intersection the older flight (lower id) goes first; a waiting cycle is broken by the aircraft that closes it.
  Aircraft on a runway never wait (the runway clearances separate them). Uncontrolled aircraft do not push back
  while someone taxies near their push-back end point.

## Runway data

The runway centre lines and thresholds were measured from the map models in gta3.img (markings / runway
textures): LS 09L/27R y = -2494 and 09R/27L y = -2593 (x 1440..2065), SF 04/22 on the line y = x + 1492,
LV 18/36 x = 1477 (y 1170..1825). The taxiways and gates follow the pavement of the same models. They are
approximations; adjust them in `airports.json` (`/avipos` prints your position).

## Procedures (SID / STAR)

`avi_nav/data/nav.json` -> `procedures`: `{ id, type = "SID"|"STAR", airport, fix, runways = { [ident] = { fix, ... } } }`.
Every TMA boundary fix has an arrival `<FIX>1A` and a departure `<FIX>1D` for every runway (GARCI is on the SF / LV border:
SF `GARCI1A/1D`, LV `GARCI2A/2D`). Written as `VINEW1A 27R` (STAR + runway), `VINEW1D 27L` (SID + runway).

- Procedure fixes `<AP><rwy><n>` (kind `proc`, drawn small, only zoomed in): `1` / `2` = base fixes abeam the final fix,
  left / right of the landing direction (the transitions parallel to the final, e.g. `LS272` north and `LS271` south
  of `LS27R`); `3` / `4` = downwind abeam the far runway end; `5` = climb-out fix on the centre line past the far end;
  `6` / `7` = turn-back fixes for SIDs to exits behind the departure; `8` = extra SID transition (`LS098`: 09
  departures to SANTA / REEFS turn back west south of the field, then reach REEFS heading south).
- STAR: entry fix -> (downwind, when the entry is beyond the runway) -> base fix -> final fix, or straight to the
  final fix when the entry is in front of it. SID: (climb-out fix) -> (turn fix) -> exit fix; with no fixes the
  aircraft turns to the exit fix right after the climb-out (800 ft AGL).
- Turn limit: no turn is over 100°, neither inside a procedure (the 90° base / final turns are the biggest) nor along
  any `flights.json` route including its SID / STAR for every runway combination. A flight plan joins the SID / STAR
  fixes that suit both runway directions (e.g. LS<->LV = VINEW / SHADY, SF->LS = DOHER SANTA). Check with a script
  before you change fixes or routes. `LV368` = transition of `GARCI2D 36` (reaches GARCI from the north-east).
- The flight plan (`flights.json` route) starts with the TMA exit fix of the departure airport and ends with the TMA
  entry fix of the arrival airport, so the suggested SID / STAR is the one of those fixes.
- IFR clearance (tower): first the SID list (suggested one yellow, runway in use first, "No SID"), then the initial
  level. The aircraft taxis to the runway of the SID unless the taxi clearance names another one; at take-off the SID
  is flown for the runway actually used.
- Approach / radar: "Arrival procedure >" (suggested STAR yellow). Fixes already behind the aircraft are skipped; it
  lands on the runway of the STAR. An arrival close to its entry fix without a STAR asks for one (`STAR` request).
- The procedure is shown in the waypoint field of the label (a direct-to replaces it while active). Without a
  controller the pilots fly the suggested SID / STAR for the runway in use themselves. A go-around drops the STAR.
- `data/nav.json` was generated (fixes + procedures); the editor keeps the procedures when it saves.

## Scope

- keys 0-5: speed vector (leader line) length in nm, 0 = off.
- wheel: zoom at the cursor; right drag: pan; left drag on a label: move it; click a label / target: menu.
  Distances (scale bar, menu) are in nautical miles.
- Airborne label (no background, grey on hover; blue text = yours, grey = someone else's, the controlling
  position in white): `CALLSIGN CTL TYPE/WAKE`, `ALT SPD DEST`, `CFL`, `WAYPOINT HEADING`, `SQK HDG VS`.
  Without hover: no CFL line without a cleared level, only the filled waypoint / heading, no SQK line.
  On hover the empty ones show as `CFL`, `DCT`, `AHDG`. Altitudes are in hundreds of feet (`045` = 4 500 ft).
- Ground label: green = arrival, blue = departure, grey = unknown; `CALLSIGN`, `SPD SQK`, `TYPE/WAKE`.
  A yellow frame = your aircraft waits for a clearance (ground and air: IFR when ready, push, taxi, runway, landing
  within 1500 m of the final fix, STAR near the entry fix); the list shows `REQ ...` for the same ones.
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
- No top-down cover: every aircraft belongs to exactly one position, the one of the sector it is in
  (TWR: CTR + ground + final, APP: TMA outside the CTR, centre: CTA outside every TMA). When that
  position is closed the pilots fly on their own, even if approach / radar is open. Tower clearances
  (IFR, push, taxi, runway, landing, vacate) are TWR-only, arrival procedures APP / centre only.
  "Transfer to" is an early handoff: the receiver has the aircraft while it is still in the sender's
  sector, then the sector rule takes over.

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
