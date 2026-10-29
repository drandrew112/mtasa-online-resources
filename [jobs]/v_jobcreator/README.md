# v_jobcreator

In-game creator for v_jobmanager games (race, deathmatch and mission). It produces the
v_jobmanager game data. Every game is stored by v_jobmanager in MySQL
(`core/storage.lua`: `jobs_draft`, `jobs_community`, `jobs_official`).

## Entering

- `/creator [gameId]` toggles the creator.
- Server exports: `jobcreatorOpen(player [, gameId])`, `jobcreatorClose(player)`,
  `jobcreatorIsActive(player)`.
- Client exports: `jobcreatorOpen([gameId])`, `jobcreatorClose()`, `jobcreatorIsActive()`.

You cannot enter from a lobby or a match, and you cannot join a lobby while in
the creator. v_jobmanager checks the `jobCreator` element data for this.

## Dependency on v_jobmanager

v_jobmanager is a soft dependency: there is deliberately no `<include>` for it (an include
would restart the creator, and kick every editor out, whenever v_jobmanager restarts). The
start order therefore does not guarantee v_jobmanager is running when this resource loads, so
`server/main.lua` never caches `exports.v_jobmanager`: `jm` is a lazy proxy that resolves the
export on every call. Keep it that way; a top-level `exports.v_jobmanager` throws at load time
and leaves the whole server script unloaded.

Every session gets its own dimension (`45000 + slot`). Position, dimension,
health, armour and weapons are saved on entry and restored on exit. While the creator is open the
player carries `save.position` (the place before the creator), so v_accounts never saves the
editor dimension.

## Missions

**New Mission** builds a v_jobmanager mission (`v_jobmanager/mode_mission/README.md`).

- **Place:** spawnpoints, zones (radius / height in the element menu), peds (skin, weapon,
  behaviour guard / patrol / attack / civilian, patrol points from your position), vehicles
  (role: to take / crew vehicle / prop / enemy; enemies park as an ambush or chase, with a
  crew), items (v_inventory mission items), interaction points (hold E). Every ped / vehicle /
  item can appear at a stage and be removed by stages.
- **Stages:** each stage opens its own menu: title (the objective text), objectives, all/any,
  fail conditions, time limit, respawn point (your position), removed elements, order, delete.
  Deleting an element also removes the objectives that point at it.
- **Mission Settings:** Team lives, time limit, the players' weapons (up to 4) / ammo / armour,
  reward money / XP (0 = automatic), and for admin level >= `OFFICIAL_LEVEL` **Script-only**:
  the mission is saved and published as an official game that only other resources start
  (no world marker).
- **Test:** a real mission match alone in the editor dimension from any stage, no rewards;
  F6 (or F2 > Stop test) ends it. Race tests use v_jobmanager's checkpoint visuals.
- Race Settings has the **Off-route limit** (default 150 m, 100 / 250, off for stunt races).
- Limits: `CREATOR.LIMITS.mission`, official / script-only: `CREATOR.OFFICIAL_MISSION`.

## Rights

| who | can |
|---|---|
| any logged-in player | create games, save them privately (max `MAX_GAMES_PER_PLAYER`), edit and delete their own unpublished games |
| admin level >= `CREATOR.ADMIN_LEVEL` (3) | publish / unpublish community games, open and delete anyone's games, place the world job marker, open official games and save drafts of them |
| admin level >= `CREATOR.OFFICIAL_LEVEL` (5) | publish official games: an official draft, or any game with **Save & Publish as Official** / **Publish as Official** (a community game moves to the official games); unpublish and delete official games |

A game can only be open in one editor at a time (`locks` in `server/main.lua`).
If a non-admin saves a game, its job marker is always taken from the stored
copy, so non-admins cannot move or add one.

## Official games

Admins (level >= 3) can also open the official games (`jobs_official`) from **Official Games** in the start menu.
- **Save** writes a draft (`jobs_draft`). The live game does not change.
- **Publish** (level >= 5) validates the draft, writes it into `jobs_official`, registers the game live and deletes the draft.
- **Unpublish** (level >= 5) takes the game out of the job list. It stays as an official draft, and only then can it be deleted.
- The editor never changes `id` and `createdBy`. The image is kept unless a new photo is taken.
- They may use any object, vehicle or weapon model, with bigger limits: 1000 objects, 300 checkpoints.

## Storage (MySQL, through v_jobmanager `core/storage.lua`)

- **Save** writes the game's row in `jobs_draft`. A draft is never a live game.
- **Publish** validates the draft with the same validator the loader uses, writes it
  into `jobs_community` (or `jobs_official`), registers the game live and deletes the draft.
  - Running lobbies and matches keep the old version.
  - A world marker is created or moved immediately.
- **Saving a published game** only writes the draft. The game is `pending` until an
  admin publishes again.
- **Unpublish** moves the live copy back into `jobs_draft`; nothing is lost.
- **Thumbnails** (640x360 JPEG) are stored base64 in the `image` column. Clients
  download them on demand into `community_img/<id>_<version>.jpg` inside
  v_jobmanager (`core/client/images.lua`), so the lobby, the scoreboard and
  ui_pause show them through their usual `fileExists(image)` fallback.

The server rebuilds every saved game in `server/sanitize.lua`:
- only catalog models, vehicles and weapons are accepted,
- numbers are clamped,
- lists are limited: 300 objects, 32 spawnpoints, 150 checkpoints.

## Controls

| key | |
|---|---|
| `R` | editor menu (ui_inac temp menu): Place, Objects, settings, Game Info, Test, Thumbnail, Check Problems, Undo / Redo, Save, Publish, Close / Exit |
| `F5` | free camera <-> on foot |
| free camera | WASD, Q/E down/up, Shift fast, Alt slow, hold RMB to look, LMB to select an element (opens its menu), Del to delete the selection |
| on foot | elements have ui_interactobject menus (Q/E focus, X open): Move, Duplicate, Options..., Delete |
| placing | LMB place (at the cursor, or at the crosshair on foot), wheel rotates, Backspace stops |
| moving | follows the cursor until you nudge it; arrows / PgUp / PgDn move (relative to the camera), Num 4/6 8/2 7/9 rotate, wheel turns, G toggles follow, End drops to the ground, Shift x8 / Alt fine, Enter / LMB drop, Backspace cancel |
| `Ctrl+Z` / `Ctrl+Y` | undo / redo |
| `F6` | end a test run |

**Photo mode:**
- HUD hidden (`hideHUD`), editor helpers hidden, free camera with mouse look.
- A 16:9 frame guide shows what will be in the picture.
- `SPACE` takes the photo. It is sent to the server and stored on the next Save.

## Layout

```
shared/config.lua    limits, keys, admin level, helper models
shared/catalog.lua   object categories, vehicles, weapons (server whitelist)
server/main.lua      sessions, rights, locks, save / publish, test vehicles / weapons
server/sanitize.lua  rebuilds client game data
client/core.lua      Editor state, doc, undo / redo, lifecycle, exports
client/view.lua      doc -> client elements, overlay, picking
client/freecam.lua   free camera
client/tools.lua     place / move tools, item operations
client/menus.lua     every ui_inac menu
client/mission.lua   mission doc helpers, Mission Settings / Stages / element menus
client/interact.lua  ui_interactobject menus (on foot)
client/keys.lua      key dispatch
client/test.lua      test runs (race checkpoints run locally)
client/photo.lua     thumbnail photos
client/hud.lua       key help
```
