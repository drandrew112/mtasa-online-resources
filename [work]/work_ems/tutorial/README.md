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

One patient goes through the whole tutorial (a minor burn and a fracture, `TUTORIAL.SCENE.injuries`):
examined and treated at the scene, loaded with the equipment riding on the stretcher, handed over at
the hospital. The patient is a medsys tutorial patient with `useEquipment`: no transport, but the
med_bag rules apply. The equipment steps (2 and 7) are left out while med_bag is not running.

1. **Tablet.** The player sits in a tutorial ambulance. The med_erm tablet runs in tutorial mode
   with demo data, and nothing reaches the server. The steps: open the tablet (J), sign in, the
   Home page, a demo case arrives, Active Case, Start Response, the automatic statuses, Messages,
   close the tablet.
2. **Equipment** (med_bag). At the side door: Check contents (the contents window: IV kits, oxygen,
   medicines, they run out, restock in a hospital bay), Take both, the carry HUD, the 4 m rule and
   the left-behind warning. The step ends when the player opens the panel at the patient.
3. **Examination.** Open the panel (X, 1). The card highlights each section: consciousness, the
   BAG / MONITOR / O2 chips (what is within 4 m; without equipment only examine, Neuro, CPR and
   transport), pulse / bleeding / skin, IV/airway/pain, injuries, the AB / CD / Transport rows. The
   player attaches the monitor; the card explains the Lifepak screen and the defibrillator keys
   (shock only VF / pulseless VT, the monitor disconnects beyond 6 m).
4. **Treatment.** Bandage the burn (mg_arrows), splint the fracture (mg_splinting), IV access
   (mg_intravenous, one IV kit per attempt), Medication -> Fentanyl (the doses left on the cards),
   O2 mask (the O2 chip drains; beyond 6 m or empty the mask comes off). `TUTORIAL.TREATMENTS` lists
   what must be done; a failed minigame can be retried, a treatment done earlier counts.
5. **Stretcher.** Take out the stretcher, place the patient on it, put the equipment (the
   treatments put it down next to the patient) on the stretcher with its menu. Load it. The step ends when the patient is in the
   ambulance AND the bag and the monitor are back in it (the card says what is still outside).
6. **Transport and handover.** The camera fades and the ambulance is parked in the bay of
   `TUTORIAL.HOSPITAL`. med_hospitals `createTutorialHandover` has copied that hospital's markers
   into the tutorial dimension. The patient comes out on the stretcher with the equipment; the
   player pushes it into the handover marker for 5 s.
7. **Restock.** Load the empty stretcher (the equipment goes back in), then Restock bag at the side
   door. The tutorial bay counts as a hospital bay (`getVehicleHospitalBay` knows the tutorial bays).
   The step ends when the bag is full again.
8. **Done.** A summary card. "Practice minigames" opens the optional practice list (all five
   minigames without a patient, any number of times, `TUTORIAL.GAMES`). Finish takes the player back
   to where they started.

The card is on the left. Its buttons work while the cursor is visible: the tablet and the panel
show it themselves, a Next card without them shows it itself, and `F2` toggles it. Every card has a "Skip tutorial" link (click twice).

## Files

| file | |
|---|---|
| `config.lua` | positions (placeholders, fine-tune with `/workpos`), injuries, demo case, required treatments, minigame list, debug flag |
| `server/session.lua` | sessions, world elements, steps, minigame practice, command, work_ems module hooks |
| `client/card.lua` | the DX card, the highlight and the cursor |
| `client/steps.lua` | step texts, the client-driven sub-steps, signals from med_erm / medsys |

## Hooks it uses in other resources

- **med_erm (client):** `startTabletTutorial`, `stopTabletTutorial`, `setTabletTutorialCase`,
  `setTabletTutorialUnit`, `addTabletTutorialMessage`, and the event `onClientErmTabletTutorial`.
  Server: `removePlayerFromUnit`.
- **medsys:** server `setTutorialPatient(ped, true, true)` (useEquipment), `applyInjury`, the event
  `onMedicalTreatment`. Client `isExaminationOpen`, `getExaminationPanelLayout` (incl. `equipment`,
  `drugCards`, `monitorButton`, `lifepakScreen`, `lifepakKeypad`), and the event `onClientMedicPanel`.
- **med_bag (optional):** server `getVehicleKit`, `getItemInfo`, `getItemStock`; client the element
  data `medbag.hands` and the event `bag:contents`.
- **med_hospitals:** `createTutorialHandover`, `destroyTutorialHandover`, the event
  `onHospitalTutorialHandover`; `getVehicleHospitalBay` also returns the tutorial bays.
- **v_accounts:** the server-only element data `save.position`.
