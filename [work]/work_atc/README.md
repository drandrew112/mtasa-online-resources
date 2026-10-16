# work_atc

Air traffic controller work on [work_core](../work_core/README.md). Going on duty gives the ATC
rights of avi_core (`[aviation]`); which ones depends on the work level. Going off duty (or
quitting) resets them to the avi_core defaults. Rights are re-applied after an avi_core restart
and on every level change while on duty.

- One duty marker for now: outside the SA Control building in San Fierro (`ATC.STATIONS`, placeholder position, tune with `/workpos`).
  More stations can be added to the list later.
- The ATC markers of avi_core are visible only on duty in this work (`AVI.MARKER_WORK = "atc"`).
- **Work XP and pay are not given here**: avi_controller calls `work_core:giveWorkXp(player, "atc", xp)` after every accepted traffic action, and `payWork` when the controller logs out of a position (tune in `avi_controller/shared/config.lua`: `XP_*`, `PAY_*`).

## Levels (`ATC.LEVELS`)

| level | name | rights |
|---|---|---|
| 1 | Trainee | TWR |
| 2-4 | Tower Controller Bronze / Silver / Gold | TWR |
| 5-7 | Approach Controller Bronze / Silver / Gold | TWR + APP |
| 8-10 | Radar Controller Bronze / Silver / Gold | TWR + APP + RADAR |
| 11-13 | Senior Controller Bronze / Silver / Gold | TWR + APP + RADAR |
| 14 | Supervisor | TWR + APP + RADAR |

Rights are cumulative (a higher rank keeps the lower positions); change the `rights` lists in
`shared/config.lua` if each level should only get its own. XP curve: `LEVEL_BASE_XP`, `LEVEL_STEP_XP`.
`/setworklevel <player> atc <level>` (work_core, admin) for testing.

Exports: `isPlayerATC`, `getATCPlayers`, `getATCWorkId`, `getATCLevelRights(level)`.

## Tutorial

`tutorial/` (see [tutorial/README.md](tutorial/README.md)): an optional tower tutorial on SASF_TWR in
the SA Control room, offered on the first duty start, `/tutorial_atc` any time. It uses the tutorial
hooks of avi_core (console marker copy), avi_controller (tutorial login: no pay, no XP, the live
position stays free) and avi_traffic (tutorial aircraft in a world of their own).
