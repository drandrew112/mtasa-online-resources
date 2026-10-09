# med_bag

Every ambulance (416, 456) carries one **medical bag** and one **monitor / defibrillator**. Without
them a medic can only examine, run the neuro exam, do CPR and request transport (medsys). The bag
holds the medicines, IV kits and oxygen, which run out and are restocked in a hospital bay.

Full design: [DESIGN.md](DESIGN.md).

## Use

| Where | What |
|---|---|
| Ambulance side door, `X` menu | take / put back the bag, the monitor or both, restock (in a hospital bay), check contents |
| `H` | put the carried items down in front of you |
| An item on the ground, `X` menu | pick up |
| Starting a treatment | carried items are put down beside the patient |
| Entering your own ambulance | carried items are stowed |

Items must be within 4 m of the patient. Items left at a scene warn the crew (blip + notification)
and return empty to their ambulance after 10 minutes.

## Admin

- `/bagpos`: your offset from the nearest ambulance, for `BAG.SIDE_POINT` in `shared/config.lua`.
- `/bagreset`: returns the nearest ambulance's items into it (stock kept).

## Removing the static monitor screen

Delete `client/screen.lua` and `fx/screen.fx` from meta.xml (or set `BAG.STATIC_SCREEN = false`).
