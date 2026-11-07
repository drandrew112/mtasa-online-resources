# v_anims

Animation database + `/anims` panel + F9 animation wheel.

## Database

`shared/database.lua` is **generated**: edit the list in `tools/build_database.py`, then run

    python tools/build_database.py ["C:/Games/GTA San Andreas/anim/"]

The tool reads the GTA IFP files (`anim/ped.ifp` + every IFP in `anim/anim.img`), checks that every
name exists and refuses any non-dive animation whose root bone travels more than 0.8 m (walks,
runs, jumps). Only the `dive` category (`/dive`, `/roll`) moves the player (updatePosition).

- Group = command: `/sit` = `sit_1`, `/sit 3` = `sit_3`. `/anim <cmd|id> [n]`, `/anim stop`, `/stopanim`.
- Flags: `l` loop (default), `o` once, `h` holds the last frame, `m` moves the player.
  Optional intro (played when starting from a normal stance) and outro (played on stop).
- Labels: v_locals `v_anims.group.<cmd>` (+ number when the group has more), categories `v_anims.cat.<id>`.
  Adding a group needs its label in `[core]/v_locals/locales/{en,hu}/v_anims.json`.

## Player UI

- `/anims`: categories, search (label, command, id, block/name), star = favourite (max 8),
  footer = the 8 wheel slots (left click play, right click remove).
- F9 hold: wheel of the favourites (slot 1 on top, clockwise), release on a slot = play,
  release in the centre = nothing. F9 tap (< 200 ms) = stop.
- Favourites: accData `anims.favourites` (JSON array, wheel order).

## Blocking

No animation when dead, in a vehicle, attached, in water, in the air, with a jetpack, or while
element data `pol.cuffed`, `wp.stunned` or `medfx.anim` is set (the animation stops when one appears).
Other systems: `exports.v_anims:setAnimsBlocked(player, "<key>", true/false)`.

## Exports

Server: `playAnim(player, id[, quiet])`, `stopAnim(player[, instant])`, `getPlayerAnim(player)`,
`setAnimsBlocked(player, key, state)`, `getAnimList()`, `getPlayerFavouriteAnims(player)`,
`setPlayerFavouriteAnims(player, list)`. Events `onPlayerAnimStart(id)`, `onPlayerAnimStop(id, reason)`.

Client: `playAnim(id)`, `stopAnim()`, `getCurrentAnim()`, `getFavouriteAnims()`, `getAnimLabel(id)`,
`openAnimPanel()`, `closeAnimPanel()`, `isAnimPanelOpen()`. Local element data `animPanelOpen`.

Synced element data `v_anims.cur` = playing id.

## Tests

    python tests/run.py   (lupa: syntax of every script + server logic with MTA stubs)
