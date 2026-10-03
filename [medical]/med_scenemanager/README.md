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
server/storage.lua    scenes/index.json + scenes/<Settlement>/[<category>/]<name>.json, summaries
server/builder.lua    scene entry <-> vehicle / ped element (capture, apply, medsys)
server/live.lua       live scenes: spawn, ERM task, cleanup after the task closed
server/auto.lua       automatic generator + /medscenerandom, /medsceneauto, /medscenelist ...
server/editor.lua     editor sessions, R menu actions, load / save
server/interact.lua   ui_interactobject menus on the editor's vehicles / peds
server/exports.lua    public API
client/editor.lua     banner, R menu (ui_inac temp menu), text input (ui_core), 3D labels
scenes/               index.json + <Settlement>/[<category>/]<name>.json per scene
```

## Scene files

Scenes are grouped by settlement, then by category:

```
scenes/Los_Santos/heartattack/ls_heartattack1.json
scenes/Los_Santos/mva/mva1.json
scenes/Los_Santos/hypertension/hypertension1.json
scenes/Los_Santos/ls_stunt-accident.json        (no category: no subfolder)
scenes/Lil_Probe_Inn/heartattack/lil-probe-inn_heartattack1.json
```

- **Settlement** is automatic, from the scene centre: `Los_Santos`, `San_Fierro`,
  `Las_Venturas` (`getZoneName(..., true)`), anywhere else the zone name (village / area,
  `getZoneName(..., false)`), spaces → `_`, apostrophes dropped. Interior scenes go to `Interiors`.
- **Category** is the scene's `"category"` key: `heartattack`, `mva`, `hypertension` (`MSM_CATEGORIES`) or
  `""` (none). A file without the key gets the first category found in its name. In the
  editor: R menu → *Category*.
- Scene names stay unique over all folders and never contain the folder.

Both are applied on every save, so a scene whose centre or category changed is moved to
its new folder (the old file is deleted). On load a file in the "wrong" folder only logs a
warning; it moves on its next save.

MTA cannot list a directory, so `scenes/index.json` lists the scene paths relative to
`scenes/`, without `.json` (`{ "scenes": [ "Los_Santos/mva/mva1", ... ] }`). The editor keeps
it up to date. If you add a JSON by hand, also add its path to the index and run
`/medscenereload`.

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
ivAccess, spo2, systolic, diastolic, heartRate, consciousness, rhythm (medsys heart rhythm, e.g.
`"VF"`; a pulseless one starts the patient in cardiac arrest with that rhythm). The vitals (spo2, systolic,
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
another live scene is closer than `MIN_SCENE_DISTANCE`, or when no free unit is within
`MAX_UNIT_DISTANCE` (2D, interior scenes are always in range; 0 = no limit). On / off: `/medsceneauto on|off` or
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

- no scene: **New scene** (centred on you), **Load scene** (follows the folders: settlement →
  its scenes + category subfolders, e.g. Los Santos → Heart attack → ls_heartattack1), Exit editor
- scene loaded:
  - **ERM task**: title, description, caller, priority P1-P4, *Set centre to my position*
  - **Peds**: *Add ped here* (your position + heading), list (teleport to it)
  - **Vehicles**: *Add vehicle (model)* creates the vehicle on your position and puts you
    in it. Drive it into place, then *Save my vehicle position & state*. The list teleports you to a vehicle.
  - **Random generator**: enabled, weight
  - **Teleport to scene** (ERM centre), **Save** (only after the first Save as),
    **Save as** (file name; folder from centre + category), **Category**, **Leave scene** (asks when there are unsaved changes)

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
exports.med_scenemanager:getCatalog()        -- editor tables: anims, injuries, state keys / presets / order, damage presets, skins...
exports.med_scenemanager:saveSceneData(name, scene [, overwrite]) -- true | false, 'exists' | error (never a scene open in the editor)
```

`getCatalog` / `saveSceneData` are used by the claude-mcp medical module (`[devtools]/claude-mcp/docs/medical.md`).

Events (resource root): `onMedSceneSpawned(id, name, taskId|false)`,
`onMedSceneRemoved(id, name, reason)`, `onMedSceneAutoChange(enabled, by)`.

Live scene elements carry the element data `msm.scene` = instance id (not synced).
