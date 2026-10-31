# ai_peds

AI peds on the navmesh (`[ai]/navmesh`, `<include>`; the calls go through pcall, so without it the peds still
run, with straight-line moves and no ped traffic). Modules:

- **Ped traffic**: a few walkers on the sidewalks around players, only in built-up areas.
- **Behaviours**: `civilian` (does its task, e.g. walks the sidewalks), `scared` (flees, anywhere), `enemy` (attacks with
  its weapon, with fists / a melee weapon when it has no gun; anywhere; a gun shoots a target sitting in a vehicle, an
  unarmed one pulls it out first with the GTA jack when the vehicle is slow, `JACK_*` in the config). Plus the internal `exiting`, `seated`, `dead`.
- **Medical status** (`server/medical.lua`, medsys optional): every ped is a persistent medsys patient, so a medic
  can always examine it and the medsys events module injures it. A hit that would kill is cancelled; the ped goes down
  in medsys (unconscious / clinical death) with the `downed` behaviour and is not culled while a player is within
  `DESPAWN_DIST`. Back up (stable / confused): its old behaviour again. `AIPEDS.MEDICAL` switches it off.
- **ai_land_traffic drivers**: a driver of a released traffic vehicle gets out properly and flees or attacks.
- **Scripted peds** via exports: goal, patrol area, guard point, group relations, weapons, target. First user: the
  gang war minigame (gang members defending their territory).

## How it works

- **Server = brain, syncer client = motor** (`server/peds.lua`, `client/motor.lua`). The server decides (behaviours,
  tasks, navmesh routes, perception) at 4 Hz and sends each ped's command to its syncer: `idle` / `wait` (stand, face a
  point), `move` (walk / run / sprint along points), `combat` (target, range, melee, accuracy, burst pattern), `exit` (get
  out of the vehicle). The syncer turns and moves the ped with control states every frame (`forwards`, `walk`,
  `sprint`, `aim_weapon` + `setPedAimTarget`, `fire`, `enter_exit` / `setPedExitVehicle`), steps around things in front
  of it, jumps once when stuck and then reports `stuck` (the server re-routes). MTA picks the syncer (nearest player
  within `ped_syncer_distance`, 100 m default; tracked with `onElementStartSync` / `onElementStopSync` and re-checked every
  second); **a ped without a syncer stands still** and its behaviour is paused. The per-frame handler only runs while the
  client has commands.
- **Other clients** (`client/motor.lua` puppets): control states are not synced, so the other players would see the ped
  slide without a walk animation. The syncer reports its move state (`walk` / `run` / `sprint` / stop, a stop only after
  300 ms), the server puts it in the `ai_peds.mv` element data (`DATA_MOVE`), and every other client that streams the ped
  in plays that walk along the synced facing; the ped sync corrects the position. Fighting the same way: while the
  syncer aims + fires (or hits in melee range) it reports `fight`, the server puts the combat command's target and
  firing pattern in `ai_peds.fight` (`DATA_FIGHT`, false otherwise), and the other clients aim at that target and fire
  bursts / hit with the same pattern. Each client's own shots only hurt its own player, so every player can be hit;
  shot reports and damage to AI peds still come only from the syncer.
- **Steering around obstacles**: a blocked forward probe picks the clearer side and keeps it while still blocked.
- **Routes** (`server/route.lua`, `server/tasks.lua`): sidewalk walks are navmesh random walks (`getPedRandomWalk` with
  the `WALK_KINDS` edges: sidewalks + crossings, no park / hiking paths), continued from the last node before the end;
  goto / patrol / flee / chase routes are async navmesh ped routes (`requestRoute("ped")`; role `civilian` for
  scripted tasks by default, `free` for fleeing and fighting = open terrain). Walkers keep to the right side of the
  sidewalk (`WALK_SIDE` of the path width).
- **Crossings**: a walker stops at the kerb while the ped light is red (`isCrossingOpen(phase)`: the ai_land_traffic
  light cycle) or a vehicle would drive over the crossing within ~3 s; it gives up waiting after `CROSSING_MAX_WAIT`.
  ai_land_traffic cars stop for peds on the road (its obstacles).
- **Perception** (`server/perception.lua`): clients report their own gunshots and the ones of the AI peds they sync
  (`SHOT_REPORT_GAP`), and damage they did to AI peds (the attacker's client reports: player, its vehicle, or an AI ped
  synced there). Deaths (`onPedWasted`) and exploding vehicles come from server events. Civilians within
  `SHOT_SCARE_RADIUS` / `ATTACK_SCARE_RADIUS` get scared; an attacked civilian fights back with `CIVILIAN_FIGHT_BACK`
  chance; enemies engage hostile shooters within `SHOT_ALERT_RADIUS`; an attacked enemy calls its group mates within
  `GROUP_ALERT_RADIUS`.
