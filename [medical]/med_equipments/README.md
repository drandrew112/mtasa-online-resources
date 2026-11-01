# med_equipments

EMS equipment, in modules (merged on 2026-10-29 from `med_bag` and `med_stretcher`):

| module | what | details |
|---|---|---|
| `bag/` | medical bag + Lifepak 15 per ambulance (v_inventory items), side-door menu, stock, restock at hospitals, left-behind warning, the equipment on the stretcher | bag/README.md, bag/DESIGN.md |
| `stretcher/` | ambulance stretcher: take out, push, carry a patient, load into the ambulance | stretcher/README.md |

The bag module calls the stretcher module directly (same resource); the stretcher events
(`onStretcherPushStart`, `onStretcherTakeOut`, `onStretcherLoaded` ...) still fire on the stretcher
object for other resources. All exports of both are `exports.med_equipments:...`
(medsys' equipment adapter: `MEDIC.EQUIPMENT_RESOURCE = "med_equipments"`).

The texts keep their `med_bag.*` / `med_stretcher.*` v_locals keys. ACL: `resource.med_equipments`
is in the DebugHook group (new ambulances are found through `addDebugHook(createVehicle)`).

## Which vehicles carry equipment (2026-11-01)

Only vehicles with the element data `med.equipment` (`shared/equipment.lua`) get a kit and a
stretcher; the model lists (`BAG.VEHICLE_MODELS`, `STRETCHER.VEHICLE_MODELS`) only say which models
can carry it. work_ems sets it on every duty vehicle (work_core vehicle `data`, `EMS.EQUIPMENT_DEFAULT`
or a vehicle's own `equipment`) and on the tutorial ambulance. Other ambulances (blood transport 598,
scene / AI transport vehicles, admin spawns) carry nothing.

The value is the equipment level: `"basic"` (only the stretcher), `"bls"` or `"als"`.
`BAG.LEVELS[level]` gives the kit's kinds and the bag's full stock (fill, restock, low-stock warnings
use it; an unknown level gets the BLS stock, never the ALS one). Since 2026-11-01 work_ems hands out
vehicles with `"basic"`, med_erm sets `"bls"` (BLS, SOLO) or `"als"` (ALS, DOC, HELI) at sign-in and
`"basic"` at sign-out. BLS: basic medicines only (no Fentanyl, Adrenaline, Ketamine, Rocuronium, no
airway kit), 15 minute oxygen; ALS: everything, 25 minute oxygen (cylinder `meta.minutes`). Exports: `setVehicleEquipment(vehicle, "bls" | "als" | true | false)`,
`getVehicleEquipment(vehicle)`; `getVehicleKit` also returns `level` (and `monitor` may be nil for a
level without a Lifepak). Changing the level rebuilds the kit.
