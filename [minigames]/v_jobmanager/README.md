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

- Walk into a job marker to join or create its waiting lobby.
- The first player is host and starts it with `/startjob`.
- Leave a waiting lobby with `/leavejob`.
- `/quickjob` joins one randomly selected existing lobby with room. It never
  creates a new lobby, as requested.
- Anyone in a waiting lobby can pick **Invite Player** in the lobby panel to
  open a player list; pressing Enter on a name sends that player a lobby invite.
  The invite is delivered through `v_phone` (`phoneAddInvite`); accepting it on
  the phone calls the exported `jobmanagerAcceptInvite` and drops the player
  straight into the lobby. `v_phone` is a soft dependency — if it is not running
  the invite action just reports that the phone service is unavailable.

Race checkpoints, vehicles, lobby membership, deathmatch elimination, and
match cleanup are all controlled on the server. `jobmanager:joinJob`,
`jobmanager:startJob`, and `jobmanager:leaveJob` are safe integration points
for the planned panel; they derive the player from the MTA `client` value.

## Configuration

Add jobs only in the owning `mode_*` directory. Every race job needs a valid `raceId` in the
route data. Deathmatch jobs need at least `minPlayers` spawn entries,
a weapon, and ammunition. The currently enabled routes deliberately omit the
incomplete legacy jobs and the malformed legacy race #3 spawn data.
