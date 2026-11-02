# v_scenemanager – Scene Manager

Scenes (accidents, ill people, brawls, armed suspects ...) stored as JSON files. A scene spawns its vehicles and
peds in the world and gives a task to every agency it needs: the EMS (**med_erm** task) and the police
(**police_system** call). Patients get their injuries / vitals through **medsys**, fighters / hostiles / suspects
are **ai_peds** peds, criminal records go to the police database. Automatic generator, in-game editor, web console,
flagged scene issues. Every text is English + Hungarian (v_locals namespace `v_scenemanager`).

Was `[medical]/med_scenemanager` until 2026-11-02 (format 1: one `erm` block). Plan with mockups:
`docs/plan/index.html`.

## Layout

```
shared/config.lua     VSM tunables (agencies, safety, NPC, flag, generator, variety, editor), catalog tables (label = v_locals key)
shared/names.lua      ped name database (male / female first names, female skin list)
server/util.lua       log, notifications, permission (v_mysql admin_level), JSON + file helpers, ordered JSON writer
server/storage.lua    scenes/index.json + scene files, format 2 normalize (format 1 converted), validation, summaries
server/builder.lua    scene entry <-> vehicle / ped element, medsys (incl. the rolled alcohol / drug)
server/agencies.lua   one adapter per agency: ems (med_erm), pd (police_system)
server/npc.lua        fighter / hostile / suspect on ai_peds, criminal records (pol.profile), vehicle records
server/safety.lua     safe scene: threats, automatic + reported "safe", staging point, HUD tracker
server/live.lua       live scenes: spawn, agency tasks, late join, PD auto close, cleanup
server/variety.lua    scene variety: history (data/variety.json), rules, weights
server/auto.lua       automatic generator (agency rule) + /scenerandom, /sceneauto, /scenelist ...
server/summon.lua     /scenesummon
server/issues.lua     scenes/issues.json, /flagscene, v_chat command registration
server/editor.lua     editor sessions, R menu actions, validation on save, Check issues
server/interact.lua   ui_interactobject menus on the editor's vehicles / peds (role, AI, record, tow, stolen)
server/exports.lua    public API
server/web.lua        web console API (texts, scenes, live, flag, issues)
client/editor.lua     banner, R menu (ui_inac temp menu), text input (ui_core), 3D labels
client/summon.lua     /scenesummon menu
client/safety.lua     ui_core stat tracker of the officers at an unsafe scene
scenes/               index.json (never edited by hand from tools), issues.json, <Settlement>/[<category>/]<name>.json
```

## Scene format 2

```json
{
    "format": 2, "name": "ls_armed3", "category": "armed", "location": "Los Santos",
    "enabled": true, "weight": 1, "center": [x, y, z], "interior": 0, "dimension": 0,
    "safe": false,                       // only with ems.need 2 + pd.need 2; default true
    "agencies": {
        "ems": { "need": 2, "priority": 1, "caller": "SceneManager", "lateJoin": true,
                 "locales": { "en": { "title": "...", "description": "..." }, "hu": { ... } } },
        "pd":  { "need": 2, "priority": 1, "lateJoin": true, "locales": { ... },
                 "close": { "towed": true, "suspects": true } }      // automatic call close conditions
    },
    "vehicles": [ { "id": "v1", "model": 420, ...the format 1 fields...,
                    "tow": true,                                      // to be towed (police tow module)
                    "record": { "stolen": true, "owner": "random" | "none" | "p1", "inspection": "expired" } } ],
    "peds": [ { "id": "p1", "skin": 105, "pos": [...], "rot": 0, "anim": "none", "injuries": [], "state": {},
                "role": "patient" | "bystander" | "fighter" | "hostile" | "suspect",
                "ai": { ... by role, see below ... },
                "record": { "name": "", "age": [24, 38], "birth": "1991-04-12",
                            "flags": { "licence": "suspended", "bac": [0.8, 1.6], "drug": "stimulant", "flee": true },
                            "past": [ { "type": "fine" | "warning", "btk": "traffic.speeding", "daysAgo": [10, 60] } ],
                            "warrants": [ { "reasons": [ "crime.robbery" ], "description": { "en": "...", "hu": "..." } } ],
                            "announce": false, "persistent": false } } ]
}
```

