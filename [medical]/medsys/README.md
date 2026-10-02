# medical_system

Realistic medical state for **players and peds**: blood loss, shock, oxygenation, consciousness,
clinical death and biological death, plus a DX **patient examination panel** whose buttons start
the treatment minigames. This resource does not create patients and has no EMS job logic. Other
scripts hurt people through the exports, and the future EMS job script builds on top of it.

## Architecture

```
shared/config.lua      MEDIC tunables, injury definitions, labels
server/state.lua       patient registry + data structure, snapshots, state transitions
server/simulation.lua  one global timer, physiology step for every patient
server/treatment.lua   examination sessions, procedures (minigames, medication), locks, panel updates
server/transport.lua   "Transport": hearse for a dead body, ambulance for a stable patient
server/exports.lua     public API
server/interaction.lua "Examine patient" entry in the ui_interactobject world menu
client/panel.lua       DX examination panel
client/interaction.lua turns the world menus off during procedures / while the player is down
client/progress.lua    progress bar of a timed procedure (medication)
```

**Where the data lives**

| data | where | synced to |
|---|---|---|
| full medical state | server table `Patients[element]` | nobody (the server owns it) |
| `medic.status` (consciousness) | element data, broadcast | everyone, but only written on state changes |
| `spo2`, `heartRate` | element data, **subscribe** mode | only the medics examining / treating the patient (mg_airway reads them) |
| panel snapshot | `medic:panelUpdate` event | only the medics with the panel open, once per tick |

Only elements that are not perfectly healthy are in the registry. The simulation timer runs only
while there is at least one patient. A patient with nothing left to simulate (no injuries, full
vitals, nobody examining it) is dropped automatically. Persistent elements
(`setPatientPersistent`, medsys_events makes every player persistent) are never dropped: they
always carry the status data (so they can always be examined) and get a fresh state after a reset
or a respawn. `isPatient` in the snapshot is false for a healthy persistent element (= needs care).

The down / get-up animations of the patients and everything a player patient experiences
(blackout, control lock, pain / bleeding screen effects) are in **medsys_effects**, which follows
the `medic.status` element data and the medsys events.

## Data structure (server)

```lua
Patients[element] = {
    element       = element,
    bloodVolume   = 5000,                 -- ml
    heartRate     = 72,                   -- BPM, 0 in clinical death
    systolic      = 120, diastolic = 80,  -- mmHg
    spo2          = 98,                   -- %
    baseBleeding  = 0,                    -- 0-3, bleeding not tied to an injury
    extraPain     = 0,                    -- pain set from outside, fades
    injuries      = { { id, type, severity, bleeding, treated, tick }, ... },
    ivAccess      = false, ivQuality = 0,
    intubated     = false,
    oxygenMask    = false,
    hypertension  = 0,                    -- mmHg on the target systolic pressure
    drugs         = { { id, tick, untilTick }, ... }, -- active medicine doses
    aware, panic  = true, false,          -- awake apart from the medicines / awake under the muscle relaxant
    consciousness = "stable",             -- stable | dazed | unconscious | clinical_death | dead
    arrestTick    = nil, deathTick = nil, -- clinical death start / biological death time
    knockoutState = nil, knockoutUntil = nil,
    apneaRate     = nil,                  -- SpO2 fall during an intubation attempt
    dead          = false,
}
```

## Physiology (every `MEDIC.TICK` ms)

- **Blood**: every wound bleeds at `BLEED_RATE[level]` ml/s (mild 1.5 / severe 5 / critical 12),
  and burns lose plasma. IV access restores fluids up to 90%, and the body slowly compensates
  while nothing bleeds. Without circulation, bleeding drops to 20%.
- **Blood pressure** moves towards a target based on the blood loss (shock classes: compensated
  to ~15%, then the pressure falls), medicines and `hypertension`.
- **Heart rate** always rises as the actual systolic pressure falls below 120 (`BARO_REFLEX`
  BPM / mmHg, whatever lowered it), plus early blood-loss compensation, pain and hypoxia.
  Below 50% SpO2 the heart fails (bradycardia) before the arrest.
- **SpO2** drifts to the lowest target of the airway causes (suffocation, inhalation burn) or of
  shock, and recovers otherwise. A secured airway removes the airway causes, the O2 mask lifts
  the targets by 10. Under Rocuronium without a tube there is no breathing: the SpO2 only falls.
