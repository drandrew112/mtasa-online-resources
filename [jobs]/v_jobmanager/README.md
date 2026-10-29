# v_jobmanager 2.0

This is a clean server-authoritative replacement for the archived resource in
`old/`. Only the migrated race route data is retained; none of the old lobby,
voting, checkpoint, UI, or synchronization code is executed.

## Layout

- `shared/config/` — generic job registry only
- `mode_race/` — race jobs, routes, spawnpoints and race implementation
- `mode_dm/` — DM job, random-arena spawnpoints and DM implementation
- `mode_mission/` — co-op missions (stages, objectives, AI enemies), script-started missions
- `core/` — generic lobby, UI, commands, authorization and lifecycle API
- `assets/sounds/` — restored UI sounds
- `old/` — untouched archive of the original resource

## Current flow

- Every job marker has a 3D DX label (job name, type, player count). Standing in
  the marker and pressing **E** joins a waiting lobby of that job or opens a new
  one (`core/client/markers.lua`).
- The first player is host and starts it with `/startjob`.
- Leave a waiting lobby with `/leavejob`.
- `/quickjob` joins one randomly selected existing lobby with room. It never
  creates a new lobby, as requested.
- Anyone in a waiting lobby can pick **Invite Player** in the lobby panel to
  open a player list; pressing Enter on a name sends that player a lobby invite.
  The invite is delivered through `ui_phone` (`phoneAddInvite`); accepting it on
  the phone calls the exported `jobmanagerAcceptInvite` and drops the player
  straight into the lobby. `ui_phone` is a soft dependency — if it is not running
  the invite action just reports that the phone service is unavailable.

## During a match (3.0)

- **Leaving:** `/leavejob` works in a running match too: it opens a confirmation menu
  (`/leavejob confirm` leaves at once). `F2` opens the job menu (leave, race: Reset to
  checkpoint every 10 s, spectator list), ui_pause has **Leave current job** in Online. Leaving
  pays nothing and costs nothing; the scoreboard shows **Left**. Server export
  `jobmanagerLeave(player)` leaves a lobby or a match; client exports `jobmanagerInMatch()`,
  `jobmanagerLeaveJob(confirmed)`.
- **No saving in the job:** at match start the player gets the server-only element data
  `save.position` = the place before the job, so v_accounts' savesys saves that instead of the
  match dimension (autosave and quit). It is removed when the player is put back.
- **Spectating** (`core/spectate.lua`, `core/client/spectate.lua`): a dead DM player (after 3 s)
  and a finished racer watch the players still playing. The ped stays hidden, attached above
  the target; the camera is the target's GTA follow camera. Scrolling the ui_inac list switches at
  once; `Space` reopens it. The others' mouse-look is not synced in MTA, so it is not their exact view.
- **Race:** the client draws the checkpoints (`mode_race/client/checkpoints.lua`, shaders in
  `mode_race/fx/`): a ring wall + ground disc and a 3D arrow pointing at the next checkpoint
  (a flag at the finish), the following checkpoint faded. The GTA marker is invisible and only
  counts the hit. A racer is put back at the last checkpoint, facing the next one, when the
  vehicle blows up (new vehicle), falls into the water, goes more than `race.offRoute` m
  (default 150, 0 = off) from the route for 5 s, or falls 40 m below the route; then 3 s ghost
  (no collisions with other racers). After the first finisher the others get 60 s, then DNF.
  Tuning: `JOBS_CONFIG` in `shared/config/jobs.lua`.
- **Missions:** `mode_mission/README.md` (stages, objectives, Team lives, script-only missions
  and their exports).

Race checkpoints, vehicles, lobby membership, deathmatch elimination, and
match cleanup are all controlled on the server. `jobmanager:joinJob`,
`jobmanager:startJob`, and `jobmanager:leaveJob` are safe integration points
for the planned panel; they derive the player from the MTA `client` value.

## Games (MySQL: `jobs_official`, `jobs_community`, `jobs_draft`)

Every game is a row in one of three tables with the same columns (`database.sql`,
also in the repo-root `main.sql`; `core/storage.lua` creates them on start):

| table | holds |
|---|---|
| `jobs_official` | the server's own live games |
| `jobs_community` | live player-made games (published by an admin) |
| `jobs_draft` | creator working copies: every Save writes here, a draft is never a live game |

A draft next to a live row means unpublished changes (`pending`); a draft alone is a
private or unpublished game. `jobs_draft.target` says which table Publish writes into.
Columns: `id, name, type, created_by, data, image, image_version, created_at, updated_at`,
plus `published_by` (live tables) or `target` (drafts).