- **need**: 0 = not needed (the block may be `{ "need": 0 }`, no texts), 1 = needed, 2 = mandatory. A needed agency
  (1 / 2) needs the title (and should have the description) in every language of `VSM.LANGS` (en, hu).
- **ai**: fighter `{ side a|b, weapon, start spawn|unit_near, startRadius, onPolice stop|flee|continue }`, hostile
  `{ targets police|all, weapon, ammo, accuracy, aggroRadius, leash, task guard|idle, surrenderHealth, flee }`,
  suspect `{ weapon, ammo, flee }`. Patients / bystanders have none (static, posed).
- **record**: ranges (`age`, `bac`, `daysAgo`) are rolled at every spawn (element data `vsm.rolled`); the alcohol /
  drug becomes the matching medsys condition too. `announce` = the police citizen row is made at spawn (MDC
  search, warrant listed), else at the first police contact. `persistent` = the same citizen at every spawn
  (`pol_citizens.ext_key = scene:<name>:<ped id>`).
- Format 1 files (`erm` block) are converted on load: `erm` -> `agencies.ems` with need 2, `pd` need 0.
- Files are written by the own encoder (`vsmEncodeJSON`, `KEY_ORDER`); every start rewrites files whose layout differs.

### Validation (`Storage.validate`, editor save, generator)

Errors keep a scene out of the generator and from being saved in the editor: no agency needed, a needed agency
without an en / hu title, `safe: false` without EMS 2 + PD 2, a hostile ped without PD 2, a hostile to every player
in a safe scene, fighters on one side only, unknown warrant reasons / penal items, a stolen vehicle owned by a scene
ped. Warnings: missing descriptions / warrant texts, a not safe scene without a threat, a vehicle to tow without the
police, an AI role in a vehicle (stays static).

## Agencies and the generator

- **Free unit**: EMS = med_erm `getFreeUnits`, PD = police_system `getFreeUnits` (status available), within the
  agency's `MAX_UNIT_DISTANCE` (interior scenes always in range). An agency is available while it has fewer waiting
  scene tasks than `PENDING_PER_UNIT` per free unit.
- **Rule** (never relaxed): every need-2 agency available with a free unit in range; without need-2 agencies one
  need-1 agency like that. Pace: random `INTERVAL_MIN..MAX` / (free units x `RATE`).
- **Spawn**: need 2 -> task; need 1 -> task when a unit of it is free in range (generator) or always (manual spawn).
  A need-1 agency without a task waits `LATE_JOIN` seconds: when one of its units frees up in range and the scene
  is still open, it gets the task too.
- The tasks of a scene are linked (ERM `meta.police = { call, status, units }`, police call `ermTask`): inter-agency
  chat both ways (ERM Messages "Inter-agency" tab, MDC call "Inter-agency" tab).
- A scene lives until every task is closed, then the usual cleanup (`CLEANUP_*`, `MAX_LIFETIME`). EMS: transport /
  false call close the ERM task like before. PD: `close` conditions close the call once a unit responded and the
  scene is safe.

## Safe scene (`server/safety.lua`)

Only EMS 2 + PD 2 scenes can start with `safe: false`. Threats: fighters, hostiles, armed suspects. A threat is
handled when cuffed, down (medsys), gone, surrendered with an officer within 15 m, or fled (> 120 m for 30 s).
Automatic safe: every threat handled + an officer of the call within 40 m of the centre. Manual: the MDC "Report
scene safe" (officer within 40 m, no active threat within 50 m). A handled threat fighting again makes it unsafe
again. The ERM task gets `meta.safety = { state, since, by, auto, staging }`: the tablet shows the field, warns the
crew at 200 m (window + sound), repeats it within 100 m and routes it to the staging point; the call cannot be closed
while unsafe, its officers near the scene see a HUD tracker. Every change is a system line in both channels.

