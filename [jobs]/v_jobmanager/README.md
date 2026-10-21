# v_jobmanager 2.0

This is a clean server-authoritative replacement for the archived resource in
`old/`. Only the migrated race route data is retained; none of the old lobby,
voting, checkpoint, UI, or synchronization code is executed.

## Layout

- `shared/config/` — generic job registry only
- `mode_race/` — race jobs, routes, spawnpoints and race implementation
- `mode_dm/` — DM job, random-arena spawnpoints and DM implementation
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

Race checkpoints, vehicles, lobby membership, deathmatch elimination, and
match cleanup are all controlled on the server. `jobmanager:joinJob`,
`jobmanager:startJob`, and `jobmanager:leaveJob` are safe integration points
for the planned panel; they derive the player from the MTA `client` value.

## Game files (`games/<id>.json`)

Every game is a self-contained JSON file; the structure is the contract the
future creator mode will write. Add the id to `games/index.json` and to the
`<file>` list in `meta.xml`. Invalid games are skipped with a debug warning.

```
common:     id, name, type ("race"|"deathmatch"), createdBy, description, image,
            minPlayers, maxPlayers
marker:     [x, y, z]  optional - without it (community games) the game has no world
            marker/blip and is reached via the job browser, phone invite or /quickjob
objects:    optional [{model,x,y,z,rx?,ry?,rz?,scale?,alpha?,collisions?,doublesided?}] -
            created in the match dimension at match start, destroyed at the end (max 1000)
race:       { vehicles:[model], spawnpoints:[[x,y,z,rot]], checkpoints:[[x,y,z,size]],
              finish:[x,y,z,size], finishCamera?:{pos,lookAt,roll,fov} }
deathmatch: { weapon, ammo, armour?, spawnpoints:[[x,y,z,rot]] }
```

`createdBy` is required (existing games: `DrAndrew112`) and is shown in the lobby.
Spawnpoints need at least `maxPlayers` entries. Loading lives in `core/games.lua`;
each mode validates its own block via `JobModes[type].validate`.

## Community games (`games/community/`, made in v_jobcreator)

`core/community.lua` stores them and exposes server exports for the creator:
- `jobmanagerCommunityList`, `jobmanagerCommunityLoad`, `jobmanagerCommunitySave`
- `jobmanagerCommunityPublish`, `jobmanagerCommunityUnpublish`, `jobmanagerCommunityDelete`
- `jobmanagerCommunityImage`, `jobmanagerValidateGame`

Layout:
- `index.json` lists every community game (owner, published, pending, imageVersion).
- `private/<id>.json` is the saved working copy. It is never loaded.
- `<id>.json` is the live copy. It is loaded at start and written on publish.
- `img/<id>.jpg` is the thumbnail.

Publishing registers the game live through `registerJob` and creates its world
marker. Running lobbies keep the old version. Community games may have at most
300 objects. See `v_jobcreator/README.md`.

Official games can be edited by admins in the creator through `core/official.lua`:
- exports: `jobmanagerOfficialList`, `jobmanagerOfficialLoad`, `jobmanagerOfficialSave`, `jobmanagerOfficialPublish`, `jobmanagerOfficialImage`;
- Save writes a draft to `games/drafts/<id>.json`, and Publish overwrites `games/<id>.json` and re-registers the game.


## Rewards (core/rewards.lua)

At match end every player still in the match is paid **cash** (`givePlayerMoney`) and
**XP** (`v_levelsys:giveXp`), then sees the results screen (`core/client/results.lua`)
before the scoreboard: placement band -> payout (right) -> XP (left) -> level bar.
Aborted matches (resource stop) pay nothing; players who quit get nothing.

- Race: route km (spawn -> checkpoints -> finish) x `perKm`, clamped; DNF x0.25.
- Deathmatch: match minutes x `perMinute` (clamped) + kills x `perKill`.
- Both: x(1 + 0.05 x (players-1)) max x1.5, then place multiplier (1st x1.5, 2nd x1.25, 3rd x1.1).
- Solo (match started with 1 player): fixed €500, no placement XP.
- Tuning lives in the `REWARDS` table.

Runtime per-game multipliers (not persisted, applied to the final money / XP total;
meant for v_weekly):

```lua
exports.v_jobmanager:jobmanagerSetMultiplier(jobId, money, xp, label)  -- 1,1 removes it
exports.v_jobmanager:jobmanagerGetMultiplier(jobId)   -- money, xp, label|false
exports.v_jobmanager:jobmanagerGetMultipliers()       -- { [jobId] = {money, xp, label} }
exports.v_jobmanager:jobmanagerClearMultiplier(jobId)
exports.v_jobmanager:jobmanagerClearMultipliers()
```