- `data` is the game JSON below without `id` / `createdBy` / `image`. Only
  `assets/jobs/default.jpg` is a file: the fallback for games without a thumbnail.
- `image` is the base64 JPEG thumbnail taken in the creator. The game's `image` then
  becomes `community_img/<id>_<image_version>.jpg`, which clients download on demand
  (`core/client/images.lua`). In `jobs_draft`, `NULL` means "same as the live copy" and
  `''` means "removed".
- `import_official_games.sql` loads the finished official races (casino_tour, canal_tour,
  beach_motorcycling). It is re-runnable. ls_airport_dm is left out on purpose: it was a
  debug game.

All rows except images are cached in memory, so the exports answer right away; writes
go to MySQL asynchronously and in order. The tables are shared by every server
instance: every 30 s `updated_at` is polled and rows another instance changed are
reloaded (live games are re-registered, the world marker follows).

Game data:

```
common:     id, name, type ("race"|"deathmatch"), createdBy, description, image,
            minPlayers, maxPlayers
marker:     [x, y, z]  optional - without it (community games) the game has no world
            marker/blip and is reached via the job browser, phone invite or /quickjob
objects:    optional [{model,x,y,z,rx?,ry?,rz?,scale?,alpha?,collisions?,doublesided?}] -
            created in the match dimension at match start, destroyed at the end (max 1000)
race:       { vehicles:[model], spawnpoints:[[x,y,z,rot]], checkpoints:[[x,y,z,size]],
              finish:[x,y,z,size], finishCamera?:{pos,lookAt,roll,fov}, offRoute?: m (0 = off) }
deathmatch: { weapon, ammo, armour?, spawnpoints:[[x,y,z,rot]] }
mission:    see mode_mission/README.md
scriptOnly: true (missions only, official games): never listed, started by other resources
```

`createdBy` is required (official games: `DrAndrew112`) and is shown in the lobby.
Spawnpoints need at least `maxPlayers` entries. Validation and registration live in
`core/games.lua`; each mode validates its own block via `JobModes[type].validate`.
Invalid games are skipped with a debug warning. Community games may have at most 300 objects.

Storage exports (`core/storage.lua`, used by v_jobcreator and v_weekly; permissions are
the caller's job):
- `jobmanagerStorageReady()`, `jobmanagerGameEntry(id)`
- `jobmanagerCommunityList([owner])`, `jobmanagerOfficialList()`: entries
  `{ id, name, type, owner, official, published, pending, imageVersion, updated }`
- `jobmanagerGameLoad(id)`: the draft, else the live copy, and its entry
- `jobmanagerGameSave(game, owner, image [, target])`: writes the draft
- `jobmanagerGamePublish(id [, "official"] [, by])`: draft -> live. With `"official"`
  a community game moves to `jobs_official`.
- `jobmanagerGameUnpublish(id)`: live -> draft, nothing is lost
- `jobmanagerGameDelete(id)`: not for live official games
- `jobmanagerSendImage(player, id, eventName)`, `jobmanagerValidateGame(game)`

Publishing registers the game live through `registerJob` and creates its world
marker. Running lobbies keep the old version. See `v_jobcreator/README.md`.


## Rewards (core/rewards.lua)

At match end every player still in the match is paid **cash** (`givePlayerMoney`) and
**XP** (`v_levelsys:giveXp`), then sees the results screen (`core/client/results.lua`)
before the scoreboard: placement band -> payout (right) -> XP (left) -> level bar.
Aborted matches (resource stop) pay nothing; players who quit get nothing.

- Race: route km (spawn -> checkpoints -> finish) x `perKm`, clamped; DNF x0.25.
- Deathmatch: match minutes x `perMinute` (clamped) + kills x `perKill`.
- Mission: the mission's reward (or `perStage` x stages) + kills when passed; `failMin` when failed.
- Both: x(1 + 0.05 x (players-1)) max x1.5, then place multiplier (1st x1.5, 2nd x1.25, 3rd x1.1).
- Solo (match started with 1 player): fixed €500, no placement XP.
- Tuning lives in the `REWARDS` table.

Runtime per-game multipliers (not persisted, applied to the final money / XP total;
set by v_weekly, for official and community games alike):

```lua
exports.v_jobmanager:jobmanagerSetMultiplier(jobId, money, xp, label)  -- 1,1 removes it
exports.v_jobmanager:jobmanagerGetMultiplier(jobId)   -- money, xp, label|false
exports.v_jobmanager:jobmanagerGetMultipliers()       -- { [jobId] = {money, xp, label} }
exports.v_jobmanager:jobmanagerClearMultiplier(jobId)
exports.v_jobmanager:jobmanagerClearMultipliers()
```
