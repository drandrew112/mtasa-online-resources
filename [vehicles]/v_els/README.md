# v_els

Emergency lights and sirens for the models in `sirenVehicles` (`shared/config.lua`).

## Driver keys

| Key | Action |
| --- | --- |
| 0 | Lights on/off (`mkjState`) |
| 1 | Siren on/off (starts with the first tone) |
| 2 | Next siren tone |
| 3 | Air horn (hold) |
| 4 | Secondary siren tone on/off (`sirenSecondary`), only while the main siren is on |
| 5 | Next flash pattern (`elsPattern`) |

Siren sound commands: `/stfs`, `/stso`, `/strtk`, `/rumbler`, `/stitaly`, `/eriston`, `/dal`, `/code3`. Debug overlay: `/debugels`.

Each model gets its default siren type from `sirenVehicles` (a `sirenTypes` key, or `true` for `DEFAULT_SIREN_TYPE`). The default is only applied to a vehicle that has no valid type yet; a type already set is never overwritten. The commands above change it per vehicle.

Every siren type can have a `secondary` tone (`false` = none) that plays on top of the main siren. It can only be turned on while the main siren is on, turns off with it, and pauses while the horn is held. Only `fsvas320` has one for now (its third tone).

Every siren type can set a `volume` multiplier (default 1.0) on top of the base siren/horn volume, to even out sound sets that are too loud or too quiet; `hornVolume` overrides it for the horn only. `code3_z3` uses 0.6.

`intro = { [index] = path }` plays that file once from the start, then hands over to the looping `sirens[index]`, which must be the intro's tail (cut out of it). Both start together, the loop runs muted in sync and a short crossfade switches over, so there is no jump. `dal` uses it on its 2nd tone (`2.wav` intro, `2_loop.wav` = from 0.5 s).

## Lights

- Each model's light points live in `lights.json`, which only the server reads and writes. Clients get the points from the server.
- The client draws the lights as corona sprites. They don't vanish near the bodywork, there is no 8-point limit, and the rhythm comes from `ELS_PATTERNS`.
- Every point belongs to a group (A-D). A pattern sets per group when the lights are on, at `step` ms per character.
- A model without a layout keeps the old GTA siren lights. The GTA siren sound is always muted.
- **Environment lighting:** the `dynamic_lighting` resource provides point lights. The nearest `ELS_ENV.maxVehicles` vehicles each get `ELS_ENV.perVehicle` lights, which flash in the same phase as the beacons.

## /elseditor

Requires `admin_level >= ELS_ADMIN_LEVEL`. Run it as the driver of an ELS vehicle. You edit a local copy, and only **Save** sends it to the server, where it applies to every vehicle of that model.

| Key | Action |
| --- | --- |
| Arrows | Move point X / Y (Shift = fine) |
| PgUp / PgDn | Move point Z |
| [ / ] | Previous / next point |
| N / M | New point / mirrored copy (A<->B, C<->D) |
| Delete | Delete point |
| C / G | Cycle color / group |
| + / - | Size |
| P | Preview: steady / patterns |
| E | Menu (colors, custom RGB, groups, sizes, save, exit) |