- **Consciousness**: `unconscious` below 70% SpO2 or 65 mmHg systolic, and `dazed` below 88% /
  90 mmHg or at pain 70+.
- **Medicines** shift the target pressure / pulse, take away pain, sedate or paralyse while they
  work (`MEDIC_DRUGS`, doses add up). Sedation / paralysis force `unconscious`.
  `hypertension` and the `resting*` keys (setMedicalState) are lasting offsets on the same targets
  (a patient with one of them is never discharged as healthy).
- **Cardiac arrest** when the SpO2 reaches `ARREST_SPO2` (0), the blood volume falls to 50% or the
  systolic pressure falls to `ARREST_SYSTOLIC` (30, e.g. Captopril given in shock), or the pulse
  stays at `ARREST_HEART_RATE` (200) or above for `ARREST_TACHY_TIME` (5 s). The
  pulse and blood pressure go to 0, and a `DEATH_TIME` (300 s) countdown starts. When it runs
  out: biological death (`killPed`).

Unconscious / arrested patients play `PED/KO_shot_front`, and they get up (`getup_front`) when
they wake. Player patients get their controls locked and see a dazed vignette, or a blackout
with the resuscitation countdown.

## Examination panel

Every patient (any ped/player with `medic.status`) gets a **Patient → Examine patient** entry
in the `ui_interactobject` world menu (`X` opens it, `1` picks it, within `MEDIC.INTERACT_RANGE`).
The menu is registered for the `ped` and `player` types with `dataKey = "medic.status"`, so it
appears and disappears with the patient status on its own. With `REQUIRE_MEDIC_ROLE` only the
players flagged by `setPlayerMedic` see it. Other resources (e.g. a stretcher) can add their own
menu to the same patient; `ui_interactobject` merges them into one panel. While a procedure runs,
or while the player is down, the world menus are switched off for that player.

Picking it opens the panel. It shows consciousness, heart rate with an ECG trace, blood pressure, SpO2,
bleeding, skin (instead of a blood volume number), IV / airway status, pain, the injury list and
the clinical death countdown. Close it with **X** or **Backspace**. It also closes when you walk
away (`PANEL_RANGE`).

The buttons are grouped into rows by `MEDIC_ACTION_GROUPS` (config): **AB** (Airway, Breathing:
Intubate, O2 mask), **CD** (Circulation, Disability: Bandage, CPR, IV access, Medication) and
Transport. A dead body only gets the Transport row (`MEDIC_DEAD_ACTION_GROUPS`). Active medicines
are listed one per line (two columns) with their remaining time.

| button | minigame | available when | success |
|---|---|---|---|
| Bandage | mg_arrows | an untreated wound / fracture / burn, or bleeding | treats the worst injury: bleeding stops (critical → mild), fracture splinted, burn dressed |
| CPR | mg_cpr | clinical death | ROSC chance (accuracy, +IV, +airway, 0 when the blood loss is too high), otherwise +45 s on the death timer |
| IV access | mg_intravenous | no IV yet | IV fluids run (rate scales with the quality). Difficulty rises with shock |
| Intubate | mg_airway | no tube, and RSI (also in clinical death): Ketamine working + Rocuronium working (after its 15 s onset) | airway secured, suffocation treated, O2 mask off. The patient is pre-oxygenated to 95%, then the SpO2 falls during the attempt |
| O2 mask / Remove O2 | – (3 s, `OXYGEN_TIME`) | no tube | toggles the oxygen mask: the SpO2 targets of the airway problems / shock +10, 100% otherwise, 2× faster recovery. A critical airway problem still needs the tube |
| Medication | – (3 s, `DRUG_TIME`) | IV access in place | opens the medicine grid (name, group; the hovered one is described under it); the picked one is given after 3 s |
| Transport | – | ped only: a living patient with consciousness **Stable** or intubated (with a pulse), or a dead body (then it is the only button, "Request transport") | after `TRANSPORT_DELAY` (30 s) an ambulance (alive) / hearse (dead) arrives at a free spot next to the patient, loads it (5 s), the ped is removed and the vehicle drives off |

Medicines (`MEDIC_DRUGS` in `shared/config.lua`):

