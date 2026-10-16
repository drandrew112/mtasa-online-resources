# work_atc training modules (SCOPE / ADC / APC / ACC)

A short tour of the radar scope (SCOPE) and three training modules, one for each controller
position. Only SCOPE teaches the scope itself; the position modules take it as known. They fully
replace the old tower tutorial
(`tutorial/`, `/tutorial_atc`). Each module runs in the SA Control operations room (interior 3) in a
dimension of its own, starting at `TRAINING.DIMENSION_BASE`, on the real scope with training
aircraft that only the player sees.

| module | position | unlocked by (avi_core right) | what it teaches |
|---|---|---|---|
| **SCOPE** The radar scope | SASF_TWR | TWR (level 1) | console, where everything is on the scope (top bar, AT / FIXL / V-+, zoom and move, lists, buttons); the label and the command menu of a departure at its stand (only shown); Logout. About 5 min |
| **ADC** Aerodrome Controller | SASF_TWR | TWR (level 1) | console; IFR clearance, pushback, taxi, take-off; landing clearance, taxi in; alerts, pay |
| **APC** Approach Controller | SASF_APP | APP (level 5) | the TMA; a departure climbing to 5000 ft and leaving the TMA; an arrival on its STAR (descent to 1500 ft, Cleared approach); an arrival on radar vectors; the LOA rules |
| **ACC** Area Control Centre | SACC_CTR | RADAR (level 8) | the CTA and its sectors; an overflight (level, Direct to); a head-on conflict pair at the same level; an arrival descended to 4000 ft for the TMA entry fix; alerts, pay |

The levels come from `ATC.LEVELS` (the first level whose rights include the right).

- **Where:** the training marker in the operations room (`TRAINING.MARKER`, int 3 dim 0), visible to
  players on duty (work_core `setElementVisibleToWork`). `E` opens the module list (locked /
  available / completed). A module started here keeps the player where they stand (the same spot in
  the session's dimension) and brings them back to the live dimension at the end.
- **First duty:** the first time a player goes on duty, a card offers SCOPE (`TRAINING.OFFER`, Start / Later). Started
  from the offer, the player is put into the room (`TRAINING.START`) and back to the duty marker at
  the end. The answer sets `atc.training.offered`; `TRAINING.DEBUG = true` offers it every time.
- **Completion:** account data `atc.training.<module> = true` (v_mysql). Completing a module is not
  required for anything; the menu shows it and offers "Again".
- **Stop:** the "Quit training" link on the card (click twice) or `/atctraining stop`. Dying,
  quitting or an error also ends it, without completion.
- **Start conditions:** logged in, alive, on duty (marker), the right of the module, not logged in to
  a live ATC position.
- v_accounts saves the original position (`save.position`), so a disconnect never saves the training
  one. Nothing is paid and no XP is given.

## The real flow, flagged as training

- map_int_sacontrol copies the room into the session's dimension (`createDimensionCopy`).
- avi_core makes a tutorial copy of the console marker of the module's position (the San Fierro
  consoles for ADC / APC, the ACC console for ACC), visible only to the player. It opens the tutorial
  login of avi_controller.
- avi_controller runs a tutorial login on the position: the live position stays free, the scope
  gets only the player's training aircraft, only the own position counts as open; no pay, no XP,
  separation losses are not charged; the logout receipt goes to the module.
- avi_traffic flies the training aircraft in a world of their own. Every other position is closed,
  so outside the trainee's sector the pilots fly on their own (the APC departure taxies and takes off
  alone; the ACC arrival flies its STAR in the closed TMA).
- **Fast forward:** sub-steps marked `fast` (the player only watches) let the aircraft fly
  `TRAINING.FAST_SCALE` times faster, while none of the player's own aircraft asks for something.

## Steps

Every module: `console` (log in at the console marker; a logout before `alerts` comes back here and
the aircraft start again) → its own steps → `alerts` (or the module's `logoutStep`; Logout = the
receipt) → `done` (Finish).

- **SCOPE:** console, tour (the scope rects of avi_controller `getScopeLayout`), menu (`dep` at a stand:
  its label, open its menu, what is in it), logout (`logoutStep`), done.
- **ADC:** console, label (the departure; its menu lists the ground flow), delivery, ground, air,
  arrival, alerts, done.
- **APC:** console, airspace (the TMA, runways, fixes), departure (`dep`), arrival (`arr`, kind `tma_arr` with the pilots' STAR),
  vectors (`vec`, kind `tma_arr` without STAR, another entry fix), alerts, done. Each traffic step ends
  once that aircraft left the TMA after it was the trainee's.
- **ACC:** console, airspace (the CTA and its sectors), overflight (`ovf`), conflict (`cfa` + `cfb`, avi_traffic
  `spawnTutorialConflict`: two overflights head-on on one leg at the same level, 3500 m each side of its middle),
  inbound (`inb`), alerts, done. The conflict step ends when the pair passed each other.

The sub-steps fall through when the aircraft already left the sector (a slow trainee is not stuck).
A training aircraft removed before the trainee had it comes again (`lost` in server/modules.lua).

## Files

| file | |
|---|---|
| `config.lua` | modules (code, right, position), marker, start point, callsigns, keys, debug flag |
| `server/session.lua` | sessions, the marker and the module list, aircraft roles, steps, offer, command |
| `server/modules.lua` | the modules: steps, roles, enter hooks, server checks, lost aircraft |
| `client/card.lua` | the DX card, the highlight and the cursor (scope blocked area) |
| `client/core.lua` | sub-step machinery, helpers for the modules, offer and module list cards |
| `client/scope.lua`, `adc.lua`, `apc.lua`, `acc.lua` | sub-steps of each module |
| `client/marker.lua` | the marker label and the `E` key |
| `DESIGN.md` | the plan (Hungarian) |

Texts: v_locals `work_atc.trn.*` (en + hu), written by `[aviation]/tools/loc_training.py` (it also
removes the old `work_atc.tut.*` keys).

## Hooks it uses in other resources

- **avi_core:** `hasATCRight`, `createTutorialMarker(player, dimension, position)`, `destroyTutorialMarker`.
- **avi_controller:** `useTutorialConsole` (called by the tutorial marker), `endATCTutorial`,
  `getPlayerATCPosition`, `getATCPayRules`, the events `onATCTutorialLogin`, `onATCTutorialLogout`
  and `onATCTutorialCommand`. Client `getScopeLayout`, `setScopeBlockedRect`, `focusScope`.
- **avi_traffic:** `spawnTutorialFlight` (kinds dep / arr / tma_arr / inbound / overflight),
  `spawnTutorialConflict`, `getTutorialSnapshot`, `setTutorialSquawk`, `removeTutorialFlight(s)`,
  `setTutorialTimeScale`; avi_controller calls `setTutorialController` at the tutorial login / logout.
- **avi_airports:** `getActiveRunways`.
- **map_int_sacontrol:** `createDimensionCopy(dimension)`, `destroyDimensionCopy(dimension)`.
- **work_core:** `isPlayerOnDuty`, `setElementVisibleToWork`. **v_mysql:** account data.
