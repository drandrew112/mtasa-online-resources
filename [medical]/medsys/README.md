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
server/rhythm.lua      heart rhythm (ECG), rhythm changes during CPR, monitor / defibrillator
server/treatment.lua   examination sessions, procedures (minigames, medication), locks, panel updates
server/transport.lua   "Transport": hearse for a dead body, ambulance for a stable patient
server/exports.lua     public API
server/interaction.lua "Examine patient" entry in the ui_interactobject world menu
client/panel.lua       DX examination panel
client/ecg.lua         ECG / pleth signal of the monitor (ring buffers) + the beat beep
client/lifepak.lua     "Lifepak 15" monitor / defibrillator window left of the panel
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
    rhythm        = "SINUS",              -- MEDIC_RHYTHMS key, rhythmTick = since when
    ecgRate       = 0,                    -- electrical rate of a pulseless VT / PEA
    vtTick        = nil,                  -- lasting VT with pulse since
    monitor       = nil,                  -- { energy, sync, chargeTick, analyzeTick, advice, message, shocks }
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
  to ~15%, then the pressure falls), medicines and `hypertension`. The pressure / pulse targets
  wander randomly by up to `BP_JITTER` (4 mmHg) / `HR_JITTER` (2 BPM), so the values never sit still;
  the diastolic follows the systolic.
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

**Heart rhythm** (`server/rhythm.lua`, `MEDIC_RHYTHMS`): SINUS, SINUS_BRADY (< 60), SINUS_TACHY
(> 100), VT_WITH_PULSE, VF, PULSELESS_VT, PEA, ASYSTOLE. Only VF and pulseless VT are shockable.

- With a pulse the rhythm is named from the rate; at `VT_HEART_RATE` (170) and above it is VT with
  pulse. A *lasting* VT with pulse (after a ROSC with `ROSC_VT_CHANCE`, an unsynchronised shock,
  or `setMedicalState(el, "rhythm", "VT_WITH_PULSE")`) holds the pulse at `VT_RATE`, drops the
  pressure by `VT_SYSTOLIC_DROP` and turns pulseless after `VT_DEGRADE_TIME` (120 s) unless a
  shock converts it.
- An arrest starts with a rhythm picked by its cause (`MEDIC_ARREST_RHYTHMS`): hypoxia /
  blood loss → PEA or asystole, the 200+ pulse → VF / pVT, a forced arrest (consciousness
  `clinical_death`, heartRate 0) → **asystole**, unless a pulseless rhythm is given with
  `setMedicalState(el, "rhythm", ...)` (e.g. med_scenemanager). A patient in arrest only takes a
  pulseless rhythm: a rhythm with a pulse is turned into asystole.
- Untreated it worsens: pVT → VF after 60 s, VF → asystole after 240 s, PEA → asystole after
  180 s. CPR pauses this.
- **CPR**: once the compressions ran `CPR_CHANGE_MIN` (10 s) **and the accuracy so far passes**
  (`exports.mg_cpr:getCPRGameProgress`), the rhythm can change at any moment (on average every
  `CPR_CHANGE_TIME` s). The change stops the CPR minigame (`stopCPRGame(medic, "interrupted")`)
  and the panel reopens with the news. Possible changes: the pulse returns (ROSC chance: accuracy,
  +IV, +airway, +adrenaline; ×`CPR_SHOCKABLE_ROSC` in VF / pVT; 0 when too much blood is lost),
  PEA / asystole → VF (`CPR_TO_SHOCKABLE`), PEA ↔ asystole, VF ↔ pVT. A ROSC is not always a
  sinus rhythm (VT with pulse).
- **Shock** (monitor window): in VF / pVT it works with `SHOCK_SUCCESS`; a working shock gives a pulse with `SHOCK_ROSC` (+ the same bonuses), otherwise PEA or
  asystole follows, so CPR goes on. A failed one leaves VF (pVT may turn VF). PEA / asystole: no
  effect. VT with pulse: SYNC cardioversion converts it with `CARDIOVERSION_SYNC`, an
  unsynchronised shock with `CARDIOVERSION_UNSYNC` (or causes VF with `SHOCK_PULSE_VF`). A shock
  on a sinus rhythm (normal / brady / tachy) **always** stops the heart (VF), synced or not; an
  awake patient gets `SHOCK_PAIN`. The shock stops a CPR
  running on the patient ("Stand clear").

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

