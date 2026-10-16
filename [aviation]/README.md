# [aviation] - air traffic control

Units everywhere: altitude **feet**, speed **knots**, vertical speed **ft/min**. Positions are GTA world metres.

| resource | what it does |
|---|---|
| `avi_core` | ATC rights (separate `TWR` / `APP` / `RADAR`; everybody has TWR by default; `setPlayerATCRight`, `setPlayerATCRights`, `hasATCRight`, `canStaffPosition`), ATC markers (`AVI.MARKERS`), `/atcright [player] <twr\|app\|radar\|all\|reset> [on\|off]`, `/avipos` (admins). |
| `avi_airspace` | `data/airspaces.json`: CTR (tower) and TMA (approach) per airport, one CTA (radar) = +-6000 m (San Andreas + 3000 m), SFC-FL660. The TMAs reach well out along the finals and do not overlap. Lookup priority CTR > TMA > CTA. `centre` = the centre sectors of the CTA (see below). |
| `avi_nav` | `data/nav.json`: FIXes (CTA/TMA boundaries, en route, one on every runway final = `LS27L`, `SF04`..., procedure points), NDBs, VORs + their ground objects, SID / STAR procedures. Editor: `/avinav add\|move\|object\|del\|info`. |
| `avi_airports` | `data/airports.json`: SALS / SASF / SALV with runways, taxiways, gates. Runway in use comes from the wind (`/aviwind <dir> [kts]`). Taxi routing over the taxiways (rounded corners), `taxiDraw` = the rounded taxiways for the scopes. |
| `avi_traffic` | Simulated traffic (no vehicles) from `data/flights.json` (180 fixed flights, 100 of them overflights = ~140 per hour, started by the real clock). Gate - taxi - take-off - SID - route - STAR - landing - gate, go-around procedure when too high at the final fix / without landing clearance. `/avitraffic list\|spawn\|random\|remove\|clear\|schedule`. |
| `avi_controller` | Controller software, opened from the ATC marker (E; `/atc` is gone). Positions `SACC_CTR` (+ `SACC_N_CTR`, `SACC_S_CTR`, `SACC_U_CTR`, `SACC_NU_CTR`, `SACC_SU_CTR`), `<ICAO>_APP`, `<ICAO>_TWR`. |
| `avi_web` | The ATC website `sanandreascontrol.eu` (HTTP `/avi_web/` + in-game ui_browser): documents (LOA), live status, procedures, airspace map. See below. |

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
- `<AP><rwy>H` (`LS27LH`, `SF04H`, `LV18H` ...) = half final: on the centre line halfway between the final fix and the
  threshold (600 m out). `<AP><rwy>P1` / `P2` = parallel to the runway, abeam the threshold, left / right of the
  landing direction (on the circuit lines: LS north y -1443.5 / south y -3643.5, SF 700 m, LV 750 m off the centre line).
- The half final of the opposite end is on the climb-out path, so SIDs that turned straight after the climb-out
  now fly out to it first (`VINEW1D 27R` = `LS09LH VINEW`, `GARCI2D 18` = `LV36H GARCI` ...). SIDs that already fly a
  climb-out / turn-back pattern keep it (a turn back from the half final would be over 100°). A SID fix the aircraft
  climbs past on runway heading counts as passed (it does not turn back for it).
- Go-around procedures `<ICAO>GA` (`type = "GA"`, one fix list per runway end): flown automatically after every
  go-around (too high at the final fix, no landing clearance, "Go around" command), always climbing to 3000 ft
  (`TR.GO_AROUND_ALT`): half final of the opposite end (straight ahead) -> circuit corner abeam it -> parallel fix abeam
  the threshold -> base fix abeam the final fix -> final fix. LS 09L / 27R circuit north, 09R / 27L south (outside the
  parallel pair), SF north-west, LV east. Every turn is 90°. The label shows `GA 27L`. Pilots on their own stay at
  3000 ft until the parallel fix, then descend for the approach; under control the aircraft needs a lower level and a
  new "Cleared approach" (accepted on the GA procedure). A direct / STAR / heading takes it off the procedure.
- STAR: entry fix -> (downwind, when the entry is beyond the runway) -> base fix -> final fix, or straight to the
  final fix when the entry is in front of it. SID: (climb-out fix) -> (turn fix) -> exit fix; with no fixes the
  aircraft turns to the exit fix right after the climb-out (800 ft AGL).
