# v_els

Emergency lights and sirens for the models in `sirenVehicles` (`shared/config.lua`).

## Driver keys

| Key | Action |
| --- | --- |
| 0 | Lights on/off (`mkjState`) |
| 1 | Siren on/off (starts with the first tone) |
| 2 | Next siren tone |
| 3 | Air horn (hold) |
| 4 | Next flash pattern (`elsPattern`) |

Siren sound commands: `/stfs`, `/stso`, `/strtk`, `/rumbler`, `/stitaly`, `/eriston`, `/dal`. Debug overlay: `/debugels`.

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