| medicine | for | effect |
|---|---|---|
| Ketamine (Calypsol) | RSI step 1 (induction) | 10 min: unconscious, no pain, systolic +15, pulse +8 |
| Rocuronium bromide (Esmeron) | RSI step 2 (muscle relaxant) | 40 min: after 15 s (`PARALYSIS_ONSET`) the patient cannot move (unconscious) or breathe: SpO2 −0.25%/s until intubated (half with the O2 mask). An **awake** patient (no Ketamine) panics: pulse +50, systolic +35, until it passes out or gets Ketamine |
| Fentanyl | pain of an awake patient | 30 min: pain −70%, systolic −10 |
| Adrenalin (Tonogen) | heart stimulant / cardiac arrest | 5 min: pulse +30, systolic +30, +15% ROSC chance for CPR (does not add up). Several doses can push the pulse to the arrest limit |
| Captopril (Tensiomin) | high blood pressure | target systolic −40 mmHg for 10 min. It also lowers a normal / low pressure: in shock it can drop it to the arrest limit |

RSI order: Ketamine first, then Rocuronium, wait for the onset, intubate. The wrong order is
punished by the medicines themselves (panic, then the breathing stops in an awake patient).
An intubated patient never wakes up with the tube in: it stays unconscious until it is fully
stable and no medicine keeps it asleep, then the tube comes out.

The transport spot is picked by the requesting medic's client (ground check + line of sight, boot
towards the body); the server only accepts it within `TRANSPORT_SPOT_RANGE`. Without a free spot
the patient is simply taken away when the time is up. Players cannot be transported.

The server checks every request (distance, role, patient state, one medic per procedure per
patient). When the minigame ends, the panel reopens with the result.

## Server exports

```lua
local data = exports.medical_system:getMedicalState(element)
-- { consciousness, consciousnessLabel, heartRate, systolic, diastolic, bloodPressure = "120/80",
--   spo2, bleeding (0-3), bleedingLabel, bloodVolume, bloodPercent, pain,
--   injuries = { { id, type, label, severity, severityLabel, bleeding, treated, treatedLabel } },
--   ivAccess, intubated, oxygenMask, sedated, paralyzed, drugs = { { id, name, timeLeft } }, clinicalDeath, deathTimeLeft, dead, isPatient }

exports.medical_system:setMedicalState(element, key, value) -- true / false
--   heartRate     0 = cardiac arrest, > 0 during clinical death = return of circulation
--   systolic, diastolic, spo2, bloodVolume, pain (0-100, fades)
--   hypertension  mmHg added to the target systolic pressure until set back to 0 (lasting high BP)
--   restingSystolic, restingDiastolic, restingHeartRate
--                 lasting values: the target is shifted so the patient settles at (and holds) this
--                 value with its current injuries / pain / medicines; set systolic first
--   restingSpo2   lasting SpO2 cap (chronic hypoxia), the oxygen mask lifts it, intubation removes it
--   bleeding      0 stops every bleeding, 1-3 adds a bleeding that is not tied to an injury
--   ivAccess, intubated, oxygenMask   booleans
--   consciousness "stable" (wakes / revives), "dazed" / "unconscious" (forced for KNOCKOUT_TIME),
--                 "clinical_death", "dead"
-- The simulation continues from the new value (e.g. a heart rate drifts back to its target).

local injuryId = exports.medical_system:applyInjury(element, injuryType, severity)
--   injuryType: "gunshot" | "fracture" | "burn" | "suffocation"
--   severity:   1-3 or "minor" | "serious" | "critical"

exports.medical_system:healCompletely(element) -- everything back to baseline, health 100

exports.medsys:setPatientPersistent(element, true) -- stays registered while healthy; false: normal again
exports.medsys:isPatientPersistent(element)

-- medic role (work_ems gives / takes it; only enforced when MEDIC.REQUIRE_MEDIC_ROLE = true)
exports.medsys:setPlayerMedic(player, true)   -- give; false takes it away
exports.medsys:isPlayerMedic(player)          -- the bare flag
exports.medsys:hasMedicAccess(player)         -- not required, or has the role
exports.medsys:isMedicRoleRequired()          -- the config value; ask it once, it does not change at runtime
exports.medsys:getMedicPlayers()              -- every player with the role

-- for the EMS job script
exports.medical_system:openExamination(medic, target) -- open the panel from your own interaction
exports.medical_system:closeExamination(medic)
```

