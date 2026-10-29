# Missions (`type = "mission"`)

The players work together through a list of stages. A stage is done when all (or, with
`complete = "any"`, one) of its objectives are done; the last stage done = mission passed.
Built in the Job Creator (v_jobcreator), run by `server/runner.lua`.

- **Squad:** the players of one mission are in an MTA team without friendly fire, and
  `client/hud.lua` cancels squad damage from explosions, vehicles and melee as well
  (element data `jobs.squad` = match id).
- **Team lives** (`teamLives`, default 3): every death takes one, the player comes back after
  `JOBS_CONFIG.MISSION.respawnMs` (10 s) at the stage's `respawnPoint` (else their spawnpoint)
  and watches the others meanwhile. A death with 0 lives left ends the mission: failed.
- **Rewards** (`core/rewards.lua` `REWARDS.mission`): passed = `mission.reward` (or the starting
  script's `opts.reward`, or `perStage` x stages) + kills; failed = `failMin` only (€500 + 100 XP).
  Leaving pays nothing and costs nothing.
- **Own dimension:** every mission, also a script-started one, runs in its match dimension.

## Data

```
mission = {
  spawnpoints = { {x, y, z, rot}, ... },            -- at least maxPlayers
  loadout     = { {id = 31, ammo = 300}, ... },     -- the players' weapons (wp_manager temp loadout)
  armour      = 50,
  teamLives   = 3,                                  -- 0..20
  timeLimit   = 1200,                               -- s, optional, the whole mission
  reward      = { money = 15000, xp = 4000 },       -- optional

  zones    = { {id, x, y, z, radius, height = 8} },
  peds     = { {id, skin, x, y, z, rot, weapon, ammo, health, armor, accuracy, aggroRadius,
                behaviour = "guard" | "patrol" | "attack" | "civilian", patrol = {{x, y, z}, ...}, stage} },
  vehicles = { {id, model, x, y, z, rot, role = "loot" | "crew" | "prop" | "enemy", locked,
                behaviour = "park" | "pursue", driver = {skin, weapon}, crew = 0..3, stage} },
  items    = { {id, item = v_inventory item id, x, y, z, label, stage} },
  points   = { {id, x, y, z, label, holdMs} },      -- hold E (interact objective)

  stages = {
    { id, title,                                    -- the title is the objective text on screen
      objectives = { {type = ..., label?}, ... },   -- 1..8
      complete = "all" | "any",
      fail = { {type = ...}, ... },
      timeLimit = s, respawnPoint = {x, y, z, rot},
      despawn = { entity ids removed when the stage starts },
      next = stage id (optional jump; default the next stage) },
  },
}
```

`stage` on a ped / vehicle / item = the stage id it appears at (missing = mission start). Ids are
unique per list; the validator in `server/runner.lua` checks every reference.

| objective | params | done when |
|---|---|---|
| `enterZone` | zone, who, vehicle? | a player (who = "all": every player still playing) is in the zone, in that vehicle if given |
| `stayInZone` | zone, seconds, who | as above for `seconds` in total |
| `enterVehicle` | vehicle, who | sits in the vehicle |
| `deliverVehicle` | vehicle, zone | the vehicle stands in the zone |
| `collectItem` | item | a player holds the item (v_inventory, X menu to pick it up) |
| `deliverItem` | item, zone | the item is in the zone |
| `killPeds` | peds = {ids} or all = true | the listed peds (an enemy vehicle id = its crew) are dead |
| `destroyVehicle` | vehicle | the vehicle is blown up |
| `interact` | point | a player held E at the point for its `holdMs` |
| `survive` | seconds | that much time has passed |
| `scriptEvent` | name | `jobmanagerMissionSignal(matchId, name)` was called |

Fail conditions: `vehicleDestroyed {vehicle}`, `pedDied {ped}` (escort), `leaveZone {zone}`
(every player outside). Always: Team lives out, the time limit, everyone left.

Enemies: peds are `ai_peds` peds (group `jm_enemy_<matchId>`, hostile to the players'
`jm_crew_<matchId>`; civilians neutral). Without ai_peds they are plain GTA peds. Enemy vehicles
have a GTA driver: `park` = an ambush, the crew gets out (as ai_peds peds) when a player comes
within 45 m; `pursue` = the vehicle's syncer client drives straight at the nearest player
(`client/hud.lua`, element data `jobs.chase`) and the crew gets out when it is close and slow.
ai_land_traffic scripted vehicles are not used: they only exist in dimension 0.

## Script missions (business setups, heists)

A mission with `scriptOnly = true` is an official game (admin level >= 5 in the creator) that
never shows in a list, a marker, /quickjob or a weekly bonus. Only other resources start it:

```lua
local jm = exports.v_jobmanager
local matchId, err = jm:jobmanagerStartMission("heist_bank_setup", { leader, member }, {
    reward = false,                 -- false: this script pays; { money, xp }: replaces the mission's reward
    tag = "biz_42",                 -- comes back in the events
    returnTo = { x, y, z, interior, dimension },   -- where the players go afterwards (default: where they were)
    startStage = "s3",              -- optional
    quiet = true,                   -- no results screen / scoreboard, only a notification
})
jm:jobmanagerMissionSignal(matchId, "vault_open")   -- completes the scriptEvent objectives "vault_open"
jm:jobmanagerAbortMission(matchId, "reason")        -- ends it, no payout ("aborted")
jm:jobmanagerGetMatch(matchId)  -- { jobId, type, players, dimension, stage, startedAt, test, tag }

addEventHandler("onJobMissionStage", root, function(matchId, missionId, stageId, tag) end)
addEventHandler("onJobMissionFinished", root, function(matchId, missionId, result, info, tag)
    -- result: "success" | "fail" | "aborted"
    -- info: { stagesDone, stagesTotal, reason, timeMs, players }
end)
```

The players must be free (logged in, alive, not in a lobby, match or the creator), at most
`maxPlayers`. Public missions use the same mode through the normal lobby.

## Creator test runs

`jobmanagerTestMission(player, game, startStage)` runs an unsaved, sanitized mission alone in the
player's current (editor) dimension without rewards (tag `"__creator_test"`);
`jobmanagerStopTest(player)` ends it. v_jobcreator listens to `onJobMissionFinished`.

Status: headless-tested (lupa: validation, stages, objectives, Team lives, fail conditions, the
creator sanitizer against the validator). Untested in-game: AI fights, the chase driver, items,
the HUD.
