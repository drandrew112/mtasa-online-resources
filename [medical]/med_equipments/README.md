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
