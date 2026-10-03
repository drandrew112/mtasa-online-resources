# Medical module

A separate capability group (`medical_*` tools, bridge category `medical`) built
on the generic modules. It does not change how the generic tools work: a medical
scene is a workspace of kind `"medical"` whose meta holds the ERM task data, and
patients are peds with `meta.role = "patient"` and
`meta.medical = { anim, injuries, state }`. Any generic tool (placement,
validation, screenshots, export) works on scene entities.

Dependencies: **med_scenemanager** (catalog, save, load, live scenes; needs the
`getCatalog` / `saveSceneData` exports added for this module), **medsys** (only
for `medical_simulate_patient`), **med_erm** (live scenes create tasks).

## Tools

| tool | |
|---|---|
| `medical_get_catalog` | poses, injuries + severities, medsys state keys (ranges, presets, apply order), rhythms, damage / colour presets, ERM defaults, templates |
| `medical_create_scene` | scene workspace + ERM title / description / caller / priority, generator enabled / weight |
| `medical_add_vehicle` | vehicle with semantic placement + damage preset, lights, sirens, role, liveFrozen |
| `medical_add_patient` | patient by skin or sex, placement, pose, injuries, state, or seated in a scene vehicle |
| `medical_set_patient` | change pose / injuries / state |
| `medical_build_from_template` | complete scene at a real location (see below) + validation + optional screenshot |
| `medical_validate_scene` | generic validation + medical / EMS checks |
| `medical_simulate_patient` | start / stop medsys on a patient and read its vitals |
| `medical_export_scene` | med_scenemanager JSON (optionally saved to `scenes/<name>.json` + index) |
| `medical_load_scene` | load a saved scene into a workspace for editing |
| `medical_live_scene` | saved files, live scenes, spawn (real ERM task!), remove |

## Templates

| template | content |
|---|---|
| `t_bone_intersection` | nearest intersection: car A drives into the junction, car B from the most perpendicular leg hits its side; one patient thrown out on the other side, one dazed in B's driver seat |
| `rear_end` | two cars in a lane, one patient sitting on the sidewalk |
| `pedestrian_struck` | car in a lane, patient lying 2.5 m in front of it |
| `motorcycle_crash` | bike on the road, rider lying 4 m away |
| `cardiac_arrest_sidewalk` | patient in VF on the sidewalk, bystander kneeling (CPR pose) |

Templates use the road graph and live placement; the result is a draft — read
the validation, look at a `capture_view {workspace, overlay: true}`, adjust,
re-validate, then export.

## Medical validation

On top of the generic checks:

| type | |
|---|---|
| `no_patients` (error) | no ped with medical data |
| `no_injuries` | patient without injuries and state (medsys would discharge it) |
| `erm_title` / `erm_description` | empty ERM fields |
| `far_from_center` | patient > 60 m from the ERM centre |
| `stretcher_space` | fewer than 4 of 12 directions have 1.2 m free around the patient |
| `patient_on_road` (info) | lying on the road surface |
| `no_ambulance_access` (error) | no free road spot for an ambulance (default model 416) within 35 m |
| `no_direct_path` | the nearest ambulance spot has no clear line to the patient |

`result.medical.access[]` lists each patient's ambulance spot (position,
heading, distance, line of sight) and free headings.

## Export format

`medical_export_scene` reads every value back from MTA and produces the
med_scenemanager format 1 (see `[medical]/med_scenemanager/README.md`): centre,
ERM data, vehicles (`v1…`: model, pos, rot, damage states, colours, plate,
paintjob, variant, upgrades, engine / lights / sirens / locked, `frozen` =
`liveFrozen`) and peds (`p1…`: skin, pos, rot, anim, vehicle + seat,
injuries, state). Non-patient peds are exported without injuries. The scene
dimension is always 0 (live scenes spawn in the main world). Saving never
overwrites without `overwrite: true` and never touches a scene open in the
in-game editor. Saved scenes with `enabled: true` join the random generator.
