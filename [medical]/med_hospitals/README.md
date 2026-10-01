# med_hospitals

Hospitals for the EMS system. Together with `med_erm` they run the hospital handover of ambulance
units, and together with `medsys` they give free treatment. Every hospital, with all its markers,
is defined in `hospitals.json`.

## Markers (each one has a 3D DX label)

| kind | colour | what happens |
|---|---|---|
| **Ambulance Bay** (`bays`, any number) | yellow | An ERM unit with an active case stops its vehicle here (below `BAY_MAX_SPEED`) with a patient on its stretcher, and the unit becomes **Handover**. Without a patient the ambulance simply drives through. An occupied bay's marker has alpha 0, and it has no label. |
| **Patient Handover** (`handover`, any number) | blue | A medic pushes the patient in on the stretcher. After **5 s** the ped disappears, the ERM handover completes, and the task closes. |
| **Treatment** (`heal`, one) | green | A player standing here for **15 s** is healed completely (medsys `healCompletely` + full health). It is free. |

### Handover flow

1. The ambulance parks in a bay with a patient aboard (`med_stretcher` stretcher patient), and the
   unit goes to **Handover**. Without a patient nothing happens. The hospital owns the handover,
   so ERM's 30 s timer is not used.
2. If the ambulance leaves the bay during the handover, the unit goes to **En Route** until it parks
   in a bay again.
3. Stretcher handover is only possible under these conditions:
   - the stretcher's ambulance (`med_stretcher`) is in **Handover**,
   - it is parked in a bay of **the same hospital**,
   - the patient is lying on the stretcher,
   - the medic is pushing it.
4. After 5 s in the marker:
   - A ped patient is destroyed.
   - A player patient is taken off the stretcher, treated, and put at the hospital's `release` point.
     Without one, they are put next to the heal marker.
   - `exports.med_erm:completeHandover(unitId)` runs: the unit becomes Available, and the task closes.
5. Leaving the marker, or losing any condition, cancels the 5 s.

The ERM tablet has no Handover button any more, so the bay is the only way to start a handover.
The `onErmUnitHandoverRequest` listener stays in place but the event is no longer fired.
After a resource restart or `/hospreload`, a unit already in Handover whose vehicle is in a bay is
taken over again.

## hospitals.json

```json
{
    "hospitals": [
        {
            "id": "allsaints",                         // unique, used by the exports
            "name": "All Saints General Hospital",
            "interior": 0, "dimension": 0,             // optional, default 0
            "bays":     [ { "x": 0, "y": 0, "z": 0, "size": 4.0 } ],
            "handover": [ { "x": 0, "y": 0, "z": 0 } ],
            "heal":       { "x": 0, "y": 0, "z": 0 },  // optional
            "release":    { "x": 0, "y": 0, "z": 0, "rot": 90 }  // optional: handed-over players
        }
    ]
}
```

- `z` is the ground (where the cylinder marker stands). `size` is optional and falls back to `HOSP.*_SIZE`.
- The objective point is the first bay, or the heal / handover marker if there is no bay.
- The All Saints coordinates in the sample are **approximate**; check them in game.

## Admin commands (admin_level >= `HOSP.ADMIN_LEVEL`, from v_mysql)

- `/hosppos [fields]`: your position, at ground z, printed to the chat and the server log and
  **copied to the clipboard**. In a vehicle it takes the vehicle's position (for bays).
  - `/hosppos` gives a JSON point: `{ "x": 1179.30, "y": -1308.60, "z": 13.00, "rot": 90 }`
  - `/hosppos x,y,z` gives `{ "x": 1179.30, "y": -1308.60, "z": 13.00 }`
  - `/hosppos x,y,z,rot` gives `{ "x": 1179.30, "y": -1308.60, "z": 13.00, "rot": 90 }`
  - The fields are `x`, `y`, `z`, `rot` (or `rz`), `int` and `dim`. You can use any subset, in any order.
    `int` and `dim` are written as `"interior"` and `"dimension"`.
- `/hospreload`: re-reads `hospitals.json`. On an error, the old hospitals stay.

## Server exports

```lua
exports.med_hospitals:getHospitals()                       -- { {id, name, x, y, z, interior, dimension, bays, handoverMarkers, heal}, ... }
exports.med_hospitals:getHospital(id)                      -- every point, bays with their parked vehicle
exports.med_hospitals:getNearestHospital(element | x, y, z)    -- id, name, distance
exports.med_hospitals:setObjectiveToNearestHospital(player [, label])  -- hospitalId, objectiveId
exports.med_hospitals:setObjectiveToHospital(player, hospitalId [, label])  -- objectiveId
exports.med_hospitals:removeHospitalObjective(player)
exports.med_hospitals:getVehicleHospitalBay(vehicle)       -- hospitalId, bayIndex | false
exports.med_hospitals:getUnitHospitalHandover(unitId)      -- hospitalId | false
exports.med_hospitals:isPlayerHealing(player)
exports.med_hospitals:reloadHospitals()                    -- count | false, error
```

`setObjectiveToNearestHospital` places a v_radar objective (yellow blip and route) on the nearest
hospital in the player's interior and dimension. If there is none there, any hospital is used.
One hospital objective per player: a new one replaces the old one. It is removed within
`ARRIVE_RADIUS` (30 m).

## Server events (source = med_hospitals' resourceRoot)

```
onHospitalHandoverStart    (unitId, hospitalId)
onHospitalHandoverLeft     (unitId, hospitalId)                 -- left the bay -> En Route
onHospitalPatientHandover  (hospitalId, unitId, patient, medic, taskId | false)  -- before the ped is removed
onHospitalPlayerHealed     (player, hospitalId)
```

## Dependencies

- `med_erm`: units and handover. It got `getVehicleUnit` and `onErmUnitHandoverRequest` for this resource.
- `med_stretcher`: stretcher state. It got `takePatientOff` for this resource.
- `medsys`: healing.
- `v_radar`: objective.
- `v_mysql`: admin level, optional.
