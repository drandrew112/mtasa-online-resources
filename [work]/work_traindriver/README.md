# work_traindriver

Train driver work on [work_core](../work_core/README.md). Going on duty gives the rw_core
railway role (`setPlayerRailway`, "vasutas jog"); going off duty (or quitting) takes it away.
It is re-granted after an rw_core restart.

- No vehicle marker: trains come from the rw_core depot menu.
- Duty markers and outfits are in `shared/config.lua` (`STATIONS`, `SKINS`). Currently one marker at
  the Unity Station depot (placeholder position, tune with `/workpos`).
- Exports: `isPlayerTrainDriver`, `getTrainDriverPlayers`, `getTrainDriverWorkId`.
- A role given by `/rwrole` is separate: duty end also removes it.

## Pay

`server/pay.lua` listens to rw_timetable's `onRailServiceComplete`. The player in the driver's seat
when the last stop is served (the one who closes the service) is paid through `work_core:payWork`
(itemised receipt, bank deposit by work_core). No pay for rw_auto trains, a driver not on duty or a
service with no stop served; cancelled/ended-early services never reach this event.
Items (amounts in `TRAINDRIVER.PAY`): line base (RB/IC), per served stop, punctuality bonus by
arrival delay, fines for skipped stops / early departures (optional delay fine). The total is never
below 0. `/testtraindriverpay [RB|IC]` (admin level 3) pays a made-up service.
