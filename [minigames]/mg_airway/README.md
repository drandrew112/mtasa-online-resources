# mg_airway

Airway management (endotracheal intubation) minigame. The player has to get a tube into the
trachea before the patient's **SpO2** drops below **80%**. There are four phases:

1. **Laryngoscopy** – hold **SPACE** to lift the laryngoscope. The tongue and epiglottis move out
   of the way. Keep the lift in the green zone for 1.5 s. Levering too hard chips a tooth.
2. **Pass the cords** – aim the tube tip with the **mouse** (with hand tremor) and hold **SPACE**
   to push it between the vocal cords. The larynx drifts around and the cords open and close:
   pushing against closed cords or tissue causes trauma, pushing into the oesophagus (the slit
   behind the arytenoids) is an oesophageal intubation.
3. **Tube depth** – **SPACE** push / **S** pull back, then release inside 20.5–23.5 cm at the teeth.
   Going past 25.5 cm is a right mainstem intubation (the tube is pulled back to 19 cm).
4. **Cuff pressure** – **SPACE** inflate / **S** deflate, then release inside 20–30 cmH2O. Air leaks
   past a soft cuff, and above 40 cmH2O the cuff damages the mucosa (it is deflated).

On harder difficulties blood runs into the view – hold **E** to suction it away.
Each mistake uses up one of the allowed mistakes; one more than `maxMistakes` fails the procedure.

## SpO2 comes from element data

The minigame does **not** own the patient's vitals. It reads them every frame from the patient
ped's element data, which the medic system writes:

| element data | config key | meaning |
|---|---|---|
| `spo2` | `AIRWAY.SPO2_DATA` | SpO2 in %, required for live mode |
| `heartRate` | `AIRWAY.HR_DATA` | heart rate, optional, only shown on the HUD |

The minigame only reads these values, it never writes them. When the SpO2 goes below
`AIRWAY.FAIL_SPO2` (80) the attempt fails with `"desaturated"`. The medic system decides what a
success or failure does to the patient. If the SpO2 stays up, the attempt is capped at
`AIRWAY.MAX_TIME` (180 s, reason `"timeout"`).

Fallback: if no ped is passed, or the ped has no `spo2` data when the game starts, the SpO2 is
simulated from the difficulty's `spo2Start` / `spo2Drain` (or the same options).

If a ped is passed, the player kneels behind its head (facing it), movement controls are locked
and the `BOMBER/BOM_Plant_Loop` animation loops for the whole game.

## Server exports

```lua
local id = exports.mg_airway:startAirwayGame(player, ped, options) -- session id or false
exports.mg_airway:stopAirwayGame(player)      -- fires onAirwayGameFinish with reason "cancelled"
exports.mg_airway:isAirwayGameActive(player)
```

- `ped` – optional ped/player being intubated (`nil` = no positioning, no animation)
- `options` – optional:
  - `difficulty` – `"easy"`, `"normal"` (default), `"hard"`, `"nightmare"`
  - `spo2Start`, `spo2Drain` – only for the fallback simulation (no `spo2` element data)
  - `maxMistakes` – mistakes allowed
  - `blood` – seconds between blood drops, or `false`

| difficulty | tremor | cords close | fallback SpO2 start / drain | fallback time limit | mistakes allowed | blood |
|---|---|---|---|---|---|---|
| easy      | low     | barely  | 98% / 0.35 per s | ~51 s | 3 | – |
| normal    | medium  | yes     | 96% / 0.50 per s | 32 s  | 2 | – |
| hard      | high    | mostly  | 94% / 0.65 per s | ~21 s | 1 | every ~6 s |
| nightmare | shaking | almost fully | 91% / 0.80 per s | ~14 s | 0 | every ~3.5 s |

Result:

```lua
addEventHandler("onAirwayGameFinish", root, function(success, score, time, mistakes, reason, sessionId, details)
    -- source = player
    -- score: 0-100 (0 when failed), time: seconds from the end of the countdown
    -- reason: "intubated" | "desaturated" | "too_many_mistakes"
    --         | "cancelled" | "died" | "quit" | "timeout" | "invalid"
    -- details = { difficulty, minSpO2, depth, cuffPressure,
    --             teeth, trauma, esophageal, bronchus, cuff }   -- mistake counters
end)
```

`details` is handy for role-play consequences (e.g. `details.teeth > 0` → the patient lost a tooth).
The server plays the animation (synced to everyone), stops it when the game ends, and sanity
checks the client result (session id, play time, mistake counts). In live mode it samples the
ped's `spo2` data itself (every 250 ms) for `minSpO2` and to confirm a `"desaturated"` result. The
score is recomputed on the server.

## Client exports

Local-only game, the server is not involved (the animation is only visible to this client):

```lua
exports.mg_airway:startAirwayGame(ped, options)
exports.mg_airway:stopAirwayGame()
exports.mg_airway:isAirwayGameActive()

addEventHandler("onClientAirwayGameFinish", localPlayer, function(success, score, time, mistakes, reason, sessionId, details) end)
```

`onClientAirwayGameFinish` also fires for server-started games (with `sessionId` set).

## Test command

Enabled while `AIRWAY.TEST_COMMAND = true` (`shared.lua`) – turn it off in production.

`/airwaytest [easy|normal|hard|nightmare] [0]` – a random emergency case (overdose, drowning,
motorbike crash, anaphylaxis, ...) with a random patient lying in front of you. Without a
difficulty the case decides it. The test ped gets `spo2` / `heartRate` element data that drops
like the medic system would, so the live element data path is what gets tested. Pass `0` as the
second argument to play without a ped (fallback simulation).

## Config

`shared.lua` → `AIRWAY` (difficulty presets, element data keys, SpO2 fail limit, max time, keys,
phase speeds and zones, animation, placement offset).