| injury | bleeding (minor/serious/critical) | other effects | treated by |
|---|---|---|---|
| gunshot | mild / severe / critical | pain | Bandage |
| fracture | – / – / mild (open) | high pain | Bandage (splint) |
| burn | – | plasma loss, pain, critical = inhalation injury (SpO2 → 80%) | Bandage (dressing), Intubate for the airway |
| suffocation | – | SpO2 → 88% / 65% / 0% | Intubate |

## Medic role

With `MEDIC.REQUIRE_MEDIC_ROLE = true` only players given the role by `setPlayerMedic` can examine or
treat, see the "Examine patient" world menu, handle the stretcher (`med_stretcher`) and get the
"ambulance only" hint of the EMS tablet (`med_erm`). The role lives in a server table; the server
copies it to the `medic.role` element data so clients can read it, and reverts client changes.
The role is not saved: it is gone after a reconnect or a medsys restart, work_ems has to give it again.
Client exports for UI decisions: `isPlayerMedic([player])`, `hasMedicAccess([player])`,
`isMedicRoleRequired()`. The `onPlayerMedicChange(enabled)` server event (source: player) fires on
every change.

## Events (server, for other scripts)

```lua
addEventHandler("onMedicalInjury", root, function(injuryType, severity, injuryId) end)      -- source = patient
addEventHandler("onMedicalStateChange", root, function(newState, oldState) end)            -- consciousness changed
addEventHandler("onMedicalCardiacArrest", root, function() end)                            -- clinical death started
addEventHandler("onMedicalRevived", root, function() end)                                  -- ROSC
addEventHandler("onMedicalDeath", root, function() end)                                    -- biological death
addEventHandler("onMedicalTreatment", root, function(medic, action, success, option) end)  -- source = patient, option = medicine id
addEventHandler("onMedicalTransportRequested", root, function(medic, kind) end)            -- source = ped, kind = "alive" | "dead"
addEventHandler("onMedicalPatientTransported", root, function(medic, kind) end)            -- source = ped, right before it is destroyed
```

## Lifecycle

- `onPlayerSpawn` resets the player's medical state (a new body). Respawning is not this
  resource's job.
- A ped or player that dies in any other way (`onPedWasted` / `onPlayerWasted`) is marked dead.
- Destroyed peds and quitting players leave the registry, and their panels and procedures are
  closed.

## Test module

`server/test.lua` + `client/test.lua`, switched on and off with `MEDIC_TEST.ENABLED` in
`shared/config.lua` (default `false`). When it is off, neither file registers anything. Only for
logged-in players with `admin_level >= MEDIC_TEST.MIN_ADMIN_LEVEL` (4, i.e. above 3). The level is
read from `v_mysql` account data, not from element data. The ped is placed
`SPAWN_DISTANCE` in front of the admin, facing them.

- `/medtest` opens a `ui_inac` menu with **Scenarios**, **Single injury** (type → severity) and
  **Remove my test peds**
- `/medtest <scenario>`, e.g. `/medtest drowning` (the ids are listed by `/medtest list`)
- `/medtest <gunshot|fracture|burn|suffocation> <1-3>`
- `/medtest clear` destroys your test peds

Scenarios (in `MEDIC_TEST.SCENARIOS`): torso / limb gunshot, hemorrhagic shock, car crash, fall
from height, house fire, drowning, overdose, cardiac arrest, minor burn. Each admin can have at
most `MAX_PEDS` test peds (the oldest is removed), and they are removed when the admin quits.

## Config

Everything is in `shared/config.lua` → `MEDIC` (tick, bleed rates, thresholds, death time, ROSC
chances, key, ranges, role requirement), `MEDIC_INJURIES` (injury effects). The minigame
resources are `<include>`d. Turn off their `TEST_COMMAND`s in production.

## Tutorial support

- Server: `setTutorialPatient(element, enabled)` / `isTutorialPatient(element)`: no transport can be
  requested for this patient.
- Client: `isExaminationOpen()` and `getExaminationPanelLayout()`. The layout gives the screen
  rectangles of the panel sections: panel, consciousness, vitals, status, injuries, buttons and
  buttonList. The event `onClientMedicPanel(open, target)` fires with source = localPlayer.