## Flagged scenes

`/flagscene <reason...>`: anyone, within `FLAG.RADIUS` (80 m) of a live scene, 5-200 characters, 60 s cooldown, one
open issue per scene (a second report is refused). Web console: Flag button on every scene. Stored in
`scenes/issues.json` (`{ format, seq, issues = [ { id, scene, path, comment, lang, source, by, byName, at, pos,
instance, server, status, resolvedBy, resolvedAt } ] }`). No admin notification. Editor: R -> Check issues (button
description = the report), a loaded scene's Issues menu (teleport to the spot, mark resolved); web Issues tab.

## Commands (admin_level >= `MIN_ADMIN_LEVEL`, from v_mysql; /flagscene for everyone)

| command | |
|---|---|
| `/sceneeditor` | toggles the editor |
| `/scenerandom [name]` | spawns a random (or the named) scene now, every needed agency gets its task |
| `/scenesummon` | pick an exact scene from a menu and spawn it |
| `/sceneauto [on\|off]` | generator status / switch |
| `/scenelist` | live scenes |
| `/sceneclear [id\|all]` | removes live scenes (and closes their tasks) |
| `/scenereload` | re-reads the scene files |
| `/scenevariety [sim [n] \| clear]` | variety history + last pick, dry-run picks, delete history |
| `/flagscene <reason...>` | flags the scene you are at |

All are registered in the v_chat command database (descriptions are v_locals keys).

## Editor

R menu: Agencies (need, priority, texts EN / HU, late join, caller, PD auto close, safe at start), Peds, Vehicles,
Random generator, Location, Category, centre, Validation, Issues, Teleport, Save / Save as (validation errors stop
the save), Leave, Exit. Main menu: New scene, Load scene, Check issues, Exit. X menu on a ped: role, AI settings,
criminal record (name, age, licence, BAC range, drug, flee, past items, warrant reasons + texts, create at spawn,
same person), pose, injuries, medical state, skin, seat. On a vehicle: tow, police record (stolen, owner,
inspection), damage, colour, options, plate, model. The editor never runs AI or medsys.

## Exports (server)

```lua
exports.v_scenemanager:spawnScene(name)            -- instanceId, warning | false, error
exports.v_scenemanager:removeScene(id)
exports.v_scenemanager:getSceneAt(x, y, z [, r])   -- instanceId, name, ermTaskId | false, policeCallId | false
exports.v_scenemanager:getActiveScenes()           -- { { id, name, taskId, tasks, late, source, center, ..., safety } }
exports.v_scenemanager:getSceneList()              -- summaries (needs, safe, valid, errors, warnings, titles)
exports.v_scenemanager:getSceneData(name)          -- format 2 scene
exports.v_scenemanager:validateSceneData(scene)    -- { { level, key, params, text } }
exports.v_scenemanager:saveSceneData(name, scene [, overwrite])  -- format 1 or 2 accepted
exports.v_scenemanager:getCatalog() / getAutoGenerate() / setAutoGenerate(on [, by]) / getSceneIssues([status])
```

Events (resource root): `onSceneSpawned(id, name, tasks)`, `onSceneRemoved(id, name, reason)`,
`onSceneAutoChange(enabled, by)`, `onSceneFlagged(issue)`. Live elements carry `vsm.scene` = instance id.

Used from the other resources: med_erm `setTaskMetaField`, `postAgencyMessage`; police_system `getFreeUnits`,
`createSceneCall`, `closeSceneCall`, `getCall`, `setCallSafety`, `setCallLink`, `postCallMessage`,
`isOfficerOnDuty`, `registerNPC`, `getPenalItems`; ai_peds `createAIPed` (`hostilePlayers`), `setAIPedCombat`.
