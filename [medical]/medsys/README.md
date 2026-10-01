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
server/treatment.lua   examination sessions, procedures (minigames), locks, panel updates
server/exports.lua     public API
server/interaction.lua "Examine patient" entry in the ui_interactobject world menu
client/panel.lua       DX examination panel
client/interaction.lua turns the world menus off during procedures / while the player is down
client/patient.lua     local player's own condition (overlay, control lock)
```

**Where the data lives**

| data | where | synced to |
|---|---|---|
| full medical state | server table `Patients[element]` | nobody (the server owns it) |
| `medic.status` (consciousness) | element data, broadcast | everyone, but only written on state changes |
| `spo2`, `heartRate` | element data, **subscribe** mode | only the medics examining / treating the patient (mg_airway reads them) |
| panel snapshot | `medic:panelUpdate` event | only the medics with the panel open, once per tick |
| own condition | `medic:selfStatus` event | the player patient, only on state changes |

Only elements that are not perfectly healthy are in the registry. The simulation timer runs only
while there is at least one patient. A patient with nothing left to simulate (no injuries, full
vitals, nobody examining it) is dropped automatically.

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
- **Heart rate / blood pressure** move towards targets based on the blood loss (shock classes:
  compensated to ~15%, then the pressure falls), pain (tachycardia) and hypoxia (bradycardia
  below 50% SpO2).
- **SpO2** drifts to the lowest target of the airway causes (suffocation, inhalation burn) or of
  shock, and recovers otherwise. A secured airway removes the airway causes.
- **Consciousness**: `unconscious` below 70% SpO2 or 65 mmHg systolic, and `dazed` below 88% /
  90 mmHg or at pain 70+.
- **Cardiac arrest** when the SpO2 reaches `ARREST_SPO2` (0) or the blood volume falls to 50%. The
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

| button | minigame | available when | success |
|---|---|---|---|
| Bandage | mg_arrows | an untreated wound / fracture / burn, or bleeding | treats the worst injury: bleeding stops (critical → mild), fracture splinted, burn dressed |
| CPR | mg_cpr | clinical death | ROSC chance (accuracy, +IV, +airway, 0 when the blood loss is too high), otherwise +45 s on the death timer |
| IV access | mg_intravenous | no IV yet | IV fluids run (rate scales with the quality). Difficulty rises with shock |
| Intubate | mg_airway | unconscious / clinical death, no tube | airway secured, suffocation treated. The patient is pre-oxygenated to 95%, then the SpO2 falls during the attempt |

The server checks every request (distance, role, patient state, one medic per procedure per
patient). When the minigame ends, the panel reopens with the result.

## Server exports

```lua
local data = exports.medical_system:getMedicalState(element)
-- { consciousness, consciousnessLabel, heartRate, systolic, diastolic, bloodPressure = "120/80",
--   spo2, bleeding (0-3), bleedingLabel, bloodVolume, bloodPercent, pain,
--   injuries = { { id, type, label, severity, severityLabel, bleeding, treated, treatedLabel } },
--   ivAccess, intubated, clinicalDeath, deathTimeLeft, dead, isPatient }

exports.medical_system:setMedicalState(element, key, value) -- true / false
--   heartRate     0 = cardiac arrest, > 0 during clinical death = return of circulation
--   systolic, diastolic, spo2, bloodVolume, pain (0-100, fades)
--   bleeding      0 stops every bleeding, 1-3 adds a bleeding that is not tied to an injury
--   ivAccess, intubated   booleans
--   consciousness "stable" (wakes / revives), "dazed" / "unconscious" (forced for KNOCKOUT_TIME),
--                 "clinical_death", "dead"
-- The simulation continues from the new value (e.g. a heart rate drifts back to its target).

local injuryId = exports.medical_system:applyInjury(element, injuryType, severity)
--   injuryType: "gunshot" | "fracture" | "burn" | "suffocation"
--   severity:   1-3 or "minor" | "serious" | "critical"

exports.medical_system:healCompletely(element) -- everything back to baseline, health 100

-- for the EMS job script
exports.medical_system:setPlayerMedic(player, true)   -- only used when MEDIC.REQUIRE_MEDIC_ROLE = true
exports.medical_system:isPlayerMedic(player)
exports.medical_system:openExamination(medic, target) -- open the panel from your own interaction
exports.medical_system:closeExamination(medic)
```

| injury | bleeding (minor/serious/critical) | other effects | treated by |
|---|---|---|---|
| gunshot | mild / severe / critical | pain | Bandage |
| fracture | – / – / mild (open) | high pain | Bandage (splint) |
| burn | – | plasma loss, pain, critical = inhalation injury (SpO2 → 80%) | Bandage (dressing), Intubate for the airway |
| suffocation | – | SpO2 → 88% / 65% / 0% | Intubate |

## Events (server, for other scripts)

```lua
addEventHandler("onMedicalInjury", root, function(injuryType, severity, injuryId) end)      -- source = patient
addEventHandler("onMedicalStateChange", root, function(newState, oldState) end)            -- consciousness changed
addEventHandler("onMedicalCardiacArrest", root, function() end)                            -- clinical death started
addEventHandler("onMedicalRevived", root, function() end)                                  -- ROSC
addEventHandler("onMedicalDeath", root, function() end)                                    -- biological death
addEventHandler("onMedicalTreatment", root, function(medic, action, success) end)          -- source = patient
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
