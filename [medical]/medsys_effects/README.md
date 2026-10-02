# medsys_effects

What a player **experiences** from their own medical state, and the **forced animations** of every
patient (players and peds). medsys only simulates; this resource shows it.

It took over:
- from **medsys**: the down / get-up animations, the blackout / dazed overlay and the control lock
  (`client/patient.lua`, `medic:selfStatus` are gone)
- from **medsys_events**: the controls disabled by the injuries (`MEDEV_EFFECTS` is now
  `MEDFX_INJURY_EFFECTS`; the body parts still come from `exports.medsys_events:getInjuryDetails`)

## Architecture

```
shared/config.lua    MEDFX tunables, animations, state / injury / screen effects, test settings
server/state.lua     follows medic.status, writes the animation key, sends players their condition, walking style
server/exports.lua   setAnimationBlocked / isAnimationBlocked / getForcedAnimation
server/test.lua      admin test (/medfx)
client/anim.lua      keeps the forced animation on every streamed player / ped
client/effects.lua   local player: screen effects, camera shake, disabled controls
client/test.lua      admin test menu, visual preview
```

## Forced animations

The server writes the key into `medfx.anim` from the consciousness (`MEDFX_STATE_ANIM`):

| | dazed | unconscious / clinical death |
|---|---|---|
| player | (none, the player can move) | `down` (KO_shot_front, held) |
| ped | `dazed_ped` (sitting on the ground) | `down` |

Every client re-checks the streamed elements every `ANIM_CHECK` ms and plays the animation again
when something else replaced it, e.g. a **med_scenemanager pose** that does not fit the state. An
animation in the key's `accept` list is kept (a lying scene pose stays as it is). When the state
ends, the element gets up (`release`).

Not forced: dead elements, anybody **in a vehicle**, **on a stretcher** (`stretcher.on`), attached
to something, or blocked by another script:

```lua
exports.medsys_effects:setAnimationBlocked(ped, true)   -- e.g. while it is carried
exports.medsys_effects:setAnimationBlocked(ped, false)
exports.medsys_effects:getForcedAnimation(ped)          -- "down" | "dazed_ped" | false
```

## Player effects

Sent only to the player, only when something changed (`medfx:state`):

| source | effect |
|---|---|
| dazed | dark pulsing bars, red tint, camera shake, drunk walk, no sprint / jump |
| unconscious / clinical death | blackout with text (countdown in clinical death), every control locked |
| pain 30+ | red edges pulsing with a heartbeat, faster with more pain; shake from 70 |
| bleeding 1-3 | blood at the screen edges |
| SpO2 below 93% | tunnel vision |
| blood volume below 85% | pale / grey picture |
| new injury | red flash + short shake |
| leg / pelvis fracture | no sprint / jump, limping walk (splinted: no sprint) |
| arm fracture | no aiming / shooting |

Painkillers lower the pain value in medsys, so they lower the pain effect too.

## Admin test

`MEDFX_TEST.ENABLED`, `admin_level >= 4` (v_mysql). `/medfx` opens the menu:
- **Preview (visual only)**: lays any state over your screen without touching medsys.
  Blackout previews end after 10 s; `/medfxstop` clears the preview.
- **On yourself (medsys)**: real knockouts, pain, bleeding, SpO2, blood loss, leg / arm fracture, heal.
  `/medfx heal` works from behind a blackout too.
- **Animation peds**: unconscious / dazed / clinical death peds, a standing pose that is overridden,
  a lying pose that is kept, a ped that wakes up. `/medfx clear` removes them.
