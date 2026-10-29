# med_equipments / bag module (was med_bag)

Every ambulance (416, 456) carries one **medical bag** and one **Lifepak 15** (monitor / defibrillator),
both v_inventory items. Without them a medic can only examine, run the neuro exam, do CPR and request
transport (medsys). The bag holds the medicines, IV kits, bandages, splints, the oxygen cylinder, the
glucometer and the airway kit; the consumables run out and are restocked in a hospital bay.

Full design: [DESIGN.md](DESIGN.md).

## Use

| Where | What |
|---|---|
| Ambulance side door, `X` menu | take / put back the bag, the monitor or both, restock (in a hospital bay), check contents |
| `H` (v_inventory) | put the carried items down in front of you |
| `I` (v_inventory) | inventory window: the bag's contents, moving things between bags |
| An item on the ground, `X` menu (v_inventory) | pick up / open |
| The stretcher menu | put the items on the stretcher / take them off |
| Starting a treatment | carried items are put down beside the patient |
| Vehicles | cannot be entered with anything in the hands: put the items back at the side door |

Items must be within 4 m of the patient. Items left at a scene warn the crew (blip + notification)
and return empty to their ambulance after 10 minutes.

## Admin

- `/bagpos`: your offset from the nearest ambulance, for `BAG.SIDE_POINT` in `shared/config.lua`.
- `/bagreset`: returns the nearest ambulance's items into it (stock kept).

## Removing the static monitor screen

Delete `client/screen.lua` and `fx/screen.fx` from meta.xml (or set `BAG.STATIC_SCREEN = false`).