Picking it opens the panel. It shows consciousness, the heart rate (palpated pulse), bleeding,
skin (instead of a blood volume number), IV / airway status, pain, the injury list and the
clinical death countdown. **Blood pressure, SpO2 and the ECG need the monitor**: the panel has
only the heart rate and the bleeding / skin tiles, SpO2 and NIBP are on the Lifepak screen. Until
the monitor is attached the ECG area of the heart rate tile is the *Attach monitor /
defibrillator* button (the only place to attach it, it has no button in the rows). With the monitor the ECG
runs with the rhythm name under it (most players cannot read an ECG), the monitor beeps
(`sounds/ecg_beep.wav`) on every QRS complex while the panel is open, and the **Lifepak 15**
window appears left of the panel. Close the panel with **X** or **Backspace**. It also closes
when you walk away (`PANEL_RANGE`).

The Lifepak window: HR (the counted QRS rate; `---` in VF, PEA and asystole: a PEA has broad low
waves without an R wave, no pulse and no beep), SpO2 and NIBP (`---` without a pulse), the ECG with the rhythm name, the pleth wave, the clock, the selected energy and
a status line. Buttons:

| button | what it does |
|---|---|
| ENERGY SELECT ▼▲ | inactive (greyed out): the energy is fixed at `DEFIB_ENERGY` (200 J) |
| CHARGE | charges in `DEFIB_CHARGE_TIME` (4.73 s = the length of `defib_charge.wav`, the charge bar follows it); an undelivered charge is dumped after `DEFIB_DISARM_TIME` (60 s) |
| SHOCK | flashes when charged; delivers the shock (see Heart rhythm), everyone at the panel sees the result |
| ANALYZE | AED mode, unresponsive patient only: `DEFIB_ANALYZE_TIME` (4 s), then SHOCK ADVISED (and it charges on its own) or NO SHOCK ADVISED |
| SYNC | synchronised shock (cardioversion of VT with pulse) |
| SOUND | ECG beep + alarm on / off for this patient (LED = on). Stored on the patient's monitor: a new patient starts with it on. The defibrillator sounds always play |

Screen rows: status bar (shocks, clock, SYNC, energy), message line (analysis / charge bar /
advice), HR + ECG + rhythm name (the tallest row), then SpO2 + pleth and NIBP at the bottom
(systolic, the diastolic under it, the mean pressure in brackets beside it).

Sounds (only for the medics at the panel): `ecg_beep.wav` on every QRS, `defib_charge.wav` while
charging, `defib_charge_complate.wav` + the `defib_ready_loop.wav` loop while charged,
`lifepak_alarm_loop.wav` while the rhythm is VF / pulseless VT / PEA / VT with pulse (not in asystole).

The monitor state is per patient (every medic at the panel sees the same device), the server
runs it (`medic:defib` requests).

The buttons are grouped into rows by `MEDIC_ACTION_GROUPS` (config): **AB** (Airway, Breathing:
Intubate, O2 mask), **C** (Circulation: Bandage, Splint, CPR, IV access, Medication), **D** (Disability:
Neuro exam, Glucometer) and Transport. A dead body only gets the Transport row (`MEDIC_DEAD_ACTION_GROUPS`). Active medicines
are listed one per line (two columns) with their remaining time.

