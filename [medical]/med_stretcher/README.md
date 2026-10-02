# med_stretcher

Ambulance stretcher for patient transport, together with `medical_system` and the future `work_ems`.
Every ambulance (`STRETCHER.VEHICLE_MODELS`: 416, 456) gets its own stretcher object (model 2146). The object is scaled on
every client so its longest side is `STRETCHER.TARGET_LENGTH` metres. While the stretcher is not
in use, it is attached inside the vehicle, invisible and without collisions.

## Interaction (ui_interactobject, `X` + number keys)

There is only one menu, on the stretcher object. While the stretcher is inside the ambulance, you
reach that menu at the rear of the ambulance: the hidden object is parked at `STOWED_MENU_POINT`
(the rear doors), not at its real cargo position. Each client then moves it onto the model's real rear
doors (rear door dummies, or the back of the bounding box).

| state | options |
|---|---|
| inside the ambulance | **Take out stretcher**: stand at the rear doors (`REAR_POINT`) |
| on the ground | **Push**, **Place patient** / **Take patient off**, **Load into ambulance** |
| pushed (only the pusher sees it) | **Release**, **Load into ambulance** |
| sliding in / out | none (the menu is disabled) |

- **Take out**:
  1. The rear doors open and the ambulance is frozen.
  2. The stretcher slides out with `moveObject`, `STOW_OFFSET` → `EDGE_OFFSET`, then lowers to `OUT_OFFSET`.
  3. The doors close. The client of the player who took it out snaps the stretcher to the real ground height.

  A patient who was loaded with it rides out on it.
- **Load**:
  - The stretcher must be inside the narrow load zone behind the ambulance (`LOAD_ZONE_CENTER` /
    `LOAD_ZONE_WIDTH` / `LOAD_ZONE_LENGTH`) and point into the ambulance: its yaw within
    `LOAD_ZONE_MAX_ANGLE` (30°) of the stowed direction.
    While pushing, the pusher sees the zone on the ground (client/zone.lua): white = outside,
    orange = inside but turned wrong, green = can be loaded.
  - The doors open, the stretcher lines up, then it is lifted to the rear edge and slides in.
  - The patient is warped onto a free rear seat (`REAR_SEATS`), and the doors close.
  - A player patient cannot get out (`onVehicleStartExit` is cancelled) and cannot be jacked.
- **Push**:
  - The stretcher is attached in front of the medic with collisions off.
  - The medic walks with GTA's normal movement. It is forced to walk speed unless the sprint key is held
    (sprinting is allowed) and synced natively; jump and weapons are locked.
  - While the medic stands still, every client plays `PUSH_IDLE_ANIM` locally (arms forward).
  - The medic's own client drops this pose as soon as a movement key is pressed.
- **Place patient**: opens the patient selector (`client/select.lua`).
  - The cursor appears, and every ped or player within `PATIENT_RANGE` of the stretcher gets a round
    button above the head. Injured people's buttons are red.
  - Clicking a button selects that person, and the server re-checks the pick (`isPatientCandidate`).
  - `RMB` hides or shows the cursor, so you can turn. `Backspace` cancels.
  - The selection also ends if you move more than `SELECT_MAX_DISTANCE` away.

  Anyone can be a patient. The patient is attached to the stretcher and plays `PATIENT_ANIM`.
- The patient cannot use their own stretcher's menu.

## Lifecycle

- Ambulances are found when the resource starts. New ones are found through an `addDebugHook` on
  `createVehicle`/`setElementModel`, which needs the ACL right, and a fallback scan every
  `SCAN_INTERVAL` ms. MTA has no server-side `onVehicleCreate` event. `onElementModelChange` is handled too.
- Exploding or destroying the vehicle destroys its stretcher; the patient is taken off first and the
  pusher is released. `onVehicleRespawn` creates a new one.
- If the pusher dies or quits, they let go of the stretcher. A dead patient stays on the stretcher until respawn.
- If `medical_system` plays its down / get-up animation on a patient who is on the stretcher, the lying
  animation is played again.

## Tuning

`shared/config.lua`: all offsets are `{ x, y, z, rx, ry, rz }` in the parent's local space. The stretcher's
long side lies along the model's y axis (`rz = 0`). The in/out path is `STOW_OFFSET` / `EDGE_OFFSET` / `OUT_OFFSET`,
with timings `DOOR_TIME` / `ALIGN_TIME` / `SLIDE_TIME` / `LOWER_TIME`. `MODEL_Y_SHIFT` moves all of these
(and `STOWED_MENU_POINT` / `REAR_POINT`) back or forward per ambulance model.
Set `SELF_DATA_KEY` (e.g. `"isMedic"`) to show the menus only to medics.

## Medic role

With medsys `MEDIC.REQUIRE_MEDIC_ROLE = true` the stretcher menus are visible only to players with the
medsys medic role (`exports.medsys:setPlayerMedic`), and every selection is checked again on the server.
The setting is asked from medsys once (again only when medsys restarts); visibility follows
`onPlayerMedicChange`. A pusher who loses the role puts the stretcher down.

## Server exports

```lua
exports.med_stretcher:getVehicleStretcher(vehicle)  -- object | false
exports.med_stretcher:getStretcherVehicle(stretcher)
exports.med_stretcher:getStretcherState(stretcher)  -- "stowed" | "ground" | "pushing"
exports.med_stretcher:getStretcherPatient(stretcher) -- lying on it, or seated in its ambulance
exports.med_stretcher:getPatientStretcher(ped)
exports.med_stretcher:takePatientOff(stretcher)     -- detaches the lying patient, returns them
```

Element data: `stretcher.state` (`stowed`/`moving`/`ground`/`pushing`), `stretcher.vehicle`, `stretcher.patient` (on the object),
`stretcher.on` (on the patient), `stretcher.pushing` (on the medic), `stretcher.locked` (on the seated patient).
