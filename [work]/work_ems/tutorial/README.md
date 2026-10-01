# work_ems tutorial module

An optional walkthrough of the EMS job in a private copy of the world. Each session gets its own
dimension, starting at `TUTORIAL.DIMENSION_BASE`.

- **When:** the first time a player goes on duty as EMS, a card offers the tutorial (Start / Skip).
  With `TUTORIAL.DEBUG = true` it is offered on every duty start. `/tutorial_ems` starts it at
  any time, and `/tutorial_ems skip` ends it. Completing or skipping it sets the account data
  `ems.tutorial = true` (v_mysql). Dying, quitting or an error does not set it.
- **During the tutorial:** the player keeps their medic role, or gets it for the tutorial only.
  They are taken out of their ERM unit. v_accounts saves their original position
  (`save.position`), so a disconnect never saves the tutorial position.

## Steps

1. **Tablet.** The player sits in a tutorial ambulance. The med_erm tablet runs in tutorial mode
   with demo data, and nothing reaches the server. The steps: open the tablet (J), sign in, the
   Home page, a demo case arrives, Active Case, Start Response, the automatic statuses, Messages,
   close the tablet.
2. **Examination.** A patient with a minor burn (medsys `setTutorialPatient`, no transport). The
   steps: open the panel (X, 1), the card highlights each panel section (consciousness, vitals,
   IV/airway/pain, injuries, buttons), then the player bandages the burn with mg_arrows. A failed
   bandage can be retried.
3. **Minigames.** A panel offers mg_arrows, mg_cpr, mg_intravenous and mg_airway with no patient.
   The player can play them any number of times. Continue needs `MIN_GAMES` successful runs.
4. **Stretcher.** A healthy person stands behind the ambulance. The player takes out the
   stretcher, places the person on it and loads it back into the ambulance.
5. **Transport and handover.** The camera fades and the ambulance is parked in the bay of
   `TUTORIAL.HOSPITAL`. med_hospitals `createTutorialHandover` has copied that hospital's markers
   into the tutorial dimension. The player takes the patient out and pushes the stretcher into the
   handover marker for 5 s.
6. **Done.** A summary card. Finish takes the player back to where they started.

The card is on the left. Its buttons work while the cursor is visible: the tablet and the panel
show it themselves, and `M` toggles it. Every card has a "Skip tutorial" link (click twice).

## Files

| file | |
|---|---|
| `config.lua` | positions (placeholders, fine-tune with `/workpos`), demo case, minigame list, debug flag |
| `server/session.lua` | sessions, world elements, steps, minigame practice, command, work_ems module hooks |
| `client/card.lua` | the DX card, the highlight and the cursor |
| `client/steps.lua` | step texts, the client-driven sub-steps, signals from med_erm / medsys |

## Hooks it uses in other resources

- **med_erm (client):** `startTabletTutorial`, `stopTabletTutorial`, `setTabletTutorialCase`,
  `setTabletTutorialUnit`, `addTabletTutorialMessage`, and the event `onClientErmTabletTutorial`.
  Server: `removePlayerFromUnit`.
- **medsys:** server `setTutorialPatient`. Client `isExaminationOpen`,
  `getExaminationPanelLayout`, and the event `onClientMedicPanel`.
- **med_hospitals:** `createTutorialHandover`, `destroyTutorialHandover`, and the event
  `onHospitalTutorialHandover`.
- **v_accounts:** the server-only element data `save.position`.
