# work_atc tutorial module

An optional walkthrough of the tower controller job, built like the work_ems and
work_bloodtransport tutorials. The player stands in the SA Control operations room (interior 3) in a
dimension of their own, starting at `TUTORIAL.DIMENSION_BASE`, and controls two tutorial aircraft on
`TUTORIAL.POSITION` (SASF_TWR). Approach and radar get their own modules later.

- **When:** the first time a player goes on duty as an air traffic controller, a card offers the
  tutorial (Start / Skip). With `TUTORIAL.DEBUG = true` it is offered on every duty start.
  `/tutorial_atc` starts it at any time (no duty or ATC right needed), and `/tutorial_atc skip` ends
  it. Completing or skipping it sets the account data `atc.tutorial = true` (v_mysql). Dying,
  quitting or an error does not set it.
- **Start conditions:** logged in, alive, not logged in to an ATC position.
- **During the tutorial:** v_accounts saves the original position (`save.position`), so a
  disconnect never saves the tutorial position. Nothing is paid and no XP is given.

## The real flow, flagged as tutorial

The tutorial does not fake anything: the console marker, the login window, the scope, the menu and
the simulation are the real ones.
- avi_core makes a **tutorial copy of the San Fierro console marker** in the session's dimension,
  visible only to the player. It opens the tutorial login of avi_controller.
- avi_controller runs a **tutorial login**: the player is logged in to SASF_TWR, but the live
  position stays free (another controller may staff it meanwhile). The scope gets only the player's
  own tutorial aircraft, and only the own position counts as open. No pay, no XP, separation losses
  are not charged; the logout receipt goes to the tutorial.
- avi_traffic flies **two tutorial aircraft** (`TUT101` departure, `TUT202` arrival, type and route
  copied from a flight of the database) in a world of their own: they do not meet the live traffic
  (stands, taxi queues, runways, alerts), and the live exports (snapshot, monitors, web, traffic
  limits, workload keeper) leave them out. The tutorial tower also covers the closed approach (the
  SASF TMA) for them: the SASF CTR is only a strip along the runway, 2000 ft high, too small to
  practise levels, headings or an approach.

## Steps

1. **Console.** Walk into the console marker, `E`, Log in at SASF_TWR (tutorial).
2. **Scope.** The top bar (runways in use, wind), AT / FIXL / V- V+, zoom and pan, the lists, Hide
   and Logout.
3. **Labels and the menu.** The departure appears at a stand; the ground and airborne labels, the
   yellow request frame, the command menu.
4. **Delivery.** IFR clearance (SID, initial level), Pushback approved.
5. **Taxi.** Taxi to the runway in use, holding short, CROSS / BKTRK / T/O, take-off clearance.
6. **Take-off and climb.** Cleared altitude, the heading picker, Direct to / Transfer to; the step
   ends when the departure leaves the TMA (nobody controls it any more).
7. **Arrival.** The arrival appears in the TMA flying to the final fix of the runway in use (the
   farthest point of `TR.TUTORIAL_FINAL_DIST` x `TR.TUTORIAL_FINAL_ANGLES`): Cleared approach,
   Cleared to land (a go-around is explained when it happens), the landing, Taxi to stand, parked.
8. **Alerts and pay.** The arrival squawks 7700 (EMRG), the other alerts, the fines and the pay
   rules (from `getATCPayRules`), the ranks (APP / RADAR levels from `ATC.LEVELS`); Logout shows the
   receipt (not paid).
9. **Done.** The receipt and a summary; Finish takes the player back to where they started.

A logout before step 8 starts again from step 1 (new aircraft). A tutorial aircraft that disappears
(an admin removed it) comes again. The card is on the left; the scope ignores clicks on it
(`setScopeBlockedRect`). Its buttons work while the cursor is visible: the scope and the login
window show it themselves, a Next card without them shows it itself, and `F2` toggles it. Every card
has a "Skip tutorial" link (click twice).

## Files

| file | |
|---|---|
| `config.lua` | position, start point, the aircraft callsigns, keys named in the texts, debug flag |
| `server/session.lua` | sessions, the console marker, the aircraft, steps, command, duty start offer |
| `client/card.lua` | the DX card, the highlight and the cursor (copy of the bt card + the scope blocked area) |
| `client/steps.lua` | step texts, the client-driven sub-steps, scope layout highlights |
| `DESIGN.md` | the plan (Hungarian) |

Texts: v_locals `work_atc.tut.*` (en + hu), written by `[aviation]/tools/loc_tutorial.py`.

## Hooks it uses in other resources

- **avi_core:** `createTutorialMarker(player, dimension, position)`, `destroyTutorialMarker`.
- **avi_controller:** server `useTutorialConsole` (called by the tutorial marker), `endATCTutorial`,
  `getPlayerATCPosition`, `getATCPayRules`, the events `onATCTutorialLogin`, `onATCTutorialLogout`
  (player, position, total, receipt items) and `onATCTutorialCommand` (player, action, aircraft id,
  value). Client `getScopeLayout`, `setScopeBlockedRect`, `focusScope`.
- **avi_traffic:** `spawnTutorialFlight`, `getTutorialSnapshot`, `setTutorialSquawk`,
  `removeTutorialFlight(s)`; avi_controller calls `setTutorialController` at the tutorial
  login / logout.
- **avi_airports:** `getActiveRunways`.
- **v_accounts:** the server-only element data `save.position`.