- **Groups** (`server/groups.lua`): every ped has a group (walkers / drivers `civilian`, scripted `scripted` unless set),
  players are `player` unless `setPlayerAIGroup` / element data `ai_peds.group`. Relations `hostile` / `neutral` (default)
  / `friendly` (a group with itself). Personal grudges on top: a ped is hostile to whoever attacked it for `GRUDGE_TIME`.
  Calm enemies scan for hostiles within their aggro radius every `SCAN_INTERVAL` (server side, no line of sight: the
  client walks the route until it sees the target).

### Ped traffic (`server/traffic.lua`)

Only around players in dimension 0 / interior 0 and only in built-up areas: at least `SETTLEMENT_MIN` m of navmesh
sidewalk within `SETTLEMENT_RADIUS` of the player (country roads and lone footpaths get nobody). Density: sidewalk
length around the player / `SIDEWALK_PER_PED`, capped by `MAX_PER_PLAYER` (x `NIGHT_FACTOR` at night), `MAX_TRAFFIC` on the
server. Players share one budget (a spawn point must be under the cap of every player near it), `AREA_MAX` peds within
`AREA_RADIUS`. Spawns on a sidewalk edge `SPAWN_MIN_DIST`..`SPAWN_MAX_DIST` from players (inside the syncer distance),
`SPAWN_VISIBLE_MIN` from a camera looking at it. Walkers and adopted drivers are removed beyond `DESPAWN_DIST`, or when no
camera saw them for `CULL_AFTER` and they are farther than `CULL_MIN_DIST` (not while fighting). Every number is in
`shared/config.lua` to try out what the server bears; `/aipeds` shows the counts.

### Drivers from ai_land_traffic (`server/drivers.lua`, `server/behaviours/exiting.lua`)

ai_land_traffic calls `adoptTrafficDriver(ped, veh, {reason, culprit})` when a traffic vehicle is released by a crash,
damage, a jack or a player getting in (not for its `releaseTrafficVehicle` export). The driver is never teleported:

1. `exiting`: after a crash it waits `DRIVER_EXIT_DELAY` and until the vehicle is slower than `DRIVER_EXIT_SPEED`, then its
   syncer makes it get out (`setPedExitVehicle`, fallback `enter_exit` control: the GTA exit animation), repeated every
   `DRIVER_EXIT_RETRY`. A jacked driver is pulled out by the player; still inside after `DRIVER_JACK_WAIT`, it gets out
   itself. Not out after `DRIVER_EXIT_GIVEUP`: `seated` (stays in the vehicle; culled with the others).
2. Out of the vehicle: `enemy` against the culprit (`DRIVER_ENEMY_CHANCE`, `DRIVER_ENEMY_CHANCE_JACKED`; armed with
   `DRIVER_ARMED_CHANCE` from `DRIVER_WEAPONS`, else fists) or `scared` (always when there is no culprit player).
3. Calmed down / target lost: `civilian` with the wander task (back to the sidewalks if there are any near).

Without ai_peds running, ai_land_traffic leaves the driver in the vehicle.

## Exports (server)

Peds:
- `createAIPed(skin, x, y, z, opts)` -> ped | `false, reason`. opts: `rot`, `dimension`, `interior`, `behaviour`
  (`civilian` default | `scared` | `enemy`), `task` + `taskOpts` (below), `group`, `weapon`, `ammo`, `health`, `armor`,
  `accuracy` (0..1), `aggroRadius`, `leash`, `home` ({x, y, z}; an enemy with a patrol / guard task gets the task point),
  `retaliate` (true), `role` (navmesh ped route role of its tasks: `civilian` (sidewalks, crossings) / `free` / `police`...),
  `speed` (`walk` | `run` | `sprint` of its task moves), `keepBody`, `target` (enemy: attack now), `fightBack`.
- `destroyAIPed(ped)`, `isAIPed(ped)` (`traffic` | `driver` | `scripted` | false), `getAIPeds([kind])`,
  `getAIPedState(ped)` ({kind, behaviour, mode, task, group, weapon, target, syncer, dead, command, x, y, z, combat}).
- `setAIPedBehaviour(ped, name, args)` (civilian: `task`, `taskOpts`; scared: `threat` element or `x, y, z`; enemy:
  `target`), `getAIPedBehaviour(ped)` -> name, mode (enemy: `calm` / `engage`).
