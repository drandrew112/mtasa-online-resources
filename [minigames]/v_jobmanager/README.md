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
