# rw_passengers – design

Passengers of Sunline Rail: boarding and leaving passenger coaches through ui_interactobject, a
real walkable coach interior per coach (the **dimension is the coach's id**), and windows that
show the outside world while the train runs.

Rules given by the user:

1. Boarding and leaving go through **interact objects** (ui_interactobject), not the game's
   enter / exit.
2. Boarding and leaving are **only possible while the train stands**.
3. The interior must exist in **every dimension except 0**; the dimension identifies the coach.

Status: built 2026-10-04 (phases 0–3, see section 11); waiting for the user's manual test.

## 1. Interior survey (2026-10-04, live, MTA World MCP)

| Candidate | Where | Measured | Verdict |
| --- | --- | --- | --- |
| **Andromeda cargo hold** (user's tip) | int 9, 315.48, 984.13, 1959.11 – models 14548 `cargo_test` (hull, 10.2 × 74.6 × 21.7 m), 14550 `cargo_netting`, 14551 `cargo_store`, 14552 `cargo_stuff` | from the given point: floor z 1958.11, ceiling 1962.24 (4.1 m), walls x 311.06 / 320.58 (9.5 m), but the walkable part is a ~2.5 m aisle between two walls of CCT containers with rails on the floor, ~60 m long, **no windows** | Fits a **luggage / mail van** or a freight car. Not a passenger coach: no seats, no windows, a 60 m tube inside a 21 m car. |
| **Shamal cabin** `jet_interior` (14404) + `chairs` (14405) | int 1, around 1.81, 32.38, 1199.6 | inner width 3.3 m (x 0.23 – 3.39), height 3.5 m (floor 1198.6, ceiling 1202.1), length ~14.6 m (rear wall y 22.2, cockpit door y 36.8); 10 leather seats 2+2 / 1+1, side door on the right near the front, toilet door at the rear, **real window recesses on both sides** | **Chosen for the passenger coach.** Proportions are close to a real coach (UIC coach: 2.8 m wide inside, 2.6 m high; 14.6 m is shorter than 20.9 m, which nobody notices inside). |
| Own map from stock objects | any interior, object dimension -1 | – | Fallback only (see 1.3). |

Both GTA interiors are part of the static map, so they exist in **every dimension** by
themselves – exactly the requirement. Nothing has to be created per coach for the shell.

### 1.1 Why the Shamal cabin

* It is the only stock interior with a long narrow tube shape, seats along an aisle **and**
  windows on both sides.
* The windows are not geometry holes: the white oval panes are painted into the wall texture
  **`mp_jet_wall`** (material list of `jet_interior.dff` from gta_int.img: `mp_bobbie_carpwhite`,
  `mp_shop_floor2`, `mp_jet_wall`, `mp_jet_roof`, `mp_cj_wood5`, `mp_jet_cockpit`, `ld_747_floor`,
  `ld_747_skin`, `ld_747_door`, `ld_747_toiletdoor`, `ld_747_cockpitdoor`; seats `mp_jet_seat`).
  A shader on `mp_jet_wall` can replace the panes with our outside view (section 4). That is
  much better than gluing dx quads in front of the wall.
* The aeroplane look is removed with small changes:
  * the cockpit is hidden: a client-side door object closes the cockpit doorway (y ≈ 36.8;
    `ld_747_cockpitdoor` is only the frame), with a Sunline Rail passenger information display
    on it (section 5);
  * the jet seats stay (they look like 1st class seats); the "1st class" label fits;
  * optional retexture of `mp_jet_roof` / `mp_cj_wood5` to a Sunline Rail look (blue / grey),
    only while the local player is inside a coach – the real Shamal interior stays untouched
    for everyone else (shaders are local and only active in a coach).

### 1.2 Andromeda for later

The Andromeda hold is kept for a future **luggage / mail van** (`rw_core` vehicle kind `van`):
same boarding mechanics, interior = int 9, no window system. It is not part of the first build.

### 1.3 Fallback: own map

If the Shamal look is rejected: build the coach from stock objects in an unused interior id
(e.g. int 18 at a remote position), objects in **dimension -1** (all dimensions), created
client-side from `data/interior_custom.json`. Requirements on the pieces: flat wall / floor /
roof pieces that can be retextured with shaders, `ab_jetseat` (1562) or `airseata_LAS` (3657)
seats, window frames as dx-drawn quads. Same boarding / window code, only the interior
definition changes (section 2.3 keeps the interior as data).

## 2. Concepts

### 2.1 Coach id = dimension

* Every passenger coach of a train gets a **coach id** when it spawns; the coach id **is** the
  dimension its interior lives in.
* Range: `RWP.DIM_BASE + 1 … RWP.DIM_BASE + RWP.DIM_COUNT`, default **30001 – 39999**. Dimension
  0 is never used. Other resources already use 42000+ (work_ems tutorial) and 43000+
  (v_introduce); the railway range stays clear of them. (If plain 1…N is preferred, set
  `DIM_BASE = 0` – but then the coaches share dimensions with test trains and other systems that
  use low dimensions.)
* Allocation: lowest free id, freed when the coach's train is removed. Mirrored to the coach
  vehicle as element data `rwp.coach` (= dimension) so clients and other resources can map in
  both directions. Server exports `getCoachByDimension(dim) -> trainId, carIndex, vehicle` and
  `getCoachDimension(vehicle)`.

### 2.2 Passenger state (server)

```
Passengers[player] = { coach = dim, train = id, car = k,
                       back = { x, y, z, rz } }      -- where they boarded (fallback exit)
Coaches[dim]       = { train = id, car = k, vehicle = el, anchors = {...}, exitAnchor = obj,
                       count = n }
```

Passengers are **not** attached to the car any more (the current `rw_customtracks` riders
`addNetTrainRider` + camera on the car stay for `/rwtrain ride` debugging only).

### 2.3 Interior definition (data, `shared/interiors.lua`)

The interior is data (`RWP.INTERIORS.coach`): interior id, floor / walls / ends, spawn point,
exit anchor, cockpit blocker objects, info display rectangle, window texture + pane mask
parameters. Measured in phase 0 – values and how they were found in section 10.

## 3. Boarding and leaving

### 3.1 Outside: door anchors on the coach

Same technique as `rw_loco/server/cab.lua`: invisible, non-colliding anchor objects (model 1319,
alpha 0) **attached to each coach** at its door positions – model 570 has **one door per side, in
the middle of the car**, so 2 anchors per coach (`RWP.COACH_DOORS`, vehicle-local offsets). One ui_interactobject menu per anchor:

```
Sunline Rail · Coach 2 (SL3 IC to Unity)
  [1] Board the train          desc: "12 / 20 on board"
```

* The anchors inherit the coach's dimension (0 for normal trains, the test dimension for test
  trains); the menus are registered 600 ms after the objects (client delivery, as in cab.lua).
* **A door can be used only when all of these hold** (decided by the user):
  1. the train stands: network train speed `|v| < RWP.STAND_SPEED` (0.2 m/s) for at least
     `RWP.STAND_TIME` (1 s);
  2. it stands at a station platform;
  3. the doors are released on that side: `rw.doors` of the lead is that side or `"both"`.

  Point 2 needs no extra check: `rw_loco` only releases the doors when
  `rw_timetable:canOpenDoors` allows it (standing inside a station zone), `rw_auto` uses the same
  rule, and the doors close by themselves once the train moves. So **released doors already
  mean "standing at a station"**. The standing check stays as a safety net for the moment the
  train starts and the server has not closed the doors yet.
* The door state per anchor = (lead's `rw.doors`, the coach's side). `rw.doors` left / right are
  relative to the **lead's** direction; a coach flipped against the lead (`car.flip`) has its
  anchor sides mirrored, so every anchor is mapped to the train's left / right once when the
  anchors are created.
* Enabling: rw_passengers listens to `onElementDataChange` for `rw.doors` on the leads (no timer
  needed for the door state) plus a 250 ms timer per train with coaches for the standing check.
  Only the anchors on the released side are enabled (`setInteractMenuEnabled`); the others stay
  disabled with desc "Doors closed". The server re-checks all three conditions on selection
  anyway (the client may be late).

### 3.2 Boarding sequence (server, on `onInteractMenuSelect`)

1. Validate: menu belongs to a coach anchor, player on foot, alive, not already a passenger, not
   in another blocking state, door usable (3.1: standing, doors released on the anchor's side),
   coach not full (`RWP.CAPACITY`).
2. `triggerEvent("onPlayerBoardTrain", player, trainId, carIndex, dim)` – **cancellable**; the
   future ticket system / conductor hooks in here (`wasEventCancelled` → refused with a reason
   set by the canceller).
3. Client fade out (300 ms), then server: remember `back`, set element data `save.position` to a
   safe outside point (v_accounts saves that instead of the interior position – a player who
   quits inside never logs in inside an empty Shamal), `setElementInterior(1)`,
   `setElementDimension(dim)`, position at `spawn`, facing inside, fade in.
4. Element data `rwp.ride = { dim, trainId, car }` (synced) for the clients: window renderer,
   info display, sounds.
5. `triggerEvent("onPlayerBoardedTrain", player, trainId, carIndex, dim)`.

### 3.3 Inside: leaving

* One exit anchor per **occupied** coach dimension, created on the first boarding and destroyed
  when the coach is empty: object in int 1, dimension = coach id, at the cabin's side door. Menu:
  `Leave the train`, enabled only while the doors are released (same conditions as 3.1), desc
  "Doors closed" / "Next stop: Market" / "Doors open – right side".
* There is a single cabin door inside, so the exit is not tied to a side inside: the player
  leaves through the **released side** (with `"both"` the platform side from
  `canOpenDoors`).
* Leaving sequence: validate (standing + doors released) → fade → exit point →
  `setElementInterior(0)`, `setElementDimension(coach vehicle's dimension)`, position, clear
  `save.position` and `rwp.ride`, fire `onPlayerLeftTrain`.
* **Exit point:** beside the coach (not the cab), in front of its middle door (y = 0), 2.8 m out, on the released (= platform) side. The point is computed by an `rw_core` export
  `getTrainSidePoint(vehicle, offsetY, lateral, side)` (taken from `rw_loco` `exitSide`, so cab
  and coaches share it). z from the rail height + 1.2 (as `rw_customtracks` dropPlayer), then a
  client ground check; if the platform is higher, the client snaps up (`getGroundPosition`
  from +3 m).
* The "side without a neighbouring track" rule is only used by the forced exits (3.5), when the
  train is not at a platform.

### 3.4 Inside the coach

* **Players move freely in the cabin** (user's decision): no seat system, no sit menus, no
  control locks, no forced animations – what they do inside is up to them. The jet seats are
  scenery; players may use whatever the game / other resources allow.
* Vehicles cannot be brought in (boarding requires on foot).
* Players in the same coach see each other (same interior + dimension); other coaches are
  other dimensions.
* Sounds (client, 2D): running loop + clacks scaled by the coach's speed (reuse
  `rw_customtracks/sounds`), door chime on doors release / close, brake squeal when
  decelerating hard, station announcement chime.

### 3.5 Forced exits (the coach disappears)

| Case | Handling |
| --- | --- |
| Train completes its service, rw_timetable retires it (standing, 10 s later) | Announce "Terminus – please leave the train" at arrival; on removal everyone left inside is put on the platform side (normal exit path). |
| Train removed while moving (admin, crash, resource restart) | Exit point = beside the coach's last known position, side without track; message "The train was taken out of service". |
| Train stands at a station but the driver never releases the doors | Passengers wait inside (realistic); the info display shows "Doors closed". When the train is retired / despawned they are put out like above. |
| Player dies inside | Clean state; respawn handled by the usual system (medsys: players have no clinical death). |
| Player quits inside | `save.position` already points outside (3.2 step 3). State cleaned on `onPlayerQuit`. |
| Something else changes the player's interior / dimension (admin teleport, other resource) | `onElementDimensionChange` / interior check → state cleaned silently, no teleport. |
| rw_passengers stops | Everyone inside is put outside beside their coach (or `back`) before the state is lost. |

Train removal is detected via the existing `rw_core` destroy path (`destroyConsist` logs a
reason) – a new event `onRailConsistDestroy(consistId, reason)` fired *before* the vehicles
are destroyed, so the exit points can still be computed from the coach elements.

## 4. Windows

Goal: looking through a window shows what is outside the real coach – moving with the train,
the right side of the line, the right time of day and weather, with true parallax when the
player walks or turns.

### 4.1 What is not possible

MTA renders the world once per frame from one camera; there is no second camera / portal
render target, and the world is not even streamed around the moving train while the player
stands in interior 1 far away. A literal live view is therefore impossible. Moving the player's
camera to the real train would lose the interior.

### 4.2 Chosen approach: shader windows with layered parallax scenery

```
           coach state (rw_customtracks snapshot, interpolated every frame)
                │  position on the line, speed, heading, flip, world x / y
                ▼
  scenery lookup (data/scenery.json): environment class per line stretch and side,
  tunnel / bridge / station flags
                │
                ▼
  per-frame render target "outside" ── layers: sky ▸ far ▸ mid ▸ near ▸ overlays
                │
                ▼
  shader on `mp_jet_wall` (only while inside a coach): pane pixels → ray through the window →
  sample the layers at the right depth = parallax; other pixels → original wall texture
```

**1. Pane mask.** The panes are the bright, low-saturation areas of `mp_jet_wall`. At client
start the texture is read once (`engineGetModelTextures(14404)` → `dxGetTexturePixels`) and a
mask texture (pane = 1, frame = 0, soft 1–2 px edge) is generated and cached. The pixel shader
samples the original texture and the mask with the same UV; mask 0 → original colour.

**2. Ray through the window.** In the vertex shader the world position of every wall vertex is
passed on; in the pixel shader `ray = normalize(worldPos - cameraPos)`. With the cabin's known
orientation the ray is turned into coach-local coordinates: `side` (left / right wall from
`worldPos.x` against the cabin centre line), along-coach direction, up.

**3. Layers at fixed lateral distances.** Outside is modelled as vertical "curtains" parallel to
the track on each side:

| Layer | Distance from the window | Content |
| --- | --- | --- |
| near | 3–4 m | catenary-less line-side clutter: posts, fences, signal heads, platform edge, tunnel wall with lamps |
| mid | 25 m | trees, houses, warehouses, rocks – class dependent |
| far | 250 m | skyline / hills / desert ridges / sea horizon – class dependent |
| sky | ∞ | `getSkyGradient` top / bottom colours, sun / moon glow in its direction |

For layer `i` at distance `D_i` the ray hits the curtain at
`along = localPos.y + ray.y * (D_i - wallDist) / |ray.x|` and `height = localPos.z + ray.z * t`.
Texture coordinate `u = (coachPos + along) / layerPeriod_i`, `v` from the height. Near over mid
over far over sky with alpha. Because `coachPos` is the real distance along the line (in
metres), the layers scroll at exactly the train's speed – the near layer flies past, the far
layer barely moves, which is what sells the effect. Walking along the aisle changes the angles,
so the view shifts correctly (parallax), not like a flat video.

**4. Environment classes.** Layer textures come in sets: `ls_city`, `ls_industrial`,
`ls_suburb`, `countryside`, `forest`, `desert`, `lv_city`, `sf_city`, `sf_docks`, `coast`
(water + far shore), `bridge` (near layer empty, mid = water / valley far below, horizon lower),
`tunnel` (near = concrete wall with passing lamps at 25 m spacing, no mid / far / sky), `yard`.
`data/scenery.json` lists per line and side: `{ seg, from, to, left, right, flags }`. On a class
change the shader blends old → new set over ~40 m (two texture sets bound, blend factor).

* **Generating scenery.json:** a tool (`tools/scan_scenery.js`) walks both lines every 20 m with
  the MCP: the cached surface maps (`surface_map.*.20m`) and zone names give the class per side
  (sample 15 / 60 / 200 m out); a raycast up gives tunnels (roof within 10 m), a raycast down
  gives bridges (ground or water > 8 m below the rail). Results are merged into stretches, then
  corrected by hand (it is plain JSON).
* **Layer textures:** captured in the game with the MCP (`capture_view`, side view from window
  height, daylight, HUD hidden) at 2–3 typical spots per class, converted into tileable strips
  (mid / far: horizontal tiling, near: sprite sheets of posts / fences scattered by a
  deterministic hash of `coachPos`, so the same post is always at the same place). ~12 classes ×
  3 layers × 1024 × 256 DXT → a few MB, downloaded once.

**5. Stations.** When the coach stands at (or slowly runs into) a station platform
(`rw_timetable` station zones + the platform side), the near / mid layers are replaced by a
**captured still of that platform** (one per station and side, 5 stations × 2 sides), placed at
the right along-position, so passengers see the real platform, the station sign and the wall
display position. It slides in / out with the train like any layer.

**6. Time of day, weather, lights.**
* sky from `getSkyGradient`, layers tinted by the current ambient (time + weather: rain makes
  it grey, fog cuts the far layer).
* night: layers dark, emissive masks (lit windows in city sets, street lamps, station lights)
  stay bright; interior reflection on the glass increases (Fresnel: the pane shows a faint dark
  mirror image of the cabin colour).
* rain: animated streak texture on the pane, slanted by speed.
* tunnel: everything except the near tunnel wall drops out, the cabin lights become the main
  light source (shader darkens the pane to black-blue).

**7. Speed effects.** Motion blur on the near layer only: 3–5 taps along `u` scaled by speed.
Above ~80 km/h the near posts become streaks, like real.

**8. Coach orientation.** The cabin's +y is mapped to the coach vehicle's own front (car `flip`
taken into account). If the train runs backwards relative to that, the scenery runs the other
way – correct, because passengers see the real direction. Left / right windows show the left /
right side of the real coach.

**9. Cost.** One render target (or none: the layers are sampled directly in the wall shader;
the render target is only needed if the near-layer sprites are drawn by Lua) and one shader
applied to one world texture, only while the local player is in a coach; outside a coach
nothing runs. The coach state comes from the `rw_customtracks` snapshot that every client
already receives; a new client export `netGetCarState(trainId, car) -> { u, v, x, y, z,
heading, flip, seg, s }` exposes it.

### 4.3 Rejected alternatives

* **Pre-captured continuous route strips** (a picture every 25 m along both sides of every
  line): looks real, but ~2 000 images (tens of MB) and no parallax – the near and far scenery
  move together, which reads as "video". Only the station stills (4.2 point 5) use this idea.
* **Purely procedural generic scenery** without classes: cheap, but the desert would show in
  Los Santos. The class table costs little and keeps it believable.
* **dx quads in front of the windows**: misaligned with the oval panes and the curved wall,
  breaks the moment the player comes close. The shader uses the real panes.

## 5. Passenger information

* **Info display** on the new cockpit door (dx render target, `dxDrawMaterialLine3D`, style of
  the station displays): line + destination, next stop + expected time (planned + delay),
  current speed, clock. Data: `rw_timetable:getConsistService(trainId)` (server → client every
  5 s for the coaches with passengers, plus on stop events).
* **Announcements** (English UI text, chime + 2D text banner, no chat spam): "Next stop: Market
  Station", "Market Station – doors on the left", "Terminus – please leave the train".
  Triggered by `onRailServiceStop` and an approach distance (stop position − 600 m).
* **Outside**, the 3D train label (rw_core trainlabel) and the door anchors' menu title show the
  service, so people on the platform know which train to board.

## 6. Interfaces

Server exports:

```
getCoachByDimension(dim)               -> trainId, carIndex, vehicle | false
getCoachDimension(vehicle)             -> dim | false
getPassengers(trainId [, carIndex])    -> { player, ... }
getPlayerRide(player)                  -> { train, car, coach } | false
removePassenger(player [, reason])     -> bool  (exit beside the coach, standing not required)
setBoardingLocked(trainId, bool [, reason])   -- e.g. empty stock runs / depot moves
```

Events (server): `onPlayerBoardTrain` (cancellable), `onPlayerBoardedTrain`,
`onPlayerLeftTrain(trainId, car, reason)`.

Client exports: `isInTrain()`, `getMyRide()`.

New things needed from other resources:

| Resource | Addition |
| --- | --- |
| rw_core | `onRailConsistDestroy(consistId, reason)` before the vehicles go; `getTrainSidePoint` helper (from rw_loco `exitSide`); coach id allocation hooked into `spawnConsist` (or rw_passengers listens to the consist spawn and allocates itself – preferred, keeps rw_core free of passenger logic) |
| rw_customtracks | client export `netGetCarState`; train speed already in `getNetTrain` |
| rw_timetable | nothing new (`canOpenDoors`, `getConsistService`, service events exist) |
| rw_loco | uses the shared `getTrainSidePoint` |
| rw_auto | stock runs (no service) → `setBoardingLocked` |
| v_accounts | nothing (uses existing `save.position`) |

## 7. Config (`shared/config.lua`)

Created in phase 0: dimension range, standing check, capacity (30), anchor model / range, the
coach door offsets and the exit distance, fade, announcement distance, window options.

## 8. Phases

0. **Measure** – done 2026-10-04, see section 10 (MCP, few screenshots): exact cabin origin / spawn / exit door / cockpit
   doorway; coach door offsets on model 570; whether a client-side door
   object closes the cockpit doorway cleanly; confirm `mp_jet_wall` is used only by the Shamal
   cabin (the shader is local and only active in a coach anyway). Output: `shared/interiors.lua`.
1. **Boarding core**: coach id allocation, outside anchors (enable / disable on standing),
   board / leave with fade, `save.position`, forced exits, events + exports. Test with two
   clients (drandrew112 + Laptop112) on a depot train in the test dimension.
2. **Inside**: exit anchor, sounds, info display, announcements.
3. **Windows**: pane mask, shader with sky + one class (countryside) + near posts → check the
   parallax in game (1–2 screenshots); then the scenery scan tool + class textures + station
   stills + night / weather / tunnel.
4. **Polish**: luggage van on the Andromeda hold (1.2), tickets / conductor hooks
   for the future work_traindriver.

## 9. Decisions (user, 2026-10-04)

1. **Interior:** Shamal cabin as described – the passenger information display closes the
   cockpit, windows by the shader (section 4). Andromeda stays the idea for a later luggage van.
2. **Dimensions:** 30001–39999 (`DIM_BASE = 30000`).
3. **Doors:** boarding and leaving need the doors released on that side, not only a standing
   train (3.1).
4. **Stations only:** doors can only be used at a station stop. This needs no own check –
   doors are only released at a platform, so it follows from 3.
5. **Free movement inside:** players move freely in the cabin; no seats, control locks or
   animations from rw_passengers (3.4).

## 10. Phase 0 results (2026-10-04, live with the MTA World MCP)

**Shamal cabin** – GTA object `jet_interior` (14404) at **1.719, 30.406, 1200.344**, rotation 0,
interior 1 (found from a raycast's world model). Everything below in world coordinates:

| What | Value | How |
| --- | --- | --- |
| floor | z 1198.594 | ray down |
| side walls | x 0.05 / 3.40 (centre line x 1.73) | rays across at y 33.1 |
| rear wall | y 22.242 | ray along the aisle |
| cockpit door frame | y 34.359 (cabin side face) | rays at three points |
| cockpit doorway | opening x 1.1 – 2.3, z 1198.6 – ~1201.1 (1.2 × 2.5 m) | 16 × 14 ray grid through the frame plane |
| spawn | 2.3, 33.1, 1199.6, rz 180 (inside the side door, facing the cabin) | rays in 4 directions: free |
| exit anchor | 3.2, 33.1, 1199.6 – side door recess (`ld_747_door` x 2.76 – 3.42, y 31.88 – 34.36 from the DFF + placement) | DFF material extents |
| cockpit blocker | `ab_casdorLok` (3089), 1.5 × 2.7 m, thin: at 0.21, 34.32, 1199.90, rz 0 → covers x 0.95 – 2.45, z 1198.59 – 1201.29 | spawned as a test object; rays stop on it at y 34.29 (collision OK). **Look not checked**: the game window was minimized, no screenshot possible. The `Gen_door*` models (1491 …) are the alternative (1.5 × 2.5 m, pivot at the hinge). |
| info display | on the door, cabin side: centre 1.70, 34.27, 1200.35, 1.10 × 0.62 m, facing -y | from the door placement |

* Other objects inside: a wooden cabinet on the left at the front (rays stop at y 31.9 on
  x 0.5), seats on the right side towards the rear (stop at y 24.0 on x 2.3); the aisle is free
  from the door to the rear wall. The cockpit holds a separate `chairs` object (14405).

**Window texture** – `mp_jet_wall` (256 × 256) is used **only** by `jet_interior.dff`
(scanned every DFF in gta3.img + gta_int.img), so a shader on it cannot leak elsewhere.
`engineGetModelTextures(14404)` returns it on the client and `dxGetTexturePixels` reads it, so
the pane mask can be built at runtime. The texture holds two windows side by side; panes at
pixel rects **38–74 × 97–147** and **168–204 × 97–147** (37 × 51 px, ~1 620 pane pixels each,
oval), pane colour ≈ (252, 255, 255), wooden frame ≈ (165, 134, 107). Mask rule: luminance > 200
and max − min < 40 → pane. Texture names in the TXD: `LD_747_skin`, `mp_CJ_WOOD5`,
`mp_jet_cockpit`, `mp_jet_roof`, `mp_jet_wall`, `mp_bobbie_carpwhite`, `LD_747_toiletdoor`,
`LD_747_cockpitdoor`, `mp_jet_seat`, `LD_747_door`, `LD_747_floor`, `mp_shop_floor2`.

**Passenger coach (model 570)** – measured on a standing re4 train at Linden: body half width
**1.74 m** (rays from both sides at door height), car centre 2.595 m above the rail. One side
view screenshot: **one door per side, in the middle of the car** (y ≈ 0), about 1 – 3 m above
the rail. Anchors: x ±1.9, y 0, z −0.6 relative to the car centre.

Still open for phase 1: one screenshot of the cockpit door from the aisle (needs the MTA window
not minimized) to confirm the look of `ab_casdorLok`.

## 11. Implementation (2026-10-04)

Files: `shared/config.lua`, `shared/interiors.lua` (phase 0 data), `server/coaches.lua` (coach
ids, door anchors, door state, exit anchor), `server/passengers.lua` (board / leave / forced
exits, ride state push, exports), `client/cabin.lua` (cockpit double door, ground snap after
leaving, notifications), `client/ride.lua` (smoothed speed, distance travelled, server clock),
`client/sounds.lua`, `client/display.lua` (info display + announcements), `client/scenery.lua`
(classes + layer textures), `client/windows.lua` + `shaders/windows.fx` (window shader),
`tools/gen_sounds.js` → `sounds/chime.wav`.

Differences from the plan:

* **Ride state** comes from the server every 500 ms (`rwp:state`: speed along the coach's front,
  position, doors seen from the coach, the `rw.service` view); the client smooths the speed and
  integrates the distance. No `rw_customtracks` client export was needed.
* **Environment classes** are looked up from the coach's real position by GTA zone / city
  (`Scenery.ZONES`, `Scenery.CITIES`) plus optional world boxes (`Scenery.BOXES`, for tunnels and
  covered stretches – empty so far). The MCP scan tool (`scan_scenery.js`) was not built: the
  user asked for no more MCP work. Market Station = underground (tunnel + platform), Cranberry
  = hall, the other stations = open platform.
* **Layer textures** are painted procedurally on the client (skylines, houses, palms, pines,
  hills, mesas, cacti, poles, platforms) and cached as textures. A captured picture can replace
  any layer: `textures/<class>_<far|mid|near>.png` + a `<file>` line in meta.xml.
* **Pane mask** is computed in the shader from the texel colour (luminance > 0.7–0.8, saturation
  < 0.06–0.12) instead of a generated mask texture – same rule as measured in phase 0.
* **Exit point** helper stays inside rw_passengers (`outsidePoint`); rw_loco keeps its own
  `exitSide`. `onRailConsistDestroy` already existed in rw_core (fired before the vehicles go).
* Quitting inside: `save.position` (the boarding point) is left on the player so v_accounts
  saves the outside position.
* `debugCoachMenus(vehicle)` export for tests.

Verified live: the resource starts without errors, coaches get dimensions (30001…), the door
anchors' menus are enabled only on the released side (Market Station, doors right: right
anchor usable, left "Doors closed on this side"). The shader compiles with fxc (fx_2_0 / SM3).
Not tested in game: the boarding / leaving flow, the cabin, the display, the sounds and the
window look – the user tests them manually.
