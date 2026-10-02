# med_scenemanager – Med Scene Manager

Medical scenes (accidents, injured people) stored as JSON files. A scene spawns its
vehicles and injured peds in the world and creates a **med_erm** task for it. The peds
get their injuries / vitals through **medsys**. The resource has an automatic task
generator and an in-game scene editor.

## Layout

```
shared/config.lua     MSM tunables, ped poses, injury / vitals presets, damage + colour presets
shared/names.lua      ped name database (male / female first names, female skin list)
server/util.lua       permission (v_mysql admin_level), JSON + file helpers
server/storage.lua    scenes/index.json + scenes/<name>.json, in-memory summary list
server/builder.lua    scene entry <-> vehicle / ped element (capture, apply, medsys)
server/live.lua       live scenes: spawn, ERM task, cleanup after the task closed
server/auto.lua       automatic generator + /medscenerandom, /medsceneauto, /medscenelist ...
server/editor.lua     editor sessions, R menu actions, load / save
server/interact.lua   ui_interactobject menus on the editor's vehicles / peds
server/exports.lua    public API
client/editor.lua     banner, R menu (ui_inac temp menu), text input (ui_core), 3D labels
scenes/               index.json + one JSON file per scene
```

## Scene files

MTA cannot list a directory, so `scenes/index.json` lists the scene names
(`{ "scenes": [ "name", ... ] }`). The editor keeps it up to date. If you add a JSON by
hand, also add its name to the index and run `/medscenereload`.

The files are written by our own JSON writer (`msmEncodeJSON` in server/util.lua): fixed key
order (`KEY_ORDER`: scene → erm → vehicles → peds, every entry id / model / skin / pos / rot
first), 4-space indent, short lists and plain objects (pos, colors, an injury, state) on one
line. On every start / `/medscenereload` the scene files and the index are re-read and rewritten in
this format when they differ (hand-edited files get normalized as well).

On start every file is read once and only a **summary** stays in memory (name, title,
priority, centre, weight, enabled, counts). The full scene is read from its file when it
is spawned or opened in the editor.

```json
{
    "format": 1, "name": "example_grove_crash",
    "enabled": true,              // false = never picked at random
    "weight": 1,                  // random pick weight
    "center": [x, y, z], "interior": 0, "dimension": 0,
    "erm": { "title": "...", "description": "...", "caller": "...", "priority": 1 },
    "vehicles": [ {
        "id": "v1", "model": 405, "pos": [x, y, z], "rot": [rx, ry, rz],
        "colors": [12 numbers], "health": 420,
        "doors": [6], "panels": [7], "lights": [4], "wheels": [4],
        "engine": false, "lightsOn": true, "sirens": false, "locked": false,
        "frozen": true,           // frozen in the live scene (never in the editor)
        "plate": "ABC 123", "paintjob": 3, "upgrades": [], "variant": [255, 255]
    } ],
    "peds": [ {
        "id": "p1", "skin": 15, "pos": [x, y, z], "rot": 95,
        "anim": "ko_back",        // MSM_ANIMS id
        "vehicle": "v1", "seat": 0, // optional: sits in that scene vehicle
        "frozen": false,
        "injuries": [ { "type": "gunshot", "severity": 3 } ],   // medsys applyInjury
        "state": { "consciousness": "unconscious", "spo2": 82 }  // medsys setMedicalState
    } ]
}
```

`state` keys are applied in the order of `MSM_STATE_ORDER`: bloodVolume, pain, bleeding,
ivAccess, spo2, systolic, diastolic, heartRate, consciousness. The vitals (spo2, systolic,
diastolic, heartRate) go to medsys as its lasting `resting*` keys (`MSM_STATE_RESTING`): the
patient settles at and holds them (later blood loss, medicines, oxygen, the pain fading act on
top). A plain `systolic` etc. would drift back to normal within seconds.

Every live scene ped gets a random English first name on spawn (`shared/names.lua`, female or
male list by the skin), stored as element data `medic.name` (`MSM.DATA_NAME`); medsys shows it
as the patient name.

## Live scenes

