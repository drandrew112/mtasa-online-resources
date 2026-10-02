# v_introduce – server introduction

A mandatory introduction that shows new players what they can do on the server. It cannot be
skipped. It is built from modules (chapters): a new feature gets a new module file, the core does
not change. `v_modmenu` never appears in it (`INTRO.BLOCKED_RESOURCES`).

## When it runs

- On `onPlayerLoaded` (1.5 s later) and for every logged-in player 3 s after the resource starts.
- **Mode "full"**: the player has not finished the introduction yet (`intro.done`). Every module
  they have not seen in its current version runs. Existing players get it too.
- **Mode "new"** ("What's new"): the player has finished it before, but a module is new or got a
  higher `version`. Only those modules run.
- `INTRO.DEBUG = true`: the full introduction runs on every login, whatever the player has seen.
- A player whose position another script holds (`save.position`, e.g. the EMS tutorial) is checked
  again at the next login.

## While it runs

- The player is frozen on `INTRO.STAGE` in their own dimension (`INTRO.DIMENSION_BASE` + n). No
  movement, no weapons, no damage. Nobody can invite them (`ui_phone` invites are refused).
- The camera never shows the player: a scene without a camera of its own shows the fixed
  `INTRO.BACKDROP`.
- Objects and peds of dimension 0 (custom maps such as `map_ls_shop_01`, script objects,
  shopkeepers) do not exist in the player's dimension, and the world models those maps remove
  are gone everywhere. `client/mirror.lua` copies everything within `INTRO.MIRROR_RADIUS` of the
  camera's target into the introduction's dimension (client-side) while the scene shows it.
- "On the road" (vehicles chapter): the player sits in a practice vehicle (`INTRO.VEHICLE`, an ELS
  ambulance) and tries the headlights, the radio, the emergency lights, the siren and the flashing
  pattern. The driving controls stay locked.
- v_accounts saves the original position (`save.position`), so a quit never saves the stage.
- Only the panel the current scene teaches can open. The local element data `intro.allow` =
  `{ panelId = true }`; the panels check it before opening: `phone` (ui_phone), `social`
  (v_socialpanel), `interaction` (ui_inac), `pause` (ui_pause), `browser` (ui_browser), `chat`
  (v_chat).
- **No skip.** Continue (`SPACE`) unlocks after a short lock (`READ_CHARS_PER_SEC`,
  `CAMERA_LOCK_SHARE` of a camera ride, between `MIN_SCENE_TIME` and `MAX_SCENE_TIME` = 3 s) once
  no panel is open. Task and accept scenes have no lock: Continue unlocks as soon as they are done. The server refuses a module that finished faster than `MIN_MODULE_SHARE` of
  that time, and plays the refused modules again at the end.
- Every finished module is saved right away. After a quit the player continues with the first
  unfinished module.

## The end

- New accounts (`acc.registered`, set by v_accounts on registration) are spawned at `INTRO.SPAWN`
  (LS airport, terminal). Everybody else goes back to where they were.
- No objective or route is given: the player is free to go.

## Reward

Each module gives its `xp` the first time it is finished (`intro.rewarded`, so DEBUG runs or
"What's new" re-runs do not pay twice). The final module tops the total up to
`INTRO.REWARD_TOTAL_XP` = 2800, which takes a new player from level 1 to level 3 (v_levelsys).

## Chapters (modules/)

| # | id | requires | XP |
|---|---|---|---|
| 1 | welcome | – | 150 |
| 2 | hud | v_radar | 200 |
| 3 | social | v_chat (+ v_socialpanel) | 200 |
| 4 | phone | ui_phone | 250 |
| 5 | interaction | ui_inac | 200 |
| 6 | money | v_bank | 200 |
| 7 | vehicles | v_ownveh | 250 |
| 8 | work | work_core | 200 |
| 9 | activities | v_jobmanager | 250 |
| 10 | health | medsys | 200 |
| 11 | settings | ui_pause | 150 |
| 12 | rules | – (version = `RULES_VERSION`) | 200 |
| 13 | finish | – | top-up |