| button | minigame | available when | success |
|---|---|---|---|
| Bandage | mg_arrows | an untreated wound / burn, or bleeding | treats the worst injury: bleeding stops (critical → mild), burn dressed |
| Splint | mg_splinting | an untreated fracture | the limb is realigned and the splint secured: fracture splinted |
| CPR | mg_cpr | clinical death | +45 s on the death timer; after 10 s of good compressions the rhythm can change (pulse back, or another arrest rhythm), which stops the minigame early. A round that ends without a change: "continue CPR" / "shockable rhythm - shock" |
| IV access | mg_intravenous | no IV yet | IV fluids run (rate scales with the quality). Difficulty rises with shock |
| Intubate | mg_airway | no tube, and RSI (also in clinical death): Ketamine working + Rocuronium working (after its 15 s onset) | airway secured, suffocation treated, O2 mask off. The patient is pre-oxygenated to 95%, then the SpO2 falls during the attempt |
| O2 mask / Remove O2 | – (3 s, `OXYGEN_TIME`) | no tube | toggles the oxygen mask: the SpO2 targets of the airway problems / shock +10, 100% otherwise, 2× faster recovery. A critical airway problem still needs the tube |
| Medication | – (3 s, `DRUG_TIME`) | always opens; IV medicines need IV access, oral ones (`route = "oral"`, e.g. Captopril) do not | opens the medicine grid (name, group, "oral" mark; IV ones are greyed out without IV access, the hovered one is described under it); the picked one is given after 3 s |
| Neuro exam | – (4 s, `NEURO_TIME`) | once per patient | its findings stay under the injuries (updated live): responsiveness (AVPU), pupils, FAST (face, arm, speech) and the clues of the hidden conditions (needle marks, alcohol smell, bitten tongue, acetone breath...) |
| Glucometer | – (client device) | living patient | holds out the meter right of the panel. MEASURE pricks the finger: the reading comes after `GLUCOMETER_TIME` (5 s), in mg/dL and mmol/L (`LO` < 20, `HI` > 600). Not continuous: measure again to see a change. The meter remembers the last reading of every patient (MEM) |
| Attach monitor / defibrillator (heart rate tile) | – (4 s, `MONITOR_TIME`) | once per patient | ECG electrodes + pads: BP / SpO2 / ECG visible, Lifepak window, defibrillation |
| Transport | – | ped only: a living patient with consciousness **Stable** or intubated (with a pulse), with a systolic pressure between `TRANSPORT_MIN_SYSTOLIC` and `TRANSPORT_MAX_SYSTOLIC` (90-180), or a dead body (then it is the only button, "Request transport") | after `TRANSPORT_DELAY` (30 s) an ambulance (alive) / hearse (dead) arrives at a free spot next to the patient, loads it (5 s), the ped is removed and the vehicle drives off |

Medicines (`MEDIC_DRUGS` in `shared/config.lua`):

| medicine | for | effect |
|---|---|---|
| Ketamine (Calypsol) | RSI step 1 (induction) | 10 min: unconscious, no pain, systolic +15, pulse +8 |
| Rocuronium bromide (Esmeron) | RSI step 2 (muscle relaxant) | 40 min: after 15 s (`PARALYSIS_ONSET`) the patient cannot move (unconscious) or breathe: SpO2 −0.25%/s until intubated (half with the O2 mask). An **awake** patient (no Ketamine) panics: pulse +50, systolic +35, until it passes out or gets Ketamine |
| Fentanyl | pain of an awake patient | 30 min: pain −70%, systolic −10 |
| Adrenalin (Tonogen) | heart stimulant / cardiac arrest | 5 min: pulse +30, systolic +30, +15% ROSC chance for CPR (does not add up). Several doses can push the pulse to the arrest limit |
| Captopril (Tensiomin) | high blood pressure | oral (no IV needed). Target systolic −40 mmHg for 10 min. It also lowers a normal / low pressure: in shock it can drop it to the arrest limit |
| Nitroglycerin spray | pulmonary oedema, high BP | oral. Systolic −30 for 10 min, treats pulmonary oedema |
| Glucose 40% | low blood glucose | IV. +100 mg/dL at once; the glucose drifts back to the patient's resting value: measure again |
| Oral glucose gel | low glucose, awake patient | oral, only stable / confused (it must swallow). +40 mg/dL |
| Insulin (Actrapid) | very high glucose (ketoacidosis) | IV. −0.35 mg/dL/s for 15 min: on a normal glucose it causes hypoglycaemia |
| Naloxone (Narcan) | opioid overdose | nasal. Treats the opioid overdose (breathing, consciousness, pupils back) |
| Salbutamol (Ventolin) | asthma, COPD | inhaled. Treats the wheezing (the SpO2 targets rise), pulse +12 |
| Midazolam (Dormicum) | stimulant intoxication | IV. Pulse −15, systolic −15, treats the stimulant intoxication |

### Medical conditions, glucose, breathing

Conditions are `MEDIC_INJURIES` entries with extra fields (see the config comment), applied with
`applyInjury` like any injury. **Hidden** ones (stroke, opioid / sedative / stimulant overdose,
alcohol, postictal, asthma, COPD, pulmonary oedema) are not listed on the panel: they show only
through the consciousness, the breathing, the skin and the neuro exam. `head_injury` is visible
and, like the stroke, has no prehospital treatment (*Needs hospital*). A condition can lower the
SpO2, shift the pressure / pulse, force a consciousness, change the breathing; a medicine in its
`treatDrugs` treats it. `postictal` wears off by itself; an untreated **stroke** gets one severity
worse every `STROKE_PROGRESS_TIME` (480 s), `STROKE_BAD_BP_FACTOR` times faster with a systolic
outside 130-220 (do not over-lower the pressure, Captopril only for a really high one).

