# work_ems

The EMS work, built on **work_core**. Its only jobs are giving and taking the medsys medic role
and providing the vehicle. Everything medical (examination, stretcher, ERM tablet, hospitals)
is in the `[medical]` resources.

- **Duty marker** (work_core): choose an outfit (276 OMSZ, 274, 275) and you go on duty. This
  gives `exports.medsys:setPlayerMedic(player, true)`. Going off duty or quitting takes it away.
  After a medsys restart the role is given back.
- **Duty vehicle marker**: Ambulance (416) only, for now. The plate is `A-` plus 4 random digits
  (work_core `platePrefix`). v_els, med_stretcher and med_erm handle the vehicle by its model.
- **med_erm**: only medics can sign in on the tablet (J). Losing the role removes the player
  from their unit.
- medsys `MEDIC.REQUIRE_MEDIC_ROLE = true`: only on-duty EMS players can examine or treat.

Settings (stations, skins, vehicles, plate) are in `shared/config.lua`. The positions are
placeholders: fine-tune them with `/workpos`.

## Tutorial

The optional EMS tutorial is a module in its own folder, `tutorial/`, described in
[tutorial/README.md](tutorial/README.md). It is offered on the first duty start, and `/tutorial_ems`
starts it at any time.

## Modules

Inside the resource, add a server file after `server/modules.lua` in meta.xml:

```lua
EmsModules.register("tutorial", {
    canGoOnDuty    = function(player) return false, "Finish the EMS tutorial first." end,
    onDutyStart    = function(player, skin) end,
    onDutyEnd      = function(player, reason) end,
    onVehicleSpawn = function(vehicle, player) end,
})
```

From another resource, use the same points as events:

| event | source | args |
|---|---|---|
| `onEmsDutyRequest` | player | cancellable: `cancelEvent(true, "reason")` shows the reason |
| `onEmsDutyStart` | player | `skin` |
| `onEmsDutyEnd` | player | `reason` (work_core reason) |
| `onEmsVehicleSpawn` | vehicle | `player` |

Server exports: `isPlayerEms(player)`, `getEmsPlayers()`, `getEmsWorkId()`.