- Fly-by / fly-over: every fix is **fly-by** by default: the aircraft starts the turn to the next leg before the
  fix (lead = turn radius × tan(turn / 2), turn radius = world speed / `TURN_RATE`), so it rolls out on the next
  leg instead of overshooting it (90° turn at 250 kts: ~10 m instead of ~110 m). **Fly-over** fixes must be
  overflown (`FLYOVER_PASS_DIST` 30 m or abeam), the turn starts only after them. Mark one with
  `/avinav flyover <FIX> <PROC>` (only in that SID / STAR -> procedure `flyover = [ ... ]`) or
  `/avinav flyover <FIX>` (everywhere -> fix flag `"flyover": true`); the same command toggles it back. The scope
  draws fly-over fixes with a circle around the triangle. Final fixes, approach base points and go-around points
  are always fly-by.
- Turn limit: no turn is over 100°, neither inside a procedure (the 90° base / final turns are the biggest) nor along
  any `flights.json` route including its SID / STAR for every runway combination. A flight plan joins the SID / STAR
  fixes that suit both runway directions (e.g. LS<->LV = VINEW / SHADY, SF->LS = DOHER SANTA). Check with a script
  before you change fixes or routes. `LV368` = transition of `GARCI2D 36` (reaches GARCI from the north-east). `LV188` = transition of `GARCI2A 18` (keeps the leg off the SF/LV TMA border).
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
  position in white, shortened: centre `CM` (SACC_CTR) / `CN` / `CS` / `CU` / `CNU` / `CSU`, tower / approach of the
  own airport `T` / `A`, of another airport `SF_T` / `LS_A` (last two ICAO letters)): `CALLSIGN CTL TYPE/WAKE`, `ALT SPD DEST`, `CFL`, `WAYPOINT HEADING`, `SQK HDG VS`.
  Without hover: no CFL line without a cleared level, only the filled waypoint / heading, no SQK line.
  On hover the empty ones show as `CFL`, `DCT`, `AHDG`. Altitudes are in hundreds of feet (`045` = 4 500 ft).
- Ground label: green = arrival, blue = departure, grey = unknown; `CALLSIGN`, `SPD SQK`, `TYPE/WAKE`.
  A yellow frame = your aircraft waits for a clearance (ground and air: IFR when ready, push, taxi, runway, landing
  within 1500 m of the final fix, STAR near the entry fix); the list shows `REQ ...` for the same ones.
- Alerts (any aircraft): red text above the label frame and a red frame. `EMRG` = squawk 7700,
  `COMS` = squawk 7600, `DUPE` = another aircraft has the same squawk, `STCA` = separation lost, `RAM` = off the cleared route (more than 90° off the
  next point for 40 s while on own navigation; should never happen). `/avitraffic sqk <cs> <code>` sets a squawk.
