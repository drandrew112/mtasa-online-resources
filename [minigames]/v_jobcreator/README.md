# v_jobcreator

In-game creator for v_jobmanager games (race and deathmatch). It produces the
same JSON as `v_jobmanager/games/*.json`. Community games are stored by
v_jobmanager (`core/community.lua`) under `games/community/`.

## Entering

- `/creator [gameId]` toggles the creator.
- Server exports: `jobcreatorOpen(player [, gameId])`, `jobcreatorClose(player)`,
  `jobcreatorIsActive(player)`.
- Client exports: `jobcreatorOpen([gameId])`, `jobcreatorClose()`, `jobcreatorIsActive()`.

You cannot enter from a lobby or a match, and you cannot join a lobby while in
the creator. v_jobmanager checks the `jobCreator` element data for this.

Every session gets its own dimension (`45000 + slot`). Position, dimension,
health, armour and weapons are saved on entry and restored on exit.

## Rights

| who | can |
|---|---|
| any logged-in player | create games, save them privately (max `MAX_GAMES_PER_PLAYER`), edit and delete their own unpublished games |
| admin level >= `CREATOR.ADMIN_LEVEL` (3) | publish / unpublish, open and delete anyone's games, place the world job marker |

A game can only be open in one editor at a time (`locks` in `server/main.lua`).
If a non-admin saves a game, its job marker is always taken from the stored
copy, so non-admins cannot move or add one.

## Official games

Admins (level >= 3) can also edit the official games (`games/<id>.json` in `games/index.json`) from **Official Games** in the start menu.
- **Save** writes a draft to `games/drafts/<id>.json`. The live game does not change.
- **Publish** validates the draft, overwrites `games/<id>.json`, registers the game live, then deletes the draft.
- The editor never changes `id` and `createdBy`. The image is kept unless a new photo is taken (`games/img/<id>.jpg`).
- Official games cannot be unpublished or deleted from the creator.
- They may use any object, vehicle or weapon model, with bigger limits: 1000 objects, 300 checkpoints.

## Storage (in v_jobmanager)

- **Save** writes `games/community/private/<id>.json`. This copy is never loaded.
- **Publish** validates the private copy with the same validator the loader
  uses, writes `games/community/<id>.json` and registers the game live.
  - Running lobbies and matches keep the old version.
  - A world marker is created or moved immediately.
- **Saving a published game** only changes the private copy. The index marks it
  `pending` until an admin publishes again.
- **Thumbnails** go to `games/community/img/<id>.jpg` (640x360 JPEG). Clients
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
client/interact.lua  ui_interactobject menus (on foot)
client/keys.lua      key dispatch
client/test.lua      test runs (race checkpoints run locally)
client/photo.lua     thumbnail photos
client/hud.lua       key help
```