**Confused** is a consciousness level between Stable and Dazed (`MEDIC_CONSCIOUSNESS_RANK`).

Blood glucose (`state.glucose`, mg/dL) drifts to its resting value (`setMedicalState "glucose"`
sets both, `"glucoseNow"` only the current one). Low (< 70): sweating, faster pulse, confused
< 58, dazed < 45, unconscious < 30, cardiac arrest after `HYPO_ARREST_TIME` below 20. High: fluid
loss above 300 (dehydration), Kussmaul breathing and acetone breath above 350, confused ≥ 420,
dazed ≥ 550, unconscious ≥ 700. An IV line slowly lowers a glucose above 180.

The **Breathing** line of the bleeding tile (`MEDIC_BREATHING`): normal, rapid, wheezing,
laboured, crackles, deep and rapid (Kussmaul), silent chest, slow, snoring, gasping, not breathing,
ventilated. It is broadcast as `medic.breath` element data; medsys_effects plays the struggling for
air animation on dyspnoeic peds.

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
--   ivAccess, intubated, oxygenMask, sedated, paralyzed, drugs = { { id, name, timeLeft } }, clinicalDeath, deathTimeLeft, dead, isPatient,
--   rhythm, rhythmLabel, ecgRate (ECG complexes / min), monitor = nil | { energy, sync, shocks, chargeLeft, charged,
--   analyzeLeft, advice, adviceAge, message, messageAge } }

exports.medical_system:setMedicalState(element, key, value) -- true / false
--   heartRate     0 = cardiac arrest, > 0 during clinical death = return of circulation
--   systolic, diastolic, spo2, bloodVolume, pain (0-100, fades)
--   hypertension  mmHg added to the target systolic pressure until set back to 0 (lasting high BP)
--   restingSystolic, restingDiastolic, restingHeartRate
--                 lasting values: the target is shifted so the patient settles at (and holds) this
--                 value with its current injuries / pain / medicines; set systolic first
--   restingSpo2   lasting SpO2 cap (chronic hypoxia), the oxygen mask lifts it, intubation removes it
--   bleeding      0 stops every bleeding, 1-3 adds a bleeding that is not tied to an injury
--   ivAccess, intubated, oxygenMask, monitor   booleans (monitor = the monitor / defibrillator is attached)
--   rhythm        MEDIC_RHYTHMS key: a pulseless one (VF, PULSELESS_VT, PEA, ASYSTOLE) = cardiac arrest in it,
--                 VT_WITH_PULSE = lasting VT (only a shock ends it), SINUS / SINUS_BRADY / SINUS_TACHY
--                 revive and move the resting pulse into the range when it is outside
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
| fracture | – / – / mild (open) | high pain | Splint |
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
addEventHandler("onMedicalDefibrillation", root, function(medic, joules, rhythmBefore, rhythmAfter) end) -- source = patient
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
from height, house fire, drowning, overdose, cardiac arrest (random rhythm), VF arrest, asystole,
VT with pulse, minor burn, hypertensive crisis, dead body. Each admin can have at
most `MAX_PEDS` test peds (the oldest is removed), and they are removed when the admin quits.

## Config

Everything is in `shared/config.lua` → `MEDIC` (tick, bleed rates, thresholds, death time, ROSC
chances, key, ranges, role requirement), `MEDIC_INJURIES` (injury effects). The minigame
resources are `<include>`d. Turn off their `TEST_COMMAND`s in production.

## Tutorial support

- Server: `setTutorialPatient(element, enabled)` / `isTutorialPatient(element)`: no transport can be
  requested for this patient.
- Client: `isExaminationOpen()` and `getExaminationPanelLayout()`. The layout gives the screen
  rectangles of the panel sections: panel, consciousness, vitals, status, injuries, buttons,
  buttonList, monitorButton (until the monitor is attached) and lifepak / lifepakScreen /
  lifepakKeypad (while it is attached). The event `onClientMedicPanel(open, target)` fires with source = localPlayer.