- Separation (avi_traffic `alerts.lua`, fined once per pair, on every staffed controller of the two aircraft whose own
  sector it happened in (an aircraft controlled outside the controller's sector after an early transfer is not fined);
  the sum is the `Mistakes` item of the pay, a negative total is taken from the bank):
  ground head-on (60 m, facing each other) -€300; TMA / CTA closer than 0.1 nm and 1000 ft -€500.
  Amounts: `CTL.PENALTY`, distances: `TR.SEP_*`.
- Flight lists on the right: TWR / APP = Departures + Arrivals of the airport; centre = Departures (ground /
  departure TMA), Arrivals (arrival TMA / landed), Sector (the rest). RFL = requested cruise level of the
  flight plan, also marked green in the level menus.
- Airborne commands: cleared altitude, heading (replaces the waypoint), direct to (replaces the heading),
  resume own navigation, cleared approach, cleared to land,
  vacate via <taxiway>, go around, transfer, show route.
- Cleared approach (APP / centre / tower, whoever controls the aircraft): a controlled arrival does not start
  its final without it. No arrival procedure is needed: on a STAR / GA procedure it flies that one on; on radar
  vectors that intercept the extended centre line of any runway end of the destination ahead of the threshold
  at max 30 deg (`APP_CLR_ANGLE`, within `APP_CLR_FAR` final lengths) it keeps the heading and intercepts;
  otherwise it goes direct to the **nearest final fix** of the destination (base point first when it is on the
  airport side of it), dropping the rest of its route / heading (the label waypoint shows the final fix).
  Ideal level at the final fix: field + `FINAL_AGL` 1200 ft (cleared 1500 ft is fine; above field + 1700 ft =
  go-around). Glide = 1 ft per metre from the threshold. Without the clearance the aircraft flies through the
  final fix / centre line on its heading (vectors needed). The pilots ask for it (`APP`, yellow frame) within
  `APP_CALL_DIST` of the final fix or when their vectors would intercept.
  A new direct / STAR or a go-around cancels it; uncontrolled aircraft need none.
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

## Centre sectors

The CTA (SFC-FL660) is split into four sectors (`avi_airspace` `centre`): north / south of the line ZEPHR - PALIS -
VINEW - straight east to the edge (it does not follow the SF TMA), lower (up to FL205) / upper (above FL205). Every
sector belongs to the first staffed position of its chain, so any centre position can be opened on its own:

| sector | chain |
|---|---|
| north lower | `SACC_N_CTR` > `SACC_CTR` |
| south lower | `SACC_S_CTR` > `SACC_CTR` |
| north upper | `SACC_NU_CTR` > `SACC_U_CTR` > `SACC_N_CTR` > `SACC_CTR` |
| south upper | `SACC_SU_CTR` > `SACC_U_CTR` > `SACC_S_CTR` > `SACC_CTR` |

`SACC_CTR` alone has the whole CTA; `SACC_U_CTR` takes everything above FL205; the lower sectors always stay with
`SACC_CTR` / `SACC_N_CTR` / `SACC_S_CTR`. When the whole chain is closed the aircraft is uncontrolled. All centre
positions are type CTR (RADAR right) and in the ACC marker. The upper-only positions (`SACC_U_CTR`, `SACC_NU_CTR`,
`SACC_SU_CTR`) see traffic only from 2000 ft below the split (18 500 ft, `CTL.UPPER_VIEW_BELOW`) plus their own aircraft;
the others see everything. The scope of a centre position draws the north / south line,
fills its own sectors and shows them in the top bar (`SECT NL NU`). Cleared levels go up to FL390 (1000 ft steps above
FL200).

## Traffic volume

- Overflights: ~140 per hour (the 60 new ones fly every 30 min), mostly in the upper airspace (75 % FL210-390), on
  direct or one-en-route-fix routes between border fixes on different sides (max turn 43°). Flights across the
  border follow the semicircular rule (track 000-179 odd, 180-359 even thousands), max FL390; departures to and arrivals
  from beyond the border file FL150-390 (an arrival enters no higher than its descent plan allows).
- External flights appear `TR.ENTRY_LEAD_NM` (5.5 nm) before the CTA border on the extended first leg, so they are on
  the radar well before they enter (uncontrolled until the border).
- `TR.MAX_ACTIVE` 44 (aircraft before the border included), the workload keeper up to 52. An upper centre position
  (`SACC_U_CTR` / `NU` / `SU`) gets only high overflights from the keeper.

## Scale

The map is small, so the traffic moves slower than its shown speed (`TR.AIR_SCALE` = 0.2 in
`avi_traffic/shared/config.lua`); climb / descent times stay realistic.

## v_monitors

Wall screens in the SA Control building (San Fierro) (plain 3D dxDraw, `dxDrawMaterialLine3D` of a render target). Monitor 1 =
fixed radar of the whole CTA; the others follow the avi_controller positions (`SACC_CTR`, `<ICAO>_APP`, `<ICAO>_TWR`),
each mirrors the staffed controller's scope (zoom / pan / label offsets, reported by the client every 5 s through
`avi:ctlView` / `getPositionViews`) or shows NOT IN USE. Name plate under every screen. Refresh: 5 s.
Wall geometry and sizes: `v_monitors/shared/config.lua` (`EYE_Z`, `MAX_WIDTH`, `FLIP_UV`).

## ATC markers and rights

- `avi_core` creates the ATC markers from `AVI.MARKERS` (all in the SA Control building in San Fierro; no consoles in the airport towers). Press E in one:
  `avi_controller` opens the position login (or toggles the scope when already logged in).
- The markers are visible only to the players on duty in the work `AVI.MARKER_WORK` (`"atc"`, made by the future
  `work_atc`) through work_core `setElementVisibleToWork`; the server checks the duty too. `MARKER_WORK = false`
  shows them to everybody (testing).