`Live.spawn` creates the vehicles, then the peds (seated or posed). It applies medsys
`MEDSYS_DELAY` ms later, then calls `med_erm:createTask(title, description, centre,
caller, nil, meta)` with
`meta = { scene, sceneInstance, priority, patients }`. The task is created **without** a
priority. med_erm_auto (or the dispatcher) sets it from `meta.priority`.

A scene stays until its ERM task closes. After that it is removed once no player is
within `CLEANUP_RANGE` for `CLEANUP_DELAY` seconds, and at the latest after
`CLEANUP_FORCE`. A task that never closes is closed after `MAX_LIFETIME`. When this
resource stops, its open tasks are closed.

## Automatic generator

It only runs while med_erm has **free units** (no task, Available). It waits a random
`INTERVAL_MIN..INTERVAL_MAX` seconds, **divided by the number of free units**, before the
next scene. It allows at most `PENDING_PER_UNIT` waiting (unassigned) scene tasks per free
unit and `MAX_ACTIVE` live scenes. The scene is a weighted random pick among enabled,
inactive scenes. A scene is skipped when a player is closer than `MIN_PLAYER_DISTANCE` or
another live scene is closer than `MIN_SCENE_DISTANCE`. On / off: `/medsceneauto on|off` or
the `autoEnabled` setting.

## Commands (admin_level >= `MIN_ADMIN_LEVEL`, from v_mysql)

| command | |
|---|---|
| `/medsceneeditor` | toggles the editor |
| `/medscenerandom [name]` | spawns a random (or the named) scene now, free units not required |
| `/medsceneauto [on\|off]` | generator status / switch |
| `/medscenelist` | live scenes |
| `/medsceneclear [id\|all]` | removes live scenes (and closes their tasks) |
| `/medscenereload` | re-reads the scene files |

## Editor

`/medsceneeditor` moves you into a private dimension (`EDITOR_DIMENSION` + n). A banner
at the top shows **Med Scene Editor / Press R to show menu**. Leaving the editor unloads
the scene and puts you back where you started. Dying or quitting does the same. The editor
never starts the medsys simulation. Injuries / vitals only take effect in live scenes.

**R menu** (ui_inac temp menu):

- no scene: **New scene** (centred on you), **Load scene**, Exit editor
- scene loaded:
  - **ERM task**: title, description, caller, priority P1-P4, *Set centre to my position*
  - **Peds**: *Add ped here* (your position + heading), list (teleport to it)
  - **Vehicles**: *Add vehicle (model)* creates the vehicle on your position and puts you
    in it. Drive it into place, then *Save my vehicle position & state*. The list teleports you to a vehicle.
  - **Random generator**: enabled, weight
  - **Teleport to scene** (ERM centre), **Save** (only after the first Save as),
    **Save as** (file name), **Leave scene** (asks when there are unsaved changes)

**X menu on the elements** (ui_interactobject, only you see it):

- vehicle: *Save position & state* (positions are **never** recorded automatically), get
  in, damage presets, colour, options (engine, lights, sirens, locked, frozen in the live
  scene), plate, model, delete
- ped: move to my position, face me, pose, injuries (add / remove), medical state presets,
  skin, seat in the nearest scene vehicle / take out, delete

Each scene file can be open in only one editor at a time.

**Key note:** the editor menu is on `R` (`MSM.KEY_MENU`), not E: E is ui_interactobject's
"next menu" key and the two clashed.

## Exports (server)

```lua
local id, warning = exports.med_scenemanager:spawnScene(name)   -- false, error on failure
exports.med_scenemanager:removeScene(id)
exports.med_scenemanager:getActiveScenes()   -- { { id, name, taskId, source, center, createdAt, closed, peds, vehicles } }
exports.med_scenemanager:getSceneList()      -- summaries
exports.med_scenemanager:getSceneData(name)  -- full scene from its file
exports.med_scenemanager:getAutoGenerate() / setAutoGenerate(bool [, by])
```

Events (resource root): `onMedSceneSpawned(id, name, taskId|false)`,
`onMedSceneRemoved(id, name, reason)`, `onMedSceneAutoChange(enabled, by)`.

Live scene elements carry the element data `msm.scene` = instance id (not synced).