A module whose required resource is not running is left out and does not count. A scene can
have its own `requires` too.

## Writing a module

A module is plain data (no functions). Field list: `server/registry.lua`; scene types and their
fields: `client/scenes.lua` (`camera`, `card`, `task`, `highlight`, `world`) and `client/rules.lua`
(`accept`). Text can use key labels: `{key:phone}` → `INTRO.KEYS.phone`.

```lua
Intro.module {
    id = "garage", order = 75, version = 1, xp = 150,
    title = "Garages",
    requires = { "v_garage" },
    scenes = {
        { type = "world", duration = 8,
          camera = { from = { x, y, z, lx, ly, lz }, to = { x, y, z, lx, ly, lz } },
          point = { x, y, z }, label = "Garage", blip = 27,
          text = "..." },
        { type = "task", allow = { "phone" }, title = "...", text = "...",
          tasks = { { text = "Open your phone with {key:phone}", check = { data = "phoneOpen" } } } },
    },
}
```

Add the file to `meta.xml` (server script, after `server/registry.lua`). Another resource can add
its own chapter with `exports.v_introduce:registerModule(def)` (re-register on the
`onIntroduceStart` event); it is removed when that resource stops.

When a module's content changes a lot, raise its `version`: players who saw the old one get it
again as "What's new". When `rules.txt` changes, raise `INTRO.RULES_VERSION`.

## Update modules (updates/)

News for players who already know the server. Template: `updates/_TEMPLATE.lua` (not loaded).

- `update = true` marks the module. It is not part of the main line: only players who had
  already finished the introduction (`intro.done`) get it, on their next login, in the "What's
  new" frame with the same lock as the main line.
- New players never get the current updates: finishing the main line marks all of them as seen
  (put the important things into the main line as well).
- `expires = "YYYY-MM-DD"`: from that day on nobody gets it, so a player who comes back after
  months does not get a pile of old news.
- `order` = the date as a number (20261015): pending updates run oldest first.
- `xp` is optional (default 0) and does not count into the main-line top-up.
- `INTRO.DEBUG` plays the introduction as a new player sees it: without updates.
- Test: `/intro start <player> <updateId>` or `/intro start <player> updates` (every update).

## Account data (v_mysql)

`intro.seen` (JSON `{ id = version }`), `intro.rewarded` (JSON `{ id = xp }`), `intro.done`,
`intro.rules` (accepted rules version).

## Exports and events

- server: `isInIntro(player)`, `startIntro(player, "full" | "new")`, `resetIntro(player | account)`,
  `registerModule(def)`, `unregisterModule(id)`
- client: `isIntroActive()`, `getIntroAllow()`
- server events (source = player): `onIntroStart(mode)`, `onIntroModuleDone(id)`, `onIntroFinish(mode)`;
  `onIntroduceStart` on resource start

## Admin commands (`admin_level` >= `INTRO.ADMIN_LEVEL`)

- `/intro start <player> [full | updates | <moduleId>]`, `/intro stop <player>`,
  `/intro reset <player | account> [xp]`, `/intro list`
- `/introcam` prints the current camera matrix in the module format (and copies it): use it to
  tune the camera positions, which are first guesses.

## Changes in other resources

- v_accounts: `acc.registered` on registration.
- ui_phone: `intro.allow` check, local element data `phoneApp` (open app id), invites refused
  during the introduction.
- v_socialpanel, ui_inac, ui_pause, ui_browser, v_chat: `intro.allow` check before opening.
- v_radar: client export `getMinimapRect()`; the map works in every dimension
  (`MAP_IN_EVERY_DIMENSION`, `dimensionHasMap()`), interiors still have no signal.

## Wording

"Jobs" are the game modes (races, deathmatches - v_jobmanager). "Work jobs" are the duty jobs of
work_core (EMS, ...). Phone contacts are NPCs of the city who help with things, not players.