- `setAIPedTask(ped, name, opts)`, `getAIPedTask(ped)`, `aiPedGoTo(ped, x, y, z, opts)`. Tasks (what a calm ped does; a
  fighting or scared ped takes it up again afterwards):
  - `idle` {fx, fy}: stands (facing that point).
  - `wander`: sidewalk random walk.
  - `goto` {x, y, z, speed, role, tag, direct}: `onAIPedArrived(tag, x, y, z)` / `onAIPedTaskFailed(tag, reason)`.
  - `patrol` {points = {{x, y, z}, ...}, loop (true)} or {x, y, z, radius}; `wait` = {min, max} ms at each point. A finite
    point list ends with `onAIPedArrived("patrol_end" | tag)`.
  - `guard` {x, y, z, rot}: stands there facing rot, walks back when pushed away.
  - `follow` {element, distance (3), speed}.
- `setAIPedTarget(ped, element | false)`: attack now (makes it an enemy; grudge kept until `false`), `getAIPedTarget(ped)`.
- `setAIPedCombat(ped, {aggroRadius, leash, accuracy, retaliate, home = {x, y, z} | false})`,
  `giveAIPedWeapon(ped, weapon, ammo)` (GTA weapons on the ped: peds are not under wp_manager).
- Groups: `setAIPedGroup(ped, group)`, `getAIPedGroup(ped)`, `setAIGroupRelation(a, b, "hostile" | "neutral" | "friendly",
  mutual = true)`, `getAIGroupRelation(a, b)`, `setPlayerAIGroup(player, group | false)`, `getPlayerAIGroup(player)`.

Views: `isPointSeenByPlayers(x, y, z, maxDist, dimension)` -> does any player camera (within maxDist, in that
dimension) look towards the point (view cone, no line of sight; no fresh camera report = sees). For removing peds unseen.

Traffic: `setAIPedTrafficEnabled(bool)`, `isAIPedTrafficEnabled()`, `getAIPedStats()`. ai_land_traffic:
`adoptTrafficDriver(ped, veh, {reason, culprit, behaviour})`.

Events (server, source = the ped, attach to `root`): `onAIPedArrived(tag, x, y, z)`, `onAIPedTaskFailed(tag, reason)`,
`onAIPedTargetAcquired(target)`, `onAIPedTargetLost(target, reason)` (dead / gone / far / leash / peace / export),
`onAIPedBehaviourChanged(new, old)`, `onAIPedWasted(killer, weapon)`, `onAIPedRemoved(reason)`.

Element data: `ai_peds` = kind on every AI ped.

### Example: gang territory

```lua
local ai = exports.ai_peds
ai:setAIGroupRelation("ballas", "grove", "hostile")
ai:setPlayerAIGroup(attacker, "grove")            -- players of the attacking side
for i, spot in ipairs(spots) do
    ai:createAIPed(102 + i % 3, spot[1], spot[2], spot[3], {
        behaviour = "enemy", group = "ballas", weapon = 30, ammo = 300, accuracy = 0.5,
        task = "patrol", taskOpts = { x = cx, y = cy, z = cz, radius = 35, wait = { 2000, 6000 } },
        aggroRadius = 35, leash = 80, role = "free",
    })
end
addEventHandler("onAIPedWasted", root, function(killer) --[[ score ]] end)
```

### Later: cover

`Behaviours.enemy.positionProvider = function(p, target, tx, ty, tz) return x, y, z end` (server, `server/behaviours/
enemy.lua`): when it returns a point, the fighting ped goes there and fights from it (`cmd.hold`: it does not walk on
towards the target; it shoots when it sees the target). A cover module only has to pick the points.

## /aipeds (admin_level >= 4)

No argument: counts (walkers, drivers, scripted, synced, per behaviour) and the sidewalk length / walker target where you
stand. `on` / `off` (ped traffic, off also clears it), `clear`, `debug` (labels on AI peds; route lines of the peds your
client syncs: cyan move, red combat, yellow wait).

## Status

Headless-tested (lupa + MTA stubs, 51 scenarios: spawning, crossings, fleeing / calming, fighting back, drivers
exit / jack / fast vehicle / blocked door, gang guard aggro / leash / group call / relations, goto, bodies, culling,
no navmesh). In-game untested: the client motor (control states, `setPedCameraRotation` sign - calibrated at runtime
from how the peds move, logged once when flipped), `setPedExitVehicle` sync to other clients, ped shots on players.