- Rights: `TWR` = `<ICAO>_TWR`, `APP` = `<ICAO>_APP`, `RADAR` = every centre position (`SACC_CTR`, `SACC_N_CTR` ...). Default: tower only. work_atc sets them
  from the work level with `setPlayerATCRight(player, "APP", true)`; taking the right of the current position logs
  the controller out. Rights are not persisted. Admins: `/atcright`.

## avi_web - sanandreascontrol.eu

The ATC website (every ATC document goes here), built on web_api: `http://<server>:<httpport>/avi_web/`
and in game the ui_browser (CEF) site `sanandreascontrol.eu` (services). Pages: Home (open positions,
runways in use, wind, traffic counts, refreshed every 10 s), Documents (reader), Procedures (runways +
SID / STAR / GA per airport from avi_nav) and Airspace map ("Map" on a procedure row draws it).

- **Navigation never uses href.** web_api puts `<base href="/avi_web/web/">` into the page (HTTP and
  in game), so `href="#/docs"` would leave the page. Elements carry `data-go="docs/<id>"`; `go()` in
  app.js switches the page and only rewrites the fragment with an absolute URL.
- **Documents** = Markdown in `docs/`, listed in `docs/index.json` (reading order, category, code,
  version). The server reads them on every request (an edit shows after a reload; a new file needs an
  index entry + restart). Keep each under ~60 000 characters (MTA JSON string limit 65535).
  Renderer `web/js/markdown.js`: headings, paragraphs, bold / italic / code, `---`, `>` notes, lists
  (one nested level), pipe tables, links `[x](doc:<id>)`, `[x](doc:<id>#<heading>)`, `[x](#<heading>)`,
  `[x](https://...)`, and figure lines `![caption](img/<file>)`.
- **Figures** in `web/img/`: jpg / png are client files (list them in meta.xml), shown as `<img>`.
  svg are read by the server (`sacGetImage`) and inlined, because MTA serves files as
  application/octet-stream and browsers do not show such an SVG. The airspace / procedure SVGs are
  drawn from the real data by `tools/figures.py` (run it again after nav / airspace changes). The
  scope screenshots were taken on a probe client (1360x768).
- Documents: SACC-LOA-01 Letter of Agreement (transfer rules only), SACC-OPS-1..4 Operations Manual
  (general, aerodrome, approach with the STAR entry level annex, area), SACC-NAV-1 Airspace and
  navigation, SACC-SW-1 ATC software manual. Wording: "San Andreas FIR" = the whole airspace, "CTA" =
  the radar (centre) airspace only.

## Training hooks (work_atc training modules)

The training modules ADC / APC / ACC of `[work]/work_atc/training` run on the real resources:
- **avi_traffic** `server/tutorial.lua`: `spawnTutorialFlight(owner, { kind, icao, callsign, ... })`
  makes an aircraft with `ac.tut = owner`. Kinds: `dep` (at a stand), `arr` (on the final, cleared for
  the approach), `tma_arr` (in the CTA before its TMA entry fix, keeping its level until a controller
  has it; `star = true` lets the pilots pick the STAR), `inbound` (an arrival entering the CTA) and
  `overflight`. `spawnTutorialConflict(owner, { callsigns })` = two overflights head-on on one leg at
  the same level. Tutorial aircraft live in a world of their own (stands, taxi queues, runway use,
  alerts only among themselves) and are left out of `getTrafficSnapshot`, the traffic limits, the
  workload keeper, the callsign lookups and `/avitraffic clear`. Their controller is the owner's
  tutorial position (`setTutorialController`) by the normal sector rule; in the CTA that position is
  the only open one of the centre chains (`sectorPosition(ac, open)`). Separation losses fire
  `onAviTutorialSeparationLoss` (no fine). Parked tutorial aircraft are not removed.
  `setTutorialTimeScale` makes them fly faster (whole simulation steps per tick).
- **avi_controller**: `useTutorialConsole(player, posId)` opens a login with that one position; the
  tutorial login is not in `staff` (the live position stays free), sees only the own tutorial
  aircraft (`getTutorialSnapshot`), gets no pay / XP, and fires `onATCTutorialLogin`,
  `onATCTutorialCommand`, `onATCTutorialLogout` (with the receipt). Client exports for guides:
  `getScopeLayout`, `setScopeBlockedRect`, `focusScope`.
- **avi_core**: `createTutorialMarker(player, dimension, posId)` = a console marker copy in that
  dimension, visible only to the player.
