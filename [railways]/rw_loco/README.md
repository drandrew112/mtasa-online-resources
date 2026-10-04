# rw_loco

Locomotive simulation (see `../README.md`). `LOCO.TYPES` maps a rolling stock type to its cab
panel module and the common modules (`timetable`, `sifa`).

- `server/loco.lua` owns battery / fuel pump / engine / lights / doors per consist and
  mirrors them to the lead (`rw.loco`, `rw.doors`).
- `client/core.lua` runs the modules of the loco the local player drives, lays them out
  around the minimap, handles the cursor (`rw_cursor`), click areas and the traction lock.
- `client/modules/br232.lua` - BR 232 desk (static parts in a render target).
- `client/modules/timetable.lua` - left panel (`rw_timetable` command) + small display.
- `client/modules/sifa.lua` - vigilance device (`rw_sifa` command).

A new loco type: add a panel module that calls `registerLocoModule(id, module)` and an
entry in `LOCO.TYPES` (plus the vehicle in `rw_core` `RW.VEHICLES`).

Exports: server `getLocoState(consistId)`, client `getSifaState() -> state, braking, secondsToNextCheck`.
Events: `onRailSifaBrake(consistId, player)`, `onRailEngineChange(consistId, eng)` (source: lead).
